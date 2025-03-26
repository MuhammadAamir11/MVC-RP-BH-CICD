#!/bin/bash

# 🌍 Provision ASP.NET App VM + NGINX Reverse Proxy with Clean Architecture

# 🧠 Step 1: Environment Setup
export LANG=en_US.UTF-8
export PYTHONIOENCODING=utf-8

# ⚙️ Configuration Variables
resource_group="BasicMVCRG"
location="northeurope"
admin_user="azureuser"
vm_port=5000
publish_dir="./publish"
remote_dir="/opt/BasicMVC"
project_path="/c/Git/AzurePractice/BasicMVC/basicmvc.csproj"
cloud_init_app="cloud-init_dotnet.yaml"
cloud_init_proxy_template="cloud-init_proxy.template.yaml"
cloud_init_proxy="cloud-init_proxy.yaml"

# Network + Subnets
vnet_name="BasicMVCVNet"
app_subnet="AppSubnet"
proxy_subnet="ProxySubnet"
app_subnet_prefix="10.0.1.0/24"
proxy_subnet_prefix="10.0.2.0/24"
address_prefix="10.0.0.0/16"
nsg_app="AppNSG"
nsg_proxy="ProxyNSG"

# VM Names
app_vm_name="BasicMVCVM"
proxy_vm_name="ProxyVM"

# 🔄 Step 2: Publish ASP.NET Core App
echo "🔄 Publishing ASP.NET Core app..."
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

# 🔒 Step 4: Create NSGs
az network nsg create --resource-group $resource_group --name $nsg_app
az network nsg create --resource-group $resource_group --name $nsg_proxy

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

# Allow HTTP and HTTPS to Proxy VM
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

az network nsg rule create \
  --resource-group $resource_group \
  --nsg-name $nsg_proxy \
  --name AllowHTTPS \
  --priority 101 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix Internet \
  --destination-port-range 443

# 🔐 Allow SSH from user's IP (recommend replacing * with actual IP)
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

# Attach NSGs to Subnets
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

# 💻 Step 5: Create App VM
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

# 📄 Step 6: Generate Proxy cloud-init with private IP
sed "s|__APP_PRIVATE_IP__|$private_ip|g" $cloud_init_proxy_template > $cloud_init_proxy

# 💻 Step 7: Create Proxy VM
ezproxy_result=$(az vm create \
  --name $proxy_vm_name \
  --resource-group $resource_group \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --generate-ssh-keys \
  --admin-username $admin_user \
  --custom-data @$cloud_init_proxy \
  --public-ip-sku Standard \
  --vnet-name $vnet_name \
  --subnet $proxy_subnet 2>&1)

if ! az vm show -g $resource_group -n $proxy_vm_name &> /dev/null; then
  echo "❌ Failed to create Proxy VM. Please check the cloud-init_proxy.yaml file."
  echo "$ezproxy_result"
  exit 1
fi

proxy_ip=$(az vm show -d -g $resource_group -n $proxy_vm_name --query publicIps -o tsv)

# 🔐 Step 8: Attach NSG to Proxy NIC dynamically
proxy_nic=$(az vm show \
  --resource-group $resource_group \
  --name $proxy_vm_name \
  --query "networkProfile.networkInterfaces[0].id" -o tsv | awk -F'/' '{print $NF}')

az network nic update \
  --resource-group $resource_group \
  --name "$proxy_nic" \
  --network-security-group $nsg_proxy

# 📦 Step 9: Deploy the app manually
# Use scp to copy published files to App VM
scp -r "$publish_dir"/* $admin_user@$public_ip:/home/$admin_user/

# Remotely move files to the app directory and set permissions
ssh $admin_user@$public_ip << EOF
  sudo mv /home/$admin_user/* "$remote_dir"/
  sudo chown -R www-data:www-data "$remote_dir"
  sudo systemctl restart BasicMVC.service
EOF

# ✅ Done
echo -e "\n✅ All VMs deployed successfully!"
echo "🌐 App server (internal): http://$private_ip:5000"
echo "🌐 Access via Reverse Proxy: http://$proxy_ip"

# 🔒 Summary of Security Measures:
echo -e "\n🔐 Security Measures Implemented:"
echo "- Network Security Groups (NSGs) applied to app and proxy subnets"
echo "- App VM only accessible on port 22 (SSH) from your IP"
echo "- App VM only allows port 5000 from ProxySubnet (internal access only)"
echo "- Proxy VM only allows HTTP (port 80), HTTPS (port 443), and SSH from your IP"
echo "- NGINX reverse proxy hides backend app details from the internet"
echo "- ASP.NET Core app runs as a systemd service under www-data (least privilege)"
echo "- Cloud-init used for reproducible and secure provisioning"
echo "- Self-signed SSL certificate used for encrypted testing over HTTPS"
