
  # Create directory for GitHub Runner
  - mkdir -p /home/azureuser/actions-runner
 # - cd /home/azureuser/actions-runner
 # - curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.314.1.tar.gz
 # - tar xzf actions-runner-linux-x64.tar.gz


 
# After provisioning, to verify everything -> SSH into the VM and run: cat /var/log/cloud-init-success.log
# This will show the log of the cloud-init process, including the .NET SDKs and Runtimes installed, and the status of the BasicMVC.service