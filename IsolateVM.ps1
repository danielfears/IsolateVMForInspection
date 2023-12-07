# Authored by Dan Fears - Microsoft

# What this script does in order

# 1. Gets the Virtual Network address space associated to the VM
# 2. Creates a new subnet for the Isolation Subnet
# 3. Creates a new subnet for the Bastion Host
# 4. Creates a new NSG and allows Bastion Host access
# 5. Associates the NSG with the Isolation Subnet
# 6. Creates a new Public IP for the Bastion Host
# 7. Moves the VM to the Isolation Subnet
# 8. Creates a new Bastion Host

# Constants

$bastionName = "Isolation-Bastion"
$nsgName = "Isolation-NSG"
$isolationSubnetName = "Isolation-Subnet"
$bastionSubnetName = "AzureBastionSubnet"
$bastionPIPName = "BastionPIP"

# Hash table that outputs what resources have been created and need cleaning up, updates on each successful resource created

$createdResources = @{
    "Isolation-Subnet" = $false
    "AzureBastionSubnet" = $false
    "Bastion Public IP address" = $false
    "Isolation-NSG" = $false
    "Isolation-Bastion" = $false
}

# Function to iterate through the hashtable to output report of created resources

function OutputResources {
    
    $checkAllTrue = $createdResources.Values -contains $false -eq $false # Check if all resources are created and createdResources hash table values set to true

    foreach ($key in $createdResources.Keys) {
        if ($createdResources[$key] -eq $true) {
            $outputMessage = "* $key"
            if (!$checkAllTrue) {
                $outputMessage += " will need to be deleted to re-run this script"
            }
            Write-Host $outputMessage
        }
    }
}

# Authenticate Azure Account and login

$context = Get-AzContext
if (!$context) {  
    Connect-AzAccount
    $context = Get-AzContext
    if ($context) {
        Write-Host "Successfully logged in. Context set to subscription: $($context.Subscription)"
    } else {
        Write-Host "Failed to log in. Please check your credentials."
        exit
    }
} else {
    Write-Host "Already logged in and authenticated. Context set to subscription: $($context.Subscription)"
}

# Accept input from user for Subscription ID
# Validate and set the subscription ID

$allSubscriptions = Get-AzSubscription -ErrorAction SilentlyContinue

if (!$allSubscriptions) {
    Write-Host "No subscriptions found or unable to retrieve subscriptions."
    exit
}
do {
    $subscriptionId = Read-Host -Prompt "Enter the Azure Subscription ID for the VM you want to isolate:"
    
    if (-not $subscriptionId) {
        Write-Host "No input entered. Please enter a valid Subscription ID."
        continue
    }
    $subscriptionExists = $allSubscriptions | Where-Object { $_.Id -eq $subscriptionId }
    if ($subscriptionExists) {
        try {
            Set-AzContext -Subscription $subscriptionId -ErrorAction Stop
            break
        }
        catch {
            Write-Host "Error setting context with Subscription ID '$subscriptionId': $_"
            continue
        }
    } else {
        Write-Host "Subscription ID '$subscriptionId' is invalid. Please enter a valid Subscription ID."
    }
} while ($true)

# Accept input from user for Resource Group Name
# Validate and set the Resource Group Name

$allResourceGroups = Get-AzResourceGroup -ErrorAction SilentlyContinue

if (!$allResourceGroups) {
    Write-Host "No resource groups found or unable to retrieve resource groups."
    exit
}
do {
    $VMresourceGroupName = Read-Host -Prompt "Enter the name of the resource group"
    
    if (-not $VMresourceGroupName) {
        Write-Host "No input entered. Please enter a valid resource group name."
        continue
    }
    $resourceGroupExists = $allResourceGroups | Where-Object { $_.ResourceGroupName -eq $VMresourceGroupName }
    if ($resourceGroupExists) {
        break
    } else {
        Write-Host "Resource group '$VMresourceGroupName' does not exist in the subscription. Please enter a valid resource group name."
    }
} while ($true)

# Accept input for VM name and check if it exists in the resource group
# Validate and set the target Virtual Machine name

$allVMs = Get-AzVM -ResourceGroupName $VMresourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $allVMs) {
    Write-Host "No Virtual Machines found in the resource group '$VMresourceGroupName'."
    exit
}

do {
    $vmName = Read-Host -Prompt "Enter Virtual Machine Name"
    $vmExists = $allVMs | Where-Object { $_.Name -eq $vmName }

    if ($vmExists) {
        Write-Host "A VM with the name '$vmName' exists in the resource group '$VMresourceGroupName'."
        break
    } else {
        Write-Host "No VM with the name '$vmName' found in the resource group '$VMresourceGroupName'. Please try again."
    }
} while ($true)


try {
    $vm = Get-AzVM -Name $vmName -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
    $nic = Get-AzNetworkInterface -ResourceGroupName $VMresourceGroupName | Where-Object { $_.Id -eq $vm.NetworkProfile.NetworkInterfaces.Id } -ErrorAction Stop
    $subnetId = $nic.IpConfigurations[0].Subnet.Id
    $subnet = Get-AzVirtualNetworkSubnetConfig -ResourceId $subnetId -ErrorAction Stop
    $vnet = Get-AzVirtualNetwork | Where-Object { $_.Subnets.Id -contains $subnet.Id } -ErrorAction Stop
    $vnetname = $vnet.Name
    $vnetRange = $vnet.AddressSpace.AddressPrefixes

    $location = $vnet.Location
}
catch {
    Write-Host "Error: $_"
    exit
}

Clear-Host

Write-Host "Target Subscription ID is: $subscriptionId"
Write-Host "Target Resource Group is: $VMresourceGroupName"
Write-Host "Target Virtual Machine is: $vmName"
Write-Host " "
Write-Host "Virtual network range associated to VM is: $vnetRange"
Write-Host " "


# IP address validation function

function IsValidIpAddress([string]$ip) {
    $ipPattern = "\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}\b"
    return [System.Text.RegularExpressions.Regex]::IsMatch($ip, $ipPattern)
}

# Accept input from user for isolation subnet IP address range
# Validate and set the isolation subnet IP address range

do {
    $subnetRange = Read-Host -Prompt "Enter Subnet Address Space (CIDR) for isolation subnet"
    $isValid = IsValidIpAddress -ip $subnetRange
    if (-not $isValid) {
        Write-Host "Invalid IP Address range. Please enter a valid IP Address range."
    }
} while (-not $isValid)

Write-Host "You entered a valid IP Address: $subnetRange"

# Accept input from user for Bastion subnet IP address range
# Validate and set the Bastion subnet IP address range

do {
    $bastionSubnet = Read-Host -Prompt "Enter Subnet Address Space (CIDR) for Bastion subnet"
    $isValid = IsValidIpAddress -ip $bastionSubnet
    if (-not $isValid) {
        Write-Host "Invalid IP Address range. Please enter a valid IP Address range."
    }
} while (-not $isValid)

Write-Host "You entered a valid IP Address: $bastionSubnet"


# Create Isolation & Bastion subnets

try {
    $vnet = Get-AzVirtualNetwork -Name $vnetname -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
    $isolationSubnetConfig = New-AzVirtualNetworkSubnetConfig -Name $isolationSubnetName -AddressPrefix $subnetRange -ErrorAction Stop
    $bastionSubnetConfig = New-AzVirtualNetworkSubnetConfig -Name $bastionSubnetName -AddressPrefix $bastionSubnet -ErrorAction Stop
    $vnet.Subnets.Add($isolationSubnetConfig)
    $vnet.Subnets.Add($bastionSubnetConfig)
    Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop
}
catch {
    Write-Host "Error: $_"
    foreach ($key in $createdResources.Keys) {
        if ($createdResources[$key] -eq $true) {
            Write-Host "$key will need to be deleted to re-run this script"
        }
    }
    exit
}

$createdResources["Isolation-Subnet"] = $true
$createdResources["AzureBastionSubnet"] = $true

# Create NSG and Allow Bastion Host Access

try {
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $VMresourceGroupName -Location $location -Name $nsgName -ErrorAction Stop
    $rule1 = New-AzNetworkSecurityRuleConfig -Name "AllowBastionToIsolation" -Description "Allow traffic from Bastion to Isolation Subnet" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix $bastionSubnet -SourcePortRange "*" -DestinationAddressPrefix $subnetRange -DestinationPortRange "*" -ErrorAction Stop
    $rule2 = New-AzNetworkSecurityRuleConfig -Name "DenyAllInbound" -Description "Deny all other inbound traffic" -Access Deny -Protocol "*" -Direction Inbound -Priority 4096 -SourceAddressPrefix "*" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "*" -ErrorAction Stop
    $nsg.SecurityRules.Add($rule1)
    $nsg.SecurityRules.Add($rule2)
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg -ErrorAction Stop
}
catch {
    Write-Host "Error: $_"
    foreach ($key in $createdResources.Keys) {
        if ($createdResources[$key] -eq $true) {
            Write-Host "$key will need to be deleted to re-run this script"
        }
    }
    exit
}

$createdResources["Isolation-NSG"] = $true

# Associate NSG with Subnet

try {
    $vnet = Get-AzVirtualNetwork -Name $vnet.name -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
    $subnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $isolationSubnetName -VirtualNetwork $vnet -ErrorAction Stop
    $subnetConfig.NetworkSecurityGroup = $nsg
    $vnet | Set-AzVirtualNetwork -ErrorAction Stop
}
catch {
    Write-Host "Error: $_"
    OutputResources
    exit
}

# Create Public IP for Bastion Host

try {
    $BastionPIP = New-AzPublicIpAddress -Name $bastionPIPName -ResourceGroupName $VMresourceGroupName -Location $location -AllocationMethod Static -Sku Standard -ErrorAction Stop
}
catch {
    Write-Host "Error: $_"
    OutputResources
    exit
}

$createdResources["Bastion Public IP address"] = $true

# Move VM to Isolation Subnet

try {
    $vm = Get-AzVM -Name $vmName -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
    $nic = Get-AzNetworkInterface -ResourceGroupName $VMresourceGroupName | Where-Object { $_.Id -eq $vm.NetworkProfile.NetworkInterfaces.Id } -ErrorAction Stop
    $newSubnetId = Get-AzVirtualNetworkSubnetConfig -Name $isolationSubnetName -VirtualNetwork $vnet -ErrorAction Stop
    $nic.IpConfigurations[0].Subnet.Id = $newSubnetId.Id
    Set-AzNetworkInterface -NetworkInterface $nic -ErrorAction Stop
    Update-AzVM -VM $vm -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
}
catch {
    Write-Host "Error: $_"
    OutputResources
    exit
}

# Create Bastion Host

try {
    $BastionPIP = Get-AzPublicIpAddress -Name $bastionPIPName -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
    $vnet = Get-AzVirtualNetwork -Name $vnet.name -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
    $bastion = New-AzBastion -ResourceGroupName $VMresourceGroupName -Name $bastionName -PublicIpAddress $BastionPIP -VirtualNetwork $vnet -ErrorAction Stop -AsJob
}
catch {
    Write-Host "Error: $_"
    OutputResources
    exit
}

$createdResources["Isolation-Bastion"] = $true

Write-Host "Script completed successfully! The following resources have been created:"
Write-Host " "

#Running resource output function

OutputResources

Write-Host " "
Write-Host "VM: $vmName has been moved to the Isolation Subnet and is now ready for inspection."