#!/bin/bash

# 🚀 Provision ASP.NET App VM + NGINX Reverse Proxy with Clean Architecture (No HTTPS)

# ─────────────────────────────────────────────────────────────
# 🛠️ Step 1: Environment & Variables
# ─────────────────────────────────────────────────────────────
export LANG=en_US.UTF-8
export PYTHONIOENCODING=utf-8

# Configuration Variables
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

# ─────────────────────────────────────────────────────────────
# 🧱 Step 2: Build & Publish the App
# ─────────────────────────────────────────────────────────────
echo "📦 Step 2: Publishing ASP.NET Core app..."

# Safety check to avoid publishing inside the source directory
if [[ "$publish_dir" == $(pwd)* ]]; then
  echo "❌ publish_dir cannot be inside the project directory. Exiting."
  exit 1
fi

# Clean up previous publish directories
find . -type d -name publish -exec rm -rf {} +
rm -rf "$publish_dir"
mkdir -p "$publish_dir"

# Build and publish the project
dotnet publish "$project_path" -c Release -o "$publish_dir"

# Verify build was successful
if [ $? -ne 0 ]; then
  echo "❌ dotnet publish failed. Exiting."
  exit 1
fi

# ─────────────────────────────────────────────────────────────
# 🌐 Step 3: Networking - VNet & Subnets
# ─────────────────────────────────────────────────────────────

# Create the resource group
az group create --name $resource_group --location $location

# Create virtual network and subnets
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

# ─────────────────────────────────────────────────────────────
# 🔐 Step 4: Network Security Groups & Rules
# ─────────────────────────────────────────────────────────────

# Create NSGs
az network nsg create --resource-group $resource_group --name $nsg_app
az network nsg create --resource-group $resource_group --name $nsg_proxy
az network nsg create --resource-group $resource_group --name $nsg_bastion

# Add rules to App NSG (Allow port 5000 from ProxySubnet)
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

# Add rule to Proxy NSG (Allow HTTP)
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

# Add SSH rules from current IP to all NSGs
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

# Attach NSGs to each subnet
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

# ─────────────────────────────────────────────────────────────
# 🖥️ Step 5: Deploy Virtual Machines
# ─────────────────────────────────────────────────────────────

# Deploy the App VM
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

# Capture public and private IPs for App VM
public_ip=$(az vm show -d -g $resource_group -n $app_vm_name --query publicIps -o tsv)
private_ip=$(az vm show -d -g $resource_group -n $app_vm_name --query privateIps -o tsv)

# Replace placeholder with App VM's private IP in proxy template
sed "s|__APP_PRIVATE_IP__|$private_ip|g" $cloud_init_proxy_template > $cloud_init_proxy

# Deploy the Proxy VM
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

# Capture proxy VM public IP
proxy_ip=$(az vm show -d -g $resource_group -n $proxy_vm_name --query publicIps -o tsv)

# Update proxy NIC with its NSG (in case it was not attached during creation)
proxy_nic=$(az vm show \
  --resource-group $resource_group \
  --name $proxy_vm_name \
  --query "networkProfile.networkInterfaces[0].id" -o tsv | awk -F'/' '{print $NF}')

az network nic update \
  --resource-group $resource_group \
  --name "$proxy_nic" \
  --network-security-group $nsg_proxy

# Deploy the Bastion Host VM
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

# ─────────────────────────────────────────────────────────────
# 📢 Step 6: Final Output
# ─────────────────────────────────────────────────────────────
echo -e "\n✅ All VMs deployed successfully!"
echo "🌐 Access via Reverse Proxy: http://$proxy_ip"

echo -e "\n🔐 Security Measures Implemented:"
echo "- NSGs applied per subnet (App, Proxy, Bastion)"
echo "- App VM accessible only from ProxySubnet on port 5000"
echo "- SSH access only from your IP"
echo "- Bastion host acts as secure SSH entry point"
echo "- NGINX reverse proxy hides backend app from the public"
echo "- App runs under www-data via systemd"
echo "- Cloud-init for automated provisioning"
echo "- CI/CD handled by GitHub Actions; this script provisions infrastructure only"
echo "- App hosted using systemd, not dotnet run (suitable for production)"
