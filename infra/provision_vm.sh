#!/bin/bash

# Provision Azure VM Script

# UTF-8 fallback (helps in some terminal environments)
export LANG=en_US.UTF-8
export PYTHONIOENCODING=utf-8

# Configuration Variables
resource_group="BasicMVCRG"
vm_name="BasicMVCVM"
location="northeurope"
admin_user="azureuser"
vm_port=5000
cloud_init_file="cloud-init_dotnet.yaml"

# Create Resource Group
echo "[INFO] Creating resource group: $resource_group"
az group create --location $location --name $resource_group

# Create Virtual Machine
echo "[INFO] Creating virtual machine: $vm_name"
az vm create \
    --name $vm_name \
    --resource-group $resource_group \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --generate-ssh-keys \
    --admin-username $admin_user \
    --custom-data @$cloud_init_file \
    --public-ip-sku Standard


# Open port 5000
echo "[INFO] Opening port $vm_port for incoming web traffic"
az vm open-port \
    --port $vm_port \
    --resource-group $resource_group \
    --name $vm_name \
    --priority 1001

# Get Public IP
echo "[INFO] Fetching public IP address of the VM..."
public_ip=$(az vm show -d -g $resource_group -n $vm_name --query publicIps -o tsv)

# Output Final Info
echo "[SUCCESS] Azure VM '$vm_name' is ready."
echo "[INFO] Access your ASP.NET Core app at: http://$public_ip:$vm_port"

# Fetch and display cloud-init log from the VM
echo "[INFO] Fetching cloud-init output log..."
ssh -o StrictHostKeyChecking=no $admin_user@$public_ip 'cat /var/log/cloud-init-success.log'


# After provisioning, to verify everything -> SSH into the VM and run: 
# cat /var/log/cloud-init-success.log
# This will show the log of the cloud-init process, including the .NET SDKs and Runtimes installed, and the status of the BasicMVC.service


# to delete VM
# az vm delete --name BasicMVCVM --resource-group BasicMVCRG --yes

