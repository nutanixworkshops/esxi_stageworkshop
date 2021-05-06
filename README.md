# ESXi Staging

Staging ESXi HPOC systems

## Remark

Below is still in scaffolding!!! Nothing is yet GA!!

## TODO

Below items are NOT YET in the script:

- Upload of Blueprints for:
   - Calm workshop
   - CI/CD workshop

- For Era workshop:
   - MSSQL server
   - Oracle server

- Need to make more users for the workshops. Now all is deployed for one user
   > Using clones this can be solved as a workaround

## High level description

This repo is to have the possibility to create an ESXi staging possibility for ESXi environments.
As ESXi not supports the same Nutanix products as AHV, this staging script will only install and configure/enable:

1. Prism Central
2. Calm
3. Files
4. Objects
5. Era
6. Leap

> The latest version of PC will be deployed
## Staging requirements

As we have dependencies on VMware and some other for manipulating Linux machines, the script is built in PowerShell/PowerCLI. For the execution of the script, we are using a special build Docker container. The basis of the container has been the vmware/powercli Docker container version, too which small edits have been made so it can function for the ESXi Staging. This means that **Docker has to be installed and running on your machine**. There are a lot of articles on how to install Docker on your O/S. Follow this article to install Docker for your O/S <https://docs.docker.com/get-docker/>.
Besides docker also **git** needs to be installed on your computer and **Nutanix VPN** needs to be installed and configured.

> If you want to know more on the container, please read this <https://github.com/vmware/powerclicore>.

> Two packages have been added to the container. These packages are **openssh-clients** and **sshpass**. This makes it possible to use SSH with username and password to manipulate Linux based machines. The script is using it to manipulate the Era instance for setting its static IP Address. Besides the extra packages the example scripts have been removed from the container. How the container is build, please consult the Dockerfile in the vmware-powercli folder in the Repo.  

## Usage

During the reservation of your cluster make sure you select the following:

- Select the ESXi 6.5U1 as the hypervisor
- Use AOS 5.19.1+
- Leave all other option, maybe change the password, default
- Reserve your cluster

After it's your time to use the cluster, follow these steps to get the staging running:

1. Run **git Clone <https://github.com/wessenstam/esxi_stageworkshop>** to pull the script and needed information
2. CD into the location where the GitHub Repo has been pulled
3. Create a file named **environment.env** with the needed parameters and save the file in the location of the clone. These parameters are *PE password,IP address of the PE instance* **example; ThisisSecret,10.10.10.10**
4. Save the file
5. Run the Powershell script using the below
   After you have installed Docker, you can use the following command to run the script:

   ```bash
   docker run --rm -it -v "${PWD}":/script wessenstam/esxi_stage pwsh /script/SCRIPTNAME.ps1
   ```

   Where:

   - --rm; after the container has stopped, remove it from the docker environment
   - -it; run in interactive mode, show the console output of the script
   - -v; "mount" the following path **${PWD}** (current directory) to the **/script** directory INSIDE the container
   - wessenstam/esx_staging; the name of the container image that is going to be run. It will be downloaded automatically if it doesn't exist on the machine.
   - /script/**SCRIPTNAME**.ps1; the name of the script including the location **INSIDE** the container. As we have mounted, using the **-v** parameter, the location on the machine that holds the script file to /script in the container, the container needs to be told the absolute full path.

   The following scripts are available:

   1. **private_cloud.ps1**; for Private cloud workshops with PE and PC configured
   2. **consolidated_storage.ps1**; For File server, File server manager and Objects workshops with PE and PC configured
   3. **calm.ps1**; for Calm workshop with PE and PC configured
   4. **era.ps1**; for Era related workshops with PE and PC configured
   5. **cicd.ps1**; for CI/CD related workshop where PE, PC and Calm are configured

## Detailed run

The script will do the following:

1. Using REST API for PE:

   1. Accept the EULA
   2. Disable Pulso
   3. Change the Storage Pool name to SP01
   4. Change the defafult-XXX storage container name to default
   5. Create an Images storage container
   6. Mount the Images storage container to all ESXi hosts

2. Using native Powershell for VMware to:

   1. Configure the secondairy network
   2. Enable DRS and disable Admission Control
   3. Upload ISO Images and OVA Templates in a newly created Content Library
   4. Deploy AutoAD for DNS and Authentication

      > During this step, in very rare cases, the AutoAD is not starting due to Powershell. It needs to have a user interact with the script. If the script is stuck for 45 minutes it will stop. To make sure the script progresses, check the logs (in the console). After approx 15 minutes the script should progress to the next steps. If not, please open the UI of the AutoAD VM and interact with the VM by typing "A" and Enter. After that the script will pick up the AutoAD progress and move forward.

   5. Deploy CentOS 7 VM and turns it into a Template so it can be used with Calm
   6. Deploy Windows 2016 VM and turns it into a Template so it can be used with Calm
   7. Deploy the WindowsTools VM

3. Using REST API for PE:

   1. Configure Authentication
   2. Create Roles for the SSP Admin group from AD as Cluster Admin
   3. Deploy Prism Central

4. Using REST API for PC:

   1. Change the password to the same password as PE
   2. Accept the EULA
   3. Disable Pulse
   4. Add DNS Servers (AutoAD)
   5. Add three NTP servers
   6. Set Authentication
   7. Create the roles (Rolemapping)
   8. Enable Karbon
   9. Enable Calm
   10. Enable Objects
   11. Enable File Server Manager
   12. Run LCM (Inventory and Upgrade)
   13. Create VMware as the Provider for Calm
   14. Create a Project and assigns the VMware as its provider
   15. Deploy an Objects Store
   16. Deploy and configure Era so it can be used
