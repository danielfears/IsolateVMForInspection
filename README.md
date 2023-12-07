# Azure VM Isolation PowerShell Script

## Description
This PowerShell script, authored by Dan Fears at Microsoft, automates the process of isolating a specific Azure Virtual Machine (VM) into a new subnet and setting up an Azure Bastion host for secure access. The script performs the following key tasks:
1. Retrieves the virtual network address space associated with the VM.
2. Creates a new subnet for isolation purposes.
3. Creates a separate subnet for the Azure Bastion host.
4. Generates a new Network Security Group (NSG) and configures it to allow Bastion Host access.
5. Associates the NSG with the isolation subnet.
6. Provisions a new public IP address for the Bastion host.
7. Moves the specified VM into the isolation subnet.
8. Establishes a new Bastion host for secure connectivity.

## Prerequisites
- Azure PowerShell Module (Az Module)
- Access to an Azure subscription with permissions to manage VMs, Virtual Networks, NSGs, and Public IP addresses.

## Getting Started
1. **Authenticate**: The script checks for an active Azure session and prompts for login if not already authenticated.
2. **Subscription and Resource Group**: You are prompted to enter a valid Azure Subscription ID and the name of the resource group containing the VM.
3. **Virtual Machine Selection**: Enter the name of the VM you wish to isolate.
4. **Network Configuration**: You will be prompted to enter CIDR blocks for both the isolation and Bastion subnets.
5. **Execution**: The script then proceeds to create the necessary network resources and reconfigures the VM.

## Parameters
- **Subscription ID**: The ID of the Azure Subscription where the VM is located.
- **Resource Group Name**: The name of the Resource Group containing the VM.
- **Virtual Machine Name**: The name of the VM to be isolated.
- **Isolation Subnet CIDR**: CIDR block for the new isolation subnet.
- **Bastion Subnet CIDR**: CIDR block for the new Bastion subnet.

## Usage
Run the script in a PowerShell environment with Azure PowerShell module installed. Follow the on-screen prompts to input the required parameters.

```powershell
# Example command to execute the script
.\VMIsolationBastionSetup.ps1
```

## Cleanup and Rollback
The script maintains a hashtable to track the creation of resources. In case of an error, it provides information about which resources were created and might need to be manually cleaned up.

## Contributing
Feel free to fork this repository and submit pull requests or issues for any enhancements or fixes.

## License
[MIT](LICENSE)
