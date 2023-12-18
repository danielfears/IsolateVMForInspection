# Authored by Dan Fears - Microsoft

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

function Invoke-OutputResources {
    
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

function Invoke-UserLogin { # Authenticate Azure Account and login

    $context = Get-AzContext

    if (!$context) {  

        Connect-AzAccount -ErrorAction Stop
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

}

function Invoke-SubscriptionInput { # Accept input from user for Subscription ID, validate and set context

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
}

function Invoke-ResourceGroupInput { # Accept input from user for Resource Group Name, validate and set variable

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
}

function Invoke-VMNameInput { # Accept input for VM name and check if it exists in the resource group, validate and set variable

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
}

function Invoke-VMDetails { # Get VM details and set variables

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

}

Clear-Host

Write-Host "Target Subscription ID is: $subscriptionId"
Write-Host "Target Resource Group is: $VMresourceGroupName"
Write-Host "Target Virtual Machine is: $vmName"
Write-Host " "
Write-Host "Virtual network range associated to VM is: $vnetRange"
Write-Host " "


function Invoke-IsValidIpAddress([string]$ip) { # IP address validation function
    $ipPattern = "\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}\b"
    return [System.Text.RegularExpressions.Regex]::IsMatch($ip, $ipPattern)
}

function Invoke-IsolationSubnetInput { # Accept input from user for isolation subnet IP address range, validate and set variable

    do {
        $subnetRange = Read-Host -Prompt "Enter Subnet Address Space (CIDR) for isolation subnet"
        $isValid = Invoke-IsValidIpAddress -ip $subnetRange
        if (-not $isValid) {
            Write-Host "Invalid IP Address range. Please enter a valid IP Address range."
        }
    } while (-not $isValid)

    Write-Host "You entered a valid IP Address: $subnetRange"
    
}

function Invoke-BastionSubnetInput { # Accept input from user for Bastion subnet IP address range, validate and set variable

    do {
        $bastionSubnet = Read-Host -Prompt "Enter Subnet Address Space (CIDR) for Bastion subnet"
        $isValid = IsValidIpAddress -ip $bastionSubnet
        if (-not $isValid) {
            Write-Host "Invalid IP Address range. Please enter a valid IP Address range."
        }
    } while (-not $isValid)

    Write-Host "You entered a valid IP Address: $bastionSubnet"
    
}

# function Invoke-BlastRadiusCheck { # Check blast radius of target VM

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

function Invoke-CreateSubnets { # Create Isolation & Bastion subnets

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
        Invoke-OutputResources
        exit
    }

    $createdResources["Isolation-Subnet"] = $true
    $createdResources["AzureBastionSubnet"] = $true

}

function Invoke-CreateNSG { # Create NSG and Allow Bastion Host Access

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
        Invoke-OutputResources
        exit
    }

    $createdResources["Isolation-NSG"] = $true

}

function Invoke-AssociateNSGtoSubnet { # Associate NSG with Subnet

    try {
        $vnet = Get-AzVirtualNetwork -Name $vnet.name -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
        $subnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $isolationSubnetName -VirtualNetwork $vnet -ErrorAction Stop
        $subnetConfig.NetworkSecurityGroup = $nsg
        $vnet | Set-AzVirtualNetwork -ErrorAction Stop
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }

}

function Invoke-CreateBastionPIP { # Create Public IP for Bastion Host

    try {
        $BastionPIP = New-AzPublicIpAddress -Name $bastionPIPName -ResourceGroupName $VMresourceGroupName -Location $location -AllocationMethod Static -Sku Standard -ErrorAction Stop
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }

    $createdResources["Bastion Public IP address"] = $true

}

function Invoke-MoveVMtoIsolationSubnet { # Move VM to Isolation Subnet

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
        Invoke-OutputResources
        exit
    }

}

function Invoke-CreateBastionHost { # Create Bastion Host

    try {
        $BastionPIP = Get-AzPublicIpAddress -Name $bastionPIPName -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
        $vnet = Get-AzVirtualNetwork -Name $vnet.name -ResourceGroupName $VMresourceGroupName -ErrorAction Stop
        New-AzBastion -ResourceGroupName $VMresourceGroupName -Name $bastionName -PublicIpAddress $BastionPIP -VirtualNetwork $vnet -ErrorAction Stop -AsJob
    }
    catch {
        Write-Host "Error: $_"
        Invoke-OutputResources
        exit
    }

    $createdResources["Isolation-Bastion"] = $true

}

function Invoke-CompletionOutput { # Output completion message and list of created resources

    Write-Host " "
    Write-Host "Script completed successfully! The following resources have been created:"
    Write-Host " "

    Invoke-OutputResources

    Write-Host " "
    Write-Host "VM: $vmName has been moved to the Isolation Subnet and is now ready for inspection."

}

function Invoke-IsolateVM { # Main function to run the script

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