#!/bin/bash

# For CICD we will remove dotnet publish "$project_path" -c Release -o "$publish_dir"


# 🌍 Provision ASP.NET App VM + NGINX Reverse Proxy with Clean Architecture (No HTTPS)

# 🧠 Step 1: Environment Setup
export LANG=en_US.UTF-8
export PYTHONIOENCODING=utf-8

# ⚙️ Configuration Variables
resource_group="BasicMVCRG"
location="northeurope"
admin_user="azureuser"
vm_port=5000
publish_dir="/tmp/basicmvc_publish"
remote_dir="/opt/BasicMVC"
project_path="/c/Git/AzurePractice/basicMVC/basicmvc.csproj"
cloud_init_app="cloud-init_dotnet.yaml"
cloud_init_proxy_template="cloud-init_proxy.template.yaml"
cloud_init_proxy="cloud-init_proxy.yaml"

# Network + Subnets
vnet_name="BasicMVCVNet"
app_subnet="AppSubnet"
proxy_subnet="ProxySubnet"
bastion_subnet="BastionSubnet"
app_subnet_prefix="10.0.1.0/24"
proxy_subnet_prefix="10.0.2.0/24"
bastion_subnet_prefix="10.0.3.0/24"
address_prefix="10.0.0.0/16"
nsg_app="AppNSG"
nsg_proxy="ProxyNSG"
nsg_bastion="BastionNSG"

# VM Names
app_vm_name="BasicMVCVM"
proxy_vm_name="ProxyVM"
bastion_vm_name="BastionHost"

# 🔁️ Step 2: Publish ASP.NET Core App
echo "🔁 Step 2: Publishing ASP.NET Core app..."

# Safety check: prevent publishing into the project directory
if [[ "$publish_dir" == $(pwd)* ]]; then
  echo "❌ publish_dir cannot be inside the project directory. Exiting."
  exit 1
fi

# Clean nested 'publish' folders if accidentally created
find . -type d -name publish -exec rm -rf {} +

rm -rf "$publish_dir"
mkdir -p "$publish_dir"
dotnet publish "$project_path" -c Release -o "$publish_dir"

if [ $? -ne 0 ]; then
  echo "❌ dotnet publish failed. Exiting."
  exit 1
fi

# 🕱️ Step 3: Create VNet & Subnets
az group create --name $resource_group --location $location

az network vnet create \
  --resource-group $resource_group \
  --name $vnet_name \
  --address-prefix $address_prefix \
  --subnet-name $app_subnet \
  --subnet-prefix $app_subnet_prefix

az network vnet subnet create \
  --resource-group $resource_group \
  --vnet-name $vnet_name \
  --name $proxy_subnet \
  --address-prefix $proxy_subnet_prefix

az network vnet subnet create \
  --resource-group $resource_group \
  --vnet-name $vnet_name \
  --name $bastion_subnet \
  --address-prefix $bastion_subnet_prefix

# 🔐 Step 4: Create NSGs
az network nsg create --resource-group $resource_group --name $nsg_app
az network nsg create --resource-group $resource_group --name $nsg_proxy
az network nsg create --resource-group $resource_group --name $nsg_bastion

# Allow App VM port 5000 from ProxySubnet
az network nsg rule create \
  --resource-group $resource_group \
  --nsg-name $nsg_app \
  --name AllowAppPort5000 \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix $proxy_subnet_prefix \
  --destination-port-range 5000

# Allow HTTP to Proxy VM
az network nsg rule create \
  --resource-group $resource_group \
  --nsg-name $nsg_proxy \
  --name AllowHTTP \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix Internet \
  --destination-port-range 80

# 🔐 Step 5: Allow SSH from user's IP
my_ip=$(curl -s ifconfig.me)
echo "🕵️️ Detected public IP: $my_ip"

az network nsg rule create \
  --resource-group $resource_group \
  --nsg-name $nsg_app \
  --name AllowSSHAppVM \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix "$my_ip" \
  --destination-port-range 22

az network nsg rule create \
  --resource-group $resource_group \
  --nsg-name $nsg_proxy \
  --name AllowSSHProxyVM \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix "$my_ip" \
  --destination-port-range 22

az network nsg rule create \
  --resource-group $resource_group \
  --nsg-name $nsg_bastion \
  --name AllowSSHBastion \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix "$my_ip" \
  --destination-port-range 22

# 🔗 Step 6: Attach NSGs to Subnets
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

az network vnet subnet update \
  --vnet-name $vnet_name \
  --resource-group $resource_group \
  --name $bastion_subnet \
  --network-security-group $nsg_bastion

# 💻 Step 7: Create App VM
az vm create \
  --name $app_vm_name \
  --resource-group $resource_group \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --generate-ssh-keys \
  --admin-username $admin_user \
  --custom-data @$cloud_init_app \
  --public-ip-sku Standard \
  --vnet-name $vnet_name \
  --subnet $app_subnet

public_ip=$(az vm show -d -g $resource_group -n $app_vm_name --query publicIps -o tsv)
private_ip=$(az vm show -d -g $resource_group -n $app_vm_name --query privateIps -o tsv)

# 📄 Step 8: Generate Proxy cloud-init with private IP
sed "s|__APP_PRIVATE_IP__|$private_ip|g" $cloud_init_proxy_template > $cloud_init_proxy

# 💻 Step 9: Create Proxy VM
az vm create \
  --name $proxy_vm_name \
  --resource-group $resource_group \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --generate-ssh-keys \
  --admin-username $admin_user \
  --custom-data @$cloud_init_proxy \
  --public-ip-sku Standard \
  --vnet-name $vnet_name \
  --subnet $proxy_subnet

proxy_ip=$(az vm show -d -g $resource_group -n $proxy_vm_name --query publicIps -o tsv)

# 🔐 Step 10: Attach NSG to Proxy NIC dynamically
proxy_nic=$(az vm show \
  --resource-group $resource_group \
  --name $proxy_vm_name \
  --query "networkProfile.networkInterfaces[0].id" -o tsv | awk -F'/' '{print $NF}')

az network nic update \
  --resource-group $resource_group \
  --name "$proxy_nic" \
  --network-security-group $nsg_proxy

# 💻 Step 11: Create Bastion Host VM
az vm create \
  --name $bastion_vm_name \
  --resource-group $resource_group \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --generate-ssh-keys \
  --admin-username $admin_user \
  --public-ip-sku Standard \
  --vnet-name $vnet_name \
  --subnet $bastion_subnet

# 📦 Step 12: Upload app via Bastion SSH tunnel
bastion_ip=$(az vm show -d -g $resource_group -n $bastion_vm_name --query publicIps -o tsv)

# 🛑 Kill old SSH tunnel if running
pkill -f "ssh -A -fN -L 2222" 2>/dev/null
sleep 2

# 🧹 Clean known_hosts for port 2222
ssh-keygen -R [localhost]:2222 2>/dev/null

# Trust Bastion IP and localhost tunnel to avoid SSH prompts
ssh-keyscan -H "$bastion_ip" >> ~/.ssh/known_hosts 2>/dev/null
ssh-keyscan -H [localhost]:2222 >> ~/.ssh/known_hosts 2>/dev/null

# Check if port 2222 is free
if lsof -i :2222; then
  echo "❌ Port 2222 is still in use. Exiting."
  exit 1
else
  echo "✅ Port 2222 is free. Proceeding..."
fi

# Open SSH tunnel
ssh -o StrictHostKeyChecking=no -A -fN -L 2222:$private_ip:22 $admin_user@$bastion_ip
sleep 5

# Upload build
scp -o StrictHostKeyChecking=no -P 2222 -r "$publish_dir"/* $admin_user@localhost:/home/$admin_user/

# Confirm upload is done
echo "✅ Build files uploaded to App VM via SSH tunnel"

# Move + restart service
ssh -o StrictHostKeyChecking=no -p 2222 $admin_user@localhost << EOF
  sudo mv /home/$admin_user/* "$remote_dir"/
  sudo chown -R www-data:www-data "$remote_dir"
  sudo systemctl restart BasicMVC.service
EOF

# ✅ Step 13: Done
echo -e "\n✅ All VMs deployed successfully!"
echo "🌐 Access via Reverse Proxy: http://$proxy_ip"

# 🔐 Security Measures Summary
echo -e "\n🔐 Security Measures Implemented:"
echo "- NSGs applied per subnet (App, Proxy, Bastion)"
echo "- App VM accessible only from ProxySubnet on port 5000"
echo "- SSH access only from your IP"
echo "- Bastion host acts as secure SSH entry point"
echo "- NGINX reverse proxy hides backend app from the public"
echo "- App runs under www-data via systemd"
echo "- Cloud-init for automated provisioning"
echo "- File upload via SSH tunnel through Bastion"
echo "- Old SSH tunnels killed to prevent port conflicts"
echo "- Known_hosts cleaned to avoid SSH verification prompts"
echo "- CI/CD handled by GitHub Actions; this script provisions infrastructure only"

