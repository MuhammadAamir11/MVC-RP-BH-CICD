#!/bin/bash

# 🌍 Provision Azure VM Script (with Emoji Logging)

# 🧠 Set UTF-8 encoding to prevent symbol-related errors
export LANG=en_US.UTF-8
export PYTHONIOENCODING=utf-8

# ⚙️ Configuration Variables
resource_group="BasicMVCRG"
vm_name="BasicMVCVM"
location="northeurope"
admin_user="azureuser"
vm_port=5000
cloud_init_file="cloud-init_dotnet.yaml"

# 🏗️ Create Azure Resource Group
echo "📦 Creating resource group: $resource_group"
az group create --location $location --name $resource_group

# 🖥️ Create Azure Virtual Machine
echo "💻 Creating virtual machine: $vm_name"
az vm create \
    --name $vm_name \
    --resource-group $resource_group \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --generate-ssh-keys \
    --admin-username $admin_user \
    --custom-data @$cloud_init_file \
    --public-ip-sku Standard

# 🔓 Open port 5000 for web traffic
echo "🌐 Opening port $vm_port for incoming web traffic"
az vm open-port \
    --port $vm_port \
    --resource-group $resource_group \
    --name $vm_name \
    --priority 1001

# 🌍 Get Public IP of the VM
echo "🌐 Fetching public IP address of the VM..."
public_ip=$(az vm show -d -g $resource_group -n $vm_name --query publicIps -o tsv)

# ✅ Summary Output
echo "✅ Azure VM '$vm_name' is ready."
echo "🚀 Access your ASP.NET Core app at: http://$public_ip:$vm_port"

# ⏳ Wait for cloud-init log to appear
echo "📄 Waiting for /var/log/cloud-init-success.log to be created..."

for i in {1..10}; do
  if ssh -o StrictHostKeyChecking=no $admin_user@$public_ip 'test -f /var/log/cloud-init-success.log'; then
    echo "✅ Log is ready!"
    ssh -o StrictHostKeyChecking=no $admin_user@$public_ip 'cat /var/log/cloud-init-success.log'
    break
  else
    echo "⏱️  Log not ready yet... retrying in 10s"
    sleep 10
  fi
done

