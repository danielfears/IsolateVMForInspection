# Authored by Dan Fears - Microsoft

# Parameters for CI/CD pipeline value input
param(
    [string]$AzureTenantId,
    [string]$AzureClientId,
    [string]$AzureClientSecret,
    [string]$subscriptionId,
    [string]$VMresourceGroupName,
    [string]$vmName,
    [string]$subnetRange,
    [string]$bastionSubnet
)

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

# Iterate through the hashtable to output report of created resources
function Invoke-OutputResources {
    
    $checkAllTrue = $script:createdResources.Values -contains $false -eq $false # Check if all resources are created and createdResources hash table values set to true

    foreach ($key in $script:createdResources.Keys) {
        if ($script:createdResources[$key] -eq $true) {
            $outputMessage = "* $key"
            if (!$checkAllTrue) {
                $outputMessage += " will need to be deleted to re-run this script"
            }
            Write-Host $outputMessage
        }
    }
}

# Authenticate Azure Account and login
function Invoke-UserLogin {

    if ($AzureTenantId -and $AzureClientId -and $AzureClientSecret) {

        # Programmatic login
        $SecureClientSecret = ConvertTo-SecureString $AzureClientSecret -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($AzureClientId, $SecureClientSecret)
        
        Connect-AzAccount -ServicePrincipal -Tenant $AzureTenantId -Credential $Credential -ErrorAction Stop
        $context = Get-AzContext

        if ($context) {
            Write-Host "Successfully logged in with service principal. Context set to subscription: $($context.Subscription)"
        } else {
            Write-Host "Failed to log in with service principal. Please check your credentials."
            exit
        }
    } else {

        # Manual login
        $context = Get-AzContext

        if (!$context) {  
            Connect-AzAccount -ErrorAction Stop
            $context = Get-AzContext
            
            if ($context) {
                Write-Host "Successfully logged in manually. Context set to subscription: $($context.Subscription)"
            } else {
                Write-Host "Failed to log in manually. Please check your credentials."
                exit
            }
        } else {
            Write-Host "Already logged in and authenticated. Context set to subscription: $($context.Subscription)"
        }
    }
}

# Accept input from user for Subscription ID, validate and set context
function Invoke-SubscriptionInput {

    $allSubscriptions = Get-AzSubscription -ErrorAction SilentlyContinue

    if (!$allSubscriptions) {
        Write-Host "No subscriptions found or unable to retrieve subscriptions."
        exit
    }
    do {
        if (-not $script:subscriptionId) {
            Write-Host ""
            $script:subscriptionId = Read-Host -Prompt "Enter the Azure Subscription ID for the VM you want to isolate"
        }
        
        if (-not $script:subscriptionId) {
            Write-Host "No input entered. Please enter a valid Subscription ID."
            continue
        }

        $subscriptionExists = $allSubscriptions | Where-Object { $_.Id -eq $script:subscriptionId }

        if ($subscriptionExists) {
            try {
                Set-AzContext -Subscription $script:subscriptionId -ErrorAction Stop
                break
            }
            catch {
                Write-Host "Error setting context with Subscription ID '$script:subscriptionId': $_"
                continue
            }
        } else {
            Write-Host "Subscription ID '$script:subscriptionId' is invalid. Please enter a valid Subscription ID."
        }

    } while ($true)
}


# Accept input from user for Resource Group Name, validate and set variable
function Invoke-ResourceGroupInput {

    $allResourceGroups = Get-AzResourceGroup -ErrorAction SilentlyContinue

    if (!$allResourceGroups) {
        Write-Host "No resource groups found or unable to retrieve resource groups."
        exit
    }
    do {
        if (-not $script:VMresourceGroupName) {
            Write-Host ""
            $script:VMresourceGroupName = Read-Host -Prompt "Enter the name of the resource group"
        }
        
        if (-not $script:VMresourceGroupName) {
            Write-Host "No input entered. Please enter a valid resource group name."
            continue
        }
        $resourceGroupExists = $allResourceGroups | Where-Object { $_.ResourceGroupName -eq $script:VMresourceGroupName }
        if ($resourceGroupExists) {
            break
        } else {
            Write-Host "Resource group '$script:VMresourceGroupName' does not exist in the subscription. Please enter a valid resource group name."
        }
    } while ($true)
}


# Accept input for VM name and check if it exists in the resource group, validate and set variable
function Invoke-VMNameInput {

    $allVMs = Get-AzVM -ResourceGroupName $script:VMresourceGroupName -ErrorAction SilentlyContinue
    if ($null -eq $allVMs) {
        Write-Host "No Virtual Machines found in the resource group '$script:VMresourceGroupName'."
        exit
    }

    do {
        if (-not $script:vmName) {
            Write-Host ""
            $script:vmName = Read-Host -Prompt "Enter the name of the Virtual Machine"
        }

        # Check if VM exists
        $vmExists = $allVMs | Where-Object { $_.Name -eq $script:vmName }

        if ($vmExists) {
            break
        } else {
            Write-Host "No VM with the name '$script:vmName' found in the resource group '$script:VMresourceGroupName'. Please try again."
        }
    } while ($true)
}


# Get VM details and set variables
function Invoke-VMDetails {

    try {
        $vm = Get-AzVM -Name $vmName -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
        $nic = Get-AzNetworkInterface -ResourceGroupName $VMresourceGroupName | Where-Object { $_.Id -eq $vm.NetworkProfile.NetworkInterfaces.Id } -ErrorAction Stop
        $subnetId = $nic.IpConfigurations[0].Subnet.Id
        $subnet = Get-AzVirtualNetworkSubnetConfig -ResourceId $subnetId -ErrorAction Stop
        $script:vnet = Get-AzVirtualNetwork | Where-Object { $_.Subnets.Id -contains $subnet.Id } -ErrorAction Stop
        
        $script:vnetname = $script:vnet.Name
        $script:vnetRange = $script:vnet.AddressSpace.AddressPrefixes
        $script:location = $script:vnet.Location

        # Summarise user inputs and display on screen
        Write-Host " "
        Write-Host "Target Subscription ID is: $script:subscriptionId"
        Write-Host "Target Resource Group is: $script:VMresourceGroupName"
        Write-Host "Target Virtual Machine is: $script:vmName"
        Write-Host " "
        Write-Host "Virtual network range associated to VM is: $script:vnetRange"
        Write-Host " "
    }
    catch {
        Write-Host "Error: $_"
        exit
    }

}

# IP address validation function
function Invoke-IsValidIpAddress([string]$ip) { 
    $ipPattern = "\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}\b"
    return [System.Text.RegularExpressions.Regex]::IsMatch($ip, $ipPattern)
}

# Accept input from user for isolation subnet IP address range, validate and set variable
function Invoke-IsolationSubnetInput { 
    do {
        if (-not $script:subnetRange) {
            $script:subnetRange = Read-Host -Prompt "Enter Subnet Address Space (CIDR) for isolation subnet"
        }
        $isValid = Invoke-IsValidIpAddress -ip $script:subnetRange
        if (-not $isValid) {
            Write-Host "Invalid IP Address range. Please enter a valid IP Address range."
        }
    } while (-not $isValid)

    Write-Host "You entered a valid IP Address: $script:subnetRange"
}


# Accept input from user for Bastion subnet IP address range, validate and set variable
function Invoke-BastionSubnetInput { 

    do {
        if (-not $script:bastionSubnet) {
            $script:bastionSubnet = Read-Host -Prompt "Enter Subnet Address Space (CIDR) for Bastion subnet"
        }
        $isValid = Invoke-IsValidIpAddress -ip $script:bastionSubnet
        if (-not $isValid) {
            Write-Host "Invalid IP Address range. Please enter a valid IP Address range."
        }
    } while (-not $isValid)

    Write-Host "You entered a valid IP Address: $script:bastionSubnet"
    
}

# Check blast radius of target VM
# function Invoke-BlastRadiusCheck { 

#     # VMs connected within same subnet
#     $allVMs = Get-AzVM
#     $connectedVMs = @()
#     foreach ($eachVM in $allVMs) {
#         $vmNic = Get-AzNetworkInterface -ResourceId $eachVM.NetworkProfile.NetworkInterfaces.Id
#         if ($vmNic.IpConfigurations[0].Subnet.Id -eq $subnetId) {
#             $connectedVMs += $eachVM
#         }
#     }

#     # Get the virtual network of the VM
#     $vNet = Get-AzVirtualNetwork | Where-Object { $_.Subnets.Id -contains $subnetId }

#     # Check if virtual network is found
#     if ($null -eq $vNet) {
#         Write-Host "Virtual Network not found for the VM."
#         exit
#     }

#     # Get all peered networks
#     $peeredNetworks = $vNet.VirtualNetworkPeerings | Where-Object { $_.PeeringState -eq "Connected" }

#     # List VMs in peered networks
#     foreach ($peering in $peeredNetworks) {
#         $peeredVNet = Get-AzVirtualNetwork -ResourceGroupName $peering.RemoteVirtualNetwork.ResourceGroupName -Name $peering.RemoteVirtualNetwork.Name

#         # List all subnets in the peered network
#         foreach ($subnet in $peeredVNet.Subnets) {
#             $subnetVMs = Get-AzVM | Where-Object { $_.NetworkProfile.NetworkInterfaces.Subnet.Id -eq $subnet.Id }
            
#             foreach ($subnetVM in $subnetVMs) {
#                 # Add VMs from peered network to the list
#                 $connectedVMs += $subnetVM
#             }
#         }
#     }

#     # Remove duplicates and the inspected VM itself
#     $connectedVMs = $connectedVMs | Where-Object { $_.Id -ne $vm.Id } | Sort-Object -Property Id -Unique

#     # Output the VMs connected in peered networks
#     Write-Host "VMs in peered networks of $vmName :"
#     $connectedVMs | Format-Table Name, ResourceGroupName, Location

#     # VMs connected via virtual network peering


#     Write-Host "VMs in the same subnet as $vmName :"
#     $connectedVMs | Format-Table Name, ResourceGroupName, Location

# }

# Create Isolation & Bastion subnets
function Invoke-CreateSubnets {

    try {
        $script:vnet = Get-AzVirtualNetwork -Name $script:vnetname -ResourceGroupName $script:VMresourceGroupName -ErrorAction Stop
        $isolationSubnetConfig = New-AzVirtualNetworkSubnetConfig -Name $script:isolationSubnetName -AddressPrefix $script:subnetRange -ErrorAction Stop
        $bastionSubnetConfig = New-AzVirtualNetworkSubnetConfig -Name $script:bastionSubnetName -AddressPrefix $script:bastionSubnet -ErrorAction Stop
        $script:vnet.Subnets.Add($isolationSubnetConfig)
        $script:vnet.Subnets.Add($bastionSubnetConfig)
        Set-AzVirtualNetwork -VirtualNetwork $script:vnet -ErrorAction Stop

        $script:createdResources["Isolation-Subnet"] = $true
        $script:createdResources["AzureBastionSubnet"] = $true
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }
}


# Create NSG and Allow Bastion Host Access
function Invoke-CreateNSG {

    try {
        $script:nsg = New-AzNetworkSecurityGroup -ResourceGroupName $script:VMresourceGroupName -Location $script:location -Name $script:nsgName -ErrorAction Stop
        $rule1 = New-AzNetworkSecurityRuleConfig -Name "AllowBastionToIsolation" -Description "Allow traffic from Bastion to Isolation Subnet" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix $script:bastionSubnet -SourcePortRange "*" -DestinationAddressPrefix $script:subnetRange -DestinationPortRange "*" -ErrorAction Stop
        $rule2 = New-AzNetworkSecurityRuleConfig -Name "DenyAllInbound" -Description "Deny all other inbound traffic" -Access Deny -Protocol "*" -Direction Inbound -Priority 4096 -SourceAddressPrefix "*" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "*" -ErrorAction Stop
        $script:nsg.SecurityRules.Add($rule1)
        $script:nsg.SecurityRules.Add($rule2)
        Set-AzNetworkSecurityGroup -NetworkSecurityGroup $script:nsg -ErrorAction Stop

        $script:createdResources["Isolation-NSG"] = $true
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }
}


# Associate NSG with Subnet
function Invoke-AssociateNSGtoSubnet {

    try {
        $subnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $script:isolationSubnetName -VirtualNetwork $script:vnet -ErrorAction Stop
        $subnetConfig.NetworkSecurityGroup = $script:nsg
        $script:vnet | Set-AzVirtualNetwork -ErrorAction Stop
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }

}


# Create Public IP for Bastion Host
function Invoke-CreateBastionPIP {

    try {
        # Creating the Public IP address and storing it in a script-scoped variable
        $script:BastionPIP = New-AzPublicIpAddress -Name $script:bastionPIPName -ResourceGroupName $script:VMresourceGroupName -Location $script:location -AllocationMethod Static -Sku Standard -ErrorAction Stop

        $script:createdResources["Bastion Public IP address"] = $true
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }
}


 # Move VM to Isolation Subnet
 function Invoke-MoveVMtoIsolationSubnet {
    try {
        # Retrieving the VM and NIC details
        $vm = Get-AzVM -Name $script:vmName -ResourceGroupName $script:VMresourceGroupName -ErrorAction Stop
        $nic = Get-AzNetworkInterface -ResourceGroupName $script:VMresourceGroupName | Where-Object { $_.Id -eq $vm.NetworkProfile.NetworkInterfaces.Id } -ErrorAction Stop
        
        # Retrieve the virtual network and then the specific subnet
        $vnet = Get-AzVirtualNetwork -Name $script:vnetname -ResourceGroupName $script:VMresourceGroupName -ErrorAction Stop
        $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $script:isolationSubnetName }
        $subnetId = $subnet.Id

        # Ensure we have a valid subnet ID
        if (-not $subnetId) {
            throw "Subnet ID is not valid or not found."
        }

        # Updating the NIC configuration
        $nic.IpConfigurations[0].Subnet.Id = $subnetId
        Set-AzNetworkInterface -NetworkInterface $nic -ErrorAction Stop

        # Updating the VM configuration
        Update-AzVM -VM $vm -ResourceGroupName $script:VMresourceGroupName -ErrorAction Stop
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }
}



# Create Bastion Host
function Invoke-CreateBastionHost { 

    try {
        $BastionPIP = Get-AzPublicIpAddress -Name $script:bastionPIPName -ResourceGroupName $script:VMresourceGroupName -ErrorAction Stop
        New-AzBastion -ResourceGroupName $script:VMresourceGroupName -Name $script:bastionName -PublicIpAddress $BastionPIP -VirtualNetwork $script:vnet -ErrorAction Stop -AsJob

        $script:createdResources["Isolation-Bastion"] = $true
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }
}


# Output completion message and list of created resources
function Invoke-CompletionOutput { 

    Write-Host " "
    Write-Host "Script completed successfully! The following resources have been created:"
    Write-Host " "

    Invoke-OutputResources

    Write-Host " "
    Write-Host "VM: $script:vmName has been moved to the Isolation Subnet and is now ready for inspection."

}

# Main function to run the script
function Invoke-IsolateVM { 

    Invoke-UserLogin
    Invoke-SubscriptionInput
    Invoke-ResourceGroupInput
    Invoke-VMNameInput
    Invoke-VMDetails
    Invoke-IsolationSubnetInput
    Invoke-BastionSubnetInput
    Invoke-CreateSubnets
    Invoke-CreateNSG
    Invoke-AssociateNSGtoSubnet
    Invoke-CreateBastionPIP
    Invoke-MoveVMtoIsolationSubnet
    Invoke-CreateBastionHost
    Invoke-CompletionOutput

}

# Run VM isolation function
Invoke-IsolateVM