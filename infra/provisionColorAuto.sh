#!/bin/bash

# 🌍 Provision Azure VM + Deploy ASP.NET Core App Automatically (Clean Arch to /opt/BasicMVC)

# 🧠 Step 1: Environment Setup
export LANG=en_US.UTF-8
export PYTHONIOENCODING=utf-8

# ⚙️ Step 2: Configuration Variables
resource_group="BasicMVCRG"
vm_name="BasicMVCVM"
location="northeurope"
admin_user="azureuser"
vm_port=5000
cloud_init_file="cloud-init_dotnet.yaml"
publish_dir="./publish"
remote_dir="/opt/BasicMVC"
project_path="/c/Git/AzurePractice/BasicMVC/basicmvc.csproj"


# 🔄 Step 3: Publish ASP.NET Core App
echo "🔄 Step 3: Publishing app..."
echo "🛠️  Running: dotnet publish -c Release -o $publish_dir"
dotnet publish "$project_path" -c Release -o "$publish_dir"

if [ $? -ne 0 ]; then
  echo "❌ dotnet publish failed. Exiting."
  exit 1
fi

# 🧱 Step 4: Provision Azure Resources
echo "🧱 Step 4: Provisioning Azure VM..."

echo "📦 Creating resource group: $resource_group"
az group create --location $location --name $resource_group

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

echo "🌐 Opening port $vm_port for web traffic"
az vm open-port \
  --port $vm_port \
  --resource-group $resource_group \
  --name $vm_name \
  --priority 1001

# 🔧 ADDITION TO YOUR EXISTING SCRIPT
# Add this after your ASP.NET app VM deployment (Step 4 in your script)

# 🌐 Step 4.1: Create VNet and Subnets
vnet_name="BasicMVCVNet"
app_subnet="AppSubnet"
proxy_subnet="ProxySubnet"
app_subnet_prefix="10.0.1.0/24"
proxy_subnet_prefix="10.0.2.0/24"
address_prefix="10.0.0.0/16"

nsg_app="AppNSG"
nsg_proxy="ProxyNSG"
proxy_vm_name="ProxyVM"


# Create Virtual Network and Subnets
echo "🌐 Creating Virtual Network and Subnets..."
az network vnet create \
  --resource-group $resource_group \
  --name $vnet_name \
  --address-prefix $address_prefix \
  --subnet-name $app_subnet \
  --subnet-prefix $app_subnet_prefix

# Create Proxy Subnet
az network vnet subnet create \
  --resource-group $resource_group \
  --vnet-name $vnet_name \
  --name $proxy_subnet \
  --address-prefix $proxy_subnet_prefix

# Create NSGs
echo "🛡️ Creating Network Security Groups..."
az network nsg create --resource-group $resource_group --name $nsg_app
az network nsg create --resource-group $resource_group --name $nsg_proxy

# Allow port 5000 in AppNSG from ProxySubnet only
az network nsg rule create \
  --resource-group $resource_group \
  --nsg-name $nsg_app \
  --name AllowAppPort5000 \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix $proxy_subnet_prefix \
  --source-port-range '*' \
  --destination-address-prefix '*' \
  --destination-port-range 5000

# Allow HTTP (port 80) in ProxyNSG from internet
az network nsg rule create \
  --resource-group $resource_group \
  --nsg-name $nsg_proxy \
  --name AllowHTTP \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix Internet \
  --source-port-range '*' \
  --destination-address-prefix '*' \
  --destination-port-range 80

# Attach NSGs to subnets
az network vnet subnet update \
  --vnet-name $vnet_name \
  --resource-group $resource_group \
  --name $app_subnet \
  --network-security-group $nsg_app

az network vnet subnet update \
  --vnet-name $vnet_name \
  --resource-group $resource_group \
  --name $proxy_subnet \
  --network-security-group $nsg_proxy

# 🚀 Step 4.2: Deploy Proxy VM (NGINX)
echo "🚀 Deploying Proxy VM (NGINX)..."
az vm create \
  --resource-group $resource_group \
  --name $proxy_vm_name \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username $admin_user \
  --generate-ssh-keys \
  --subnet $proxy_subnet \
  --vnet-name $vnet_name \
  --public-ip-sku Standard \
  --custom-data @cloud-init_proxy.yaml

# Fetch public IP of ProxyVM
proxy_ip=$(az vm show -d -g $resource_group -n $proxy_vm_name --query publicIps -o tsv)
echo "✅ NGINX Reverse Proxy deployed! Access your app via: http://$proxy_ip"






# 🌍 Step 5: Get Public IP & Wait for cloud-init
echo "🌍 Fetching public IP..."
public_ip=$(az vm show -d -g $resource_group -n $vm_name --query publicIps -o tsv)

echo "✅ Azure VM '$vm_name' is ready!"
echo "🌐 App will be available at: http://$public_ip:$vm_port"

echo "⏳ Waiting for /var/log/cloud-init-success.log..."
for i in {1..10}; do
  if ssh -o StrictHostKeyChecking=no $admin_user@$public_ip 'test -f /var/log/cloud-init-success.log'; then
    echo "📄 Cloud-init finished. Output:"
    ssh -o StrictHostKeyChecking=no $admin_user@$public_ip 'cat /var/log/cloud-init-success.log'
    break
  else
    echo "⏱️  Not ready yet. Retrying in 10s..."
    sleep 10
  fi
done

# 📤 Step 6: Deploy App Files to /opt/BasicMVC
echo "📤 Step 6: Deploying files to /opt/BasicMVC..."

echo "📁 Uploading files to temp folder ~/webapp..."
ssh $admin_user@$public_ip "mkdir -p ~/webapp"
scp -r "$publish_dir"/* $admin_user@$public_ip:~/webapp/

echo "📦 Moving to /opt/BasicMVC and setting permissions..."
ssh $admin_user@$public_ip << EOF
  sudo mkdir -p $remote_dir
  sudo rm -rf $remote_dir/*
  sudo mv ~/webapp/* $remote_dir/
  sudo chown -R www-data:www-data $remote_dir
EOF

# 🔄 Step 7: Restart the systemd service
echo "🔄 Restarting BasicMVC.service..."
ssh $admin_user@$public_ip "sudo systemctl restart BasicMVC.service"

echo "🔍 Checking BasicMVC.service status..."
ssh $admin_user@$public_ip "sudo systemctl status BasicMVC.service --no-pager"

# ✅ Step 8: Done
echo "✅ Deployment complete!"
echo "🌐 Access your app at: http://$public_ip:$vm_port"


# Save it so your main app prints both IPs at the end
echo "🌐 App Server:     http://$public_ip:$vm_port"
echo "🌐 Public Endpoint: http://$proxy_ip"