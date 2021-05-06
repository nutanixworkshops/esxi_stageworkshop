# Set some environmental variables
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -DefaultVIServerMode:Multiple -confirm:$false | Out-Null
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -confirm:$false | Out-Null

# are we running natively or from the docker container?
if (Test-Path -Path ./environment.env -PathType Leaf){
    $parameters=get-content "./environment.env"
    $module_dir="./Modules"
}else{
    $parameters=get-content "/script/environment.env"
    $module_dir="/script/Modules"
}
# Loading the needed modules
Import-Module $module_dir/common_mod.psm1
Import-Module $module_dir/pe_mod.psm1
Import-Module $module_dir/pc_mod.psm1
Import-Module $module_dir/vmware_mod.psm1
Import-Module $module_dir/era_mod.psm1
Import-Module $module_dir/cicd_mod.psm1

# **********************************************************************************
# Setting the needed variables
# **********************************************************************************
# Are we running from native Powershell or via the PowerCLI docker container
if (Test-Path -Path ./environment.env -PathType Leaf){
    $parameters=get-content "./environment.env"
}else{
    $parameters=get-content "/script/environment.env"
}

$password=$parameters.Split(",")[0]
$PE_IP=$parameters.Split(",")[1]
$ip_subnet=$PE_IP.Substring(0,$PE_IP.Length-3)

$AutoAD=$PE_IP.Substring(0,$PE_IP.Length-2)+"41"
$VCENTER=$PE_IP.Substring(0,$PE_IP.Length-2)+"40"
$PC_IP=$PE_IP.Substring(0,$PE_IP.Length-2)+"39"
$Era_IP=$PE_IP.Substring(0,$PE_IP.Length-2)+"43"
$GW=$PE_IP.Substring(0,$PE_IP.Length-2)+"1"

# Use the right NFS Host using the 2nd Octet of the PE IP address
switch ($PE_IP.Split(".")[1]){
    38 {
        $nfs_host="10.42.194.11"
        $vlan=(($PE_IP.Split(".")[2] -as [int])*10+3)
    }
    42 {
        $nfs_host="10.42.194.11"
        $vlan=(($PE_IP.Split(".")[2] -as [int])*10+1)
    }
    55 {
        $nfs_host="10.55.251.38"
        $vlan=(($PE_IP.Split(".")[2] -as [int])*10+1)
    }
}

# Set the username and password header
$Header_NTNX_Creds=@{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:"+$password));}
$Header_NTNX_PC_temp_creds=@{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:Nutanix/4u"));}


$cluster_name=GetClustername -IP $PE_IP -Header $Header_NTNX_Creds

Write-Output "*************************************************"
Write-Output "Concentrating on Nutanix PE environment ($cluster_name).."
Write-Output "*************************************************"

# **************************************
# Initial PE configuration
# **************************************

# Accept the Eula
$response=AcceptEula -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Disable Pulse
$response=DisablePulse -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Add NTP servers to PE
$response=AddNTPServers -IP $PE_IP -Header $Header_NTNX_Creds
Write-Output $response

# Change the default SP Name to Sp1
$response=ChangeSPName -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Change the default SP Name to Sp1
$response=RenameDefaultCNTR -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Create Images container
$response=CreateImagesCNTR -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Mount Images container
$response=MountImagesCNTR -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

Write-Output "*************************************************"
Write-Output "Concentrating on VMware environment ($VCENTER).."
Write-Output "*************************************************"

# Connect to vCenter
$response=ConnectVMware -vcenter $VCENTER -password $password
write-output $response

#Enable DRS and disable Admission control
$response=EnableDRSDisableAdmissionContol -vcenter $VCENTER -password $password
write-output $response

# Create the Secondary network in the correct VLAN
$vm_cluster_name=$response.substring($response.IndexOf("(")+1,$response.length-$response.IndexOf("(")-3)
$response=CreateSecondaryNetwork -vm_cluster_name $vm_cluster_name -vlan $vlan
Write-Output $response

Write-Output "Uploading needed images"
# Create Content Libarary
New-ContentLibrary -Name "deploy" -Datastore "Images" | Out-Null

# Upload needed images
$images=@('esxi_ovas/AutoAD_Sysprep.ova','esxi_ovas/CentOS.ova','esxi_ovas/ERA-Server-build-2.1.1.2.ova','esxi_ovas/WinTools-AHV.ova')
foreach($image in $images){
    $response=UploadImage -image $image -nfs_host $nfs_host
    Write-Output $response
}

# Deploy the CentOS templates
$templates=@('CentOS')
foreach($template in $templates){
    $response=DeployVMTemplate -vm_cluster_name $vm_cluster_name -templ_name $template
    write-output $response
}

# Deploy the WinTools-VM
$response=DeployWinToolsVM -vm_cluster_name $vm_cluster_name
Write-Output $response

# Deploy Era
$response=DeployEraVM -vm_cluster_name $vm_cluster_name
Write-Output $response

# Deploy the AutoAD and wait till ready before moving forward
$response=DeployAutoAD -vm_cluster_name $vm_cluster_name -AutoAD $AutoAD
Write-Output $response

# Disconnecting from the vCenter
$response=DisconnectvCenter
write-output $response


Write-Output "*************************************************"
Write-Output "Concentrating on Nutanix PE environment ($cluster_name).."
Write-Output "*************************************************"

# Add AutoAd as authentication and DNS server
$response=AddAutoADtoPE -AutoAD $AutoAD -IP $PE_IP -Header $Header_NTNX_Creds
Write-Output $response

# Role mapping between PE and AD
$response=RoleMapPEtoAD -IP $PE_IP -Header $Header_NTNX_Creds
Write-Output $response

# Deploy PC
$response=DeployPC -IP $PE_IP -AutoAD $AutoAD -Header $Header_NTNX_Creds -PC_IP $PC_IP -GW $GW
write-output $response

# Check PE registered to PC
$response=PERegistered -IP $PE_IP -Header $Header_NTNX_Creds
Write-Output $response

Write-Output "*************************************************"
Write-Output "Concentrating on Nutanix PC environment.."
Write-Output "*************************************************"

# Change PC Password to match PE
$response=ResetPCPassword -IP $PC_IP -password $password -Header $Header_NTNX_PC_temp_creds
Write-Output $response

# Accept the Eula
$response=AcceptEula -IP $PC_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Disable Pulse
$response=DisablePulse -IP $PC_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Add AutoAd as authentication and DNS server
$response=AddAutoADtoPE -AutoAD $AutoAD -IP $PC_IP -Header $Header_NTNX_Creds
Write-Output $response

# Role mapping between PC and AD
$response=RoleMapPEtoAD -IP $PC_IP -Header $Header_NTNX_Creds
Write-Output $response

# Add NTP servers to PC
$response=AddNTPServers -IP $PC_IP -Header $Header_NTNX_Creds
Write-Output $response

# Enable Calm
$response=EnableCalm -IP $PC_IP -Header $Header_NTNX_Creds
Write-Output $response

# Run LCM to update all enabled modules except NCC and PC themself
$response=PCLCMRun -IP $PC_IP -Header $Header_NTNX_Creds
Write-Output $response

# Add VMware as Provider for Calm
$response=VMwareProviderCalm -IP $PC_IP -Header $Header_NTNX_Creds -VCENTER $VCENTER -password $password
Write-Output $response

# Create BootCampInfra Project
$response=AddPRojectBootcampInfra -IP $PC_IP -Header $Header_NTNX_Creds
Write-Output $response

# Create BootCampInfra Project
$response=AddVMwareToBootcampInfra -IP $PC_IP -Header $Header_NTNX_Creds
Write-Output $response

Write-Output "*************************************************"
Write-Output "Configuring Era"
Write-Output "*************************************************"

# Default Era configuration
$response=ConfigBasicEra -IP $PC_IP -Header $Header_NTNX_Creds -Header_Temp $Header_NTNX_PC_temp_creds -Era_IP $Era_IP -ip_subnet $ip_subnet -AutoAD $AutoAD -password $password -PE_IP $PE_IP
Write-Output $response

# Create the Compute Profiles
$response=EraComputeProfiles -Era_IP $Era_IP -Header $Header_NTNX_Creds
Write-Output $response

# Create the Domain Profile
$response=EraDomainProfile -Era_IP $Era_IP -Header $Header_NTNX_Creds
Write-Output $response

# Create the MariaDB Network for CICD
$response=EraMariaDBNetwork -Era_IP $Era_IP -Header $Header_NTNX_Creds
Write-Output $response

Write-Output "*************************************************"
Write-Output "All steps done for CI/CD bootcamp"
Write-Output "*************************************************"


# Remove the loaded modules from memory
remove-module common_mod
remove-module pe_mod
remove-module pc_mod
remove-module vmware_mod
remove-module era_mod
remove-module cicd_mod
 
 