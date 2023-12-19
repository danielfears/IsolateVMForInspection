# Azure VM Quarantine and Inspection - PowerShell

## Description
This PowerShell script is designed to isolate a specific Azure Virtual Machine (VM) by moving it to a new subnet and setting up Azure Bastion for secure access. It is crafted to work both as a standalone script for local execution and as part of a GitLab CI/CD pipeline.

The script performs the following actions:
1. Authenticates with Azure using a service principal or interactive login.
2. Retrieves the virtual network address space associated with the VM.
3. Creates a new subnet for isolation purposes.
4. Creates a separate subnet for the Azure Bastion host.
5. Generates a new Network Security Group (NSG) and configures it to allow Bastion Host access only.
6. Associates the NSG with the isolation subnet.
7. Provisions a new public IP address for the Bastion host.
8. Quarantines the target VM by moving it into the isolation subnet.
9. Establishes a new Bastion host for secure connectivity.

## Prerequisites
- Azure PowerShell Module (Az Module)
- An active Azure subscription with appropriate permissions.
- For CI/CD pipeline execution: GitLab with a configured runner.

## Getting Started

### Local Execution
1. **Authentication**: The script checks for an existing Azure session and prompts for authentication if needed.
2. **Subscription and Resource Group**: Input your Azure Subscription ID and the name of the resource group containing the VM.
3. **Virtual Machine Selection**: Specify the VM name you intend to isolate.
4. **Network Configuration**: Provide CIDR blocks for the isolation and Bastion subnets.
5. **Execution**: Run the script in a PowerShell environment. The script creates network resources and reconfigures the VM.

### CI/CD Pipeline Execution
1. **Configuration**: Set the necessary environment variables in your GitLab CI/CD settings.
2. **Automation**: The `gitlab-ci.yml` file orchestrates the script execution based on the provided variables.

## Parameters
- `subscriptionId`: Azure Subscription ID.
- `VMresourceGroupName`: Resource Group name containing the VM.
- `vmName`: Name of the VM to isolate.
- `subnetRange`: CIDR for the new isolation subnet.
- `bastionSubnet`: CIDR for the Bastion subnet.

## Usage

### Local Execution
Execute the script in a PowerShell environment with the Azure PowerShell module installed.

```powershell
# Example command to execute the script, it will ask the user for the values it requires
.\IsolateVM.ps1

# Alternatively, you can pass in those values at runtime as follows
.\IsolateVM.ps1 -subscriptionId "your-subscription-id" -VMresourceGroupName "your-rg-name" -vmName "your-vm-name" -subnetRange "your-subnet-range" -bastionSubnet "your-bastion-subnet"
```

### CI/CD Pipeline
When running the pipeline manually, it will ask for user input parameters for use within the script. GitLab CI/CD pipeline will then automatically execute the script based on the defined stages in `gitlab-ci.yml`.

## Cleanup and Rollback
The script maintains a hashtable to track the creation of resources. In case of an error, it provides information about which resources were created and might need to be manually cleaned up.

## Contributing
Feel free to fork this repository and submit pull requests or issues for any enhancements or fixes.

## License
[MIT](LICENSE)

