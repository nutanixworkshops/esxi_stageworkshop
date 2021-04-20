# Set some environmental variables
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -DefaultVIServerMode:Multiple -confirm:$false | Out-Null
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -confirm:$false | Out-Null


# **********************************************************************************
# Setting the needed variables
# **********************************************************************************
$parameters=get-content "./environment.env"
$password=$parameters.Split(",")[0]
$PE_IP=$parameters.Split(",")[1]

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

# **********************************************************************************
# ************************* Start of the script ************************************
# **********************************************************************************

# Get something on the screen...

Write-Output "*************************************************"
Write-Output "Concentrating on Nutanix PE environment.."
Write-Output "*************************************************"


# **********************************************************************************
# PE Part of the script
# **********************************************************************************

# Accept the EULA

$APIParams = @{
    method="POST"
    Body='{"username":"NTNX","companyName":"NTNX","jobTitle":"NTNX"}'
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/eulas/accept"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response = "True"){
    Write-Output "Eula Accepted"
}else{
    Write-Output "Eula NOT accepted"
}

Write-Output "--------------------------------------"

# Disable Pulse

$APIParams = @{
    method="PUT"
    Body='{"enable":"false","enableDefaultNutanixEmail":"false","isPulsePromptNeeded":"false"}'
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/pulse"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response = "True"){
    Write-Output "Pulse Disabled"
}else{
    Write-Output "Pulse NOT disabled"
}

Write-Output "--------------------------------------"

# Change the name of the Storage Pool to SP1

# First get the Disk IDs

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/storage_pools?sortOrder=storage_pool_name"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck | ConvertTo-JSON -Depth 10)
$disks=($response | ConvertFrom-JSON).entities.disks | ConvertTo-JSON
$sp_id=($response | ConvertFrom-JSON).entities.id | ConvertTo-JSON

# Change the name of the Storage Pool

$Body=@"
{
    "id":$sp_id,
    "name":"SP01",
    "disks":$disks
}
"@
$APIParams = @{
    method="PUT"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/storage_pools?sortOrder=storage_pool_name"
    ContentType="application/json"
    Body=$Body
    Header = $Header_NTNX_Creds
}

$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response="True"){
    Write-Output "Storage Pool has been renamed"
}else{
    Write-Output "Storage Pool has not been renamed"
}

Write-Output "--------------------------------------"

# Change the name of the defaulxxxx storage container to Default

# Get the ID and UUID of the default container first

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/storage_containers"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities | where-object {$_.name -match "efault"}
$default_cntr_id=$response.id | ConvertTO-JSON
$default_cntr_uuid=$response.storage_container_uuid | ConvertTO-JSON


$Payload=@"
{
    "id":$default_cntr_id,
    "storage_container_uuid":$default_cntr_uuid,
    "name":"default",
    "vstore_name_list":[
        "default"
    ]
}
"@

$APIParams = @{
    method="PATCH"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/storage_containers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
if ($response = "True"){
    Write-Output "Default Storage Container has been updated"
}else{
    Write-Output "Default Storage Container has NOT been updated"
}

Write-Output "--------------------------------------"

# Create the Images datastore

$Payload=@"
{
    "name": "Images",
    "marked_for_removal": false,
    "replication_factor": 2,
    "oplog_replication_factor": 2,
    "nfs_whitelist": [],
    "nfs_whitelist_inherited": true,
    "erasure_code": "off",
    "prefer_higher_ecfault_domain": null,
    "erasure_code_delay_secs": null,
    "finger_print_on_write": "off",
    "on_disk_dedup": "OFF",
    "compression_enabled": false,
    "compression_delay_in_secs": null,
    "is_nutanix_managed": null,
    "enable_software_encryption": false,
    "encrypted": null
}
"@

$APIParams = @{
  method="POST"
  Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/storage_containers"
  ContentType="application/json"
  Body=$Payload
  Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
if ($response = "True"){
    Write-Output "Images Storage Container has been created"
}else{
    Write-Output "Images Storage Container has NOT been created"
}

Write-Output "--------------------------------------"

# Mount the Images container to all ESXi hosts

# Get the ESXi Hosts UUIDS

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/hosts/"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities.service_vmid
$host_ids=$response | ConvertTO-JSON

# Mount to all ESXi Hosts

$Payload=@"
{
    "containerName":"Images",
    "datastoreName":"",
    "nodeIds":$host_ids,
    "readOnly":false
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/containers/datastores/add_datastore"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

Write-Output "*************************************************"
Write-Output "Concentrating on VMware environment.."
Write-Output "*************************************************"

# **********************************************************************************
# Start the VMware environment manipulations
# **********************************************************************************

# Connect to the vCenter of the environment

connect-viserver $VCENTER -User administrator@vsphere.local -Password $password | Out-Null

# Enable DRS on the vCenter

Write-Output "Enabling DRS on the vCenter environment and disabling Admission Control"
$cluster_name=(get-cluster| select $_.name).Name
Set-Cluster -Cluster $cluster_name -DRSEnabled:$true -HAAdmissionControlEnabled:$false -Confirm:$false | Out-Null

Write-Output "--------------------------------------"

# Create a new Portgroup called Secondary with the correct VLAN

Write-Output "Creating the Secondary network on the ESXi hosts"
$vmhosts = Get-Cluster $cluster_name | Get-VMhost

ForEach ($vmhost in $vmhosts){
    Get-VirtualSwitch -VMhost $vmhost -Name "vSwitch0" | New-VirtualPortGroup -Name 'Secondary' -VlanId $vlan | Out-Null
}

Write-Output "--------------------------------------"

Write-Output "Uploading needed images"

# Create a ContentLibray and copy the needed images to it

New-ContentLibrary -Name "deploy" -Datastore "Images" | Out-Null
$images=@('esxi_ovas/AutoAD_Sysprep.ova','esxi_ovas/WinTools-AHV.ova','esxi_ovas/CentOS.ova','CentOS7.iso','Windows2016.iso')
foreach($image in $images){
    # Making sure we set the correct nameing for the ContentLibaray by removing the leading sublocation on the HTTP server
    if ($image -Match "/"){
        $image_name=$image.SubString(10)
    }else{
        $image_name=$image
    }
    # Remove the ova from the "templates" and the location where we got the Image from, but leave the isos alone
    if ($image -Match ".ova"){
        $image_short=$image.Substring(0,$image.Length-4)
        $image_short=$image_short.SubString(10)
    }else{
        $image_short=$image
    }
    get-ContentLibrary -Name 'deploy' -Local |New-ContentLibraryItem -name $image_short -FileName $image_name -Uri "http://$nfs_host/workshop_staging/$image"| Out-Null
    Write-Output "Uploaded $image as $image_short in the deploy ContentLibrary"
}

Write-Output "--------------------------------------"

# Deploy an AutoAD OVA. DRS will take care of the rest.

$ESXi_Host=$vmhosts[0]

Write-Output "Deploying the WinTools VM via a Content Library in the Image Datastore"
Get-ContentLibraryitem -name 'WinTools-AHV' | new-vm -Name 'WinTools-VM' -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null
get-vm 'WinTools-VM' | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'Secondary' -Confirm:$false | Out-Null

Write-Output "WindowsTools VM has been created"
Write-Output "--------------------------------------"

Write-Output "Deploying the CentOS7 VM via a Content Library in the Image Datastore and transforming into a Template"
Get-ContentLibraryitem -name 'CentOS' | new-vm -Name 'CentOS-Templ' -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null
get-vm 'CentOS-Templ' | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'Secondary' -Confirm:$false | Out-Null
Get-VM -Name 'CentOS-Templ' | Set-VM -ToTemplate -Confirm:$false

Write-Output "A template for CentOS 7 has been created"
Write-Output "--------------------------------------"


Write-Output "Creating AutoAD VM via a Content Library in the Image Datastore"
Get-ContentLibraryitem -name 'AutoAD_Sysprep' | new-vm -Name AutoAD -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null

# Set the network to VM-Network before starting the VM

get-vm 'AutoAD' | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'VM Network' -Confirm:$false | Out-Null

Write-Output "--------------------------------------"

Write-Output "AutoAD VM has been created. Starting..."
Start-VM -VM 'AutoAD' | Out-Null

Write-Output "Waiting till AutoAD is ready.."
$counter=1
$url="http://"+$AutoAD+":8000"
while ($true){
    try{
        $response=invoke-Webrequest -Uri $url -TimeOut 15
        Break
    }catch{
        Write-Output "AutoAD still not ready. Sleeping 60 seconds before retrying...($counter/45)"
        sleep 60
        if ($counter -eq 45){
            Write-Output "We waited for 45 minutes and the AutoAD didn't got ready in time... Exiting script.."
            exit 1
        }
        $counter++
    }
}
Write-Output "AutoAD is ready for being used. Progressing..."
Write-Output "--------------------------------------"

# Close the VMware connection

disconnect-viserver * -Confirm:$false

# **********************************************************************************
# Start the PE environment manipulations
# **********************************************************************************
Write-Output "*************************************************"
Write-Output "Concentrating on Nutanix PE environment.."
Write-Output "*************************************************"

# Confiure PE to use AutoAD for authentication and DNS server

$directory_url="ldap://"+$AutoAD+":389"
  
Write-Output "Adding $AutoAD as the Directory Server"

$Payload=@"
{
"connection_type": "LDAP",
"directory_type": "ACTIVE_DIRECTORY",
"directory_url": "$directory_url",
"domain": "ntnxlab.local",
"group_search_type": "RECURSIVE",
"name": "NTNXLAB",
"service_account_username": "administrator@ntnxlab.local",
"service_account_password": "nutanix/4u"
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/api/nutanix/v2.0/authconfig/directories/"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  if ($response = "True"){
      Write-Output "Authorization to use NTNXLab.local has been created"
  }else{
      Write-Output "Authorization to use NTNXLab.local has NOT been created"
  }

Write-Output "--------------------------------------"

# Removing the DNS servers from the PE and add Just the AutoAD as its DNS server

Write-Output "Updating DNS Servers"

# Fill the array with the DNS servers that are there

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/cluster/name_servers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
$servers=$response

# Delete the DNS servers so we can add just one

foreach($server in $servers){
    $Payload='[{"ipv4":"'+$server+'"}]'
    Write-Output $Payload
    $APIParams = @{
        method="POST"
        Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/cluster/name_servers/remove_list"
        ContentType="application/json"
        Body=$Payload
        Header = $Header_NTNX_Creds
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
}

# Get the AutoAD as correct DNS in

$Payload='{"value":"'+$AutoAD+'"}'
$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/cluster/name_servers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

Write-Output "DNS Servers Updated"

Write-Output "--------------------------------------"

Write-Output "Adding SSP Admins AD Group to Cluster Admin Role"

$Payload=@"
{
    "directoryName": "NTNXLAB",
    "role": "ROLE_CLUSTER_ADMIN",
    "entityType": "GROUP",
    "entityValues":[
        "SSP Admins"
    ]
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/authconfig/directories/NTNXLAB/role_mappings?&entityType=GROUP&role=ROLE_CLUSTER_ADMIN"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  if ($response = "True"){
      Write-Output "SSP Admins have been added as the Cluster Admin Role"
  }else{
      Write-Output "SSP Admins have not been added as the CLuster Admin Role"
  }

Write-Output "--------------------------------------"


# Deploy Prism Central

Write-Output "Deploying the Prism Central to the environment"

# Get the Storage UUID as we need it before we can deploy PC

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/storage_containers"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities | where-object {$_.name -match "vmContainer1"}
$cntr_uuid=$response.storage_container_uuid


# Get the Network UUID as we need it before we can deploy PC

$APIParams = @{
  method="GET"
  Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/networks"
  ContentType="application/json"
  Body=$Payload
  Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities | where-object {$_.name -match "VM Network"}
$network_uuid=$response.uuid


$Payload=@"
{
    "resources":{
        "version":"pc.2021.1.0.1",
        "should_auto_register":true,
        "pc_vm_list":[
            {
                "vm_name":"pc-2021.1",
                "container_uuid":"$cntr_uuid",
                "num_sockets":6,
                "data_disk_size_bytes":536870912000,
                "memory_size_bytes":27917287424,
                "dns_server_ip_list":[
                    "$AutoAD"
                ],
                "nic_list":[
                    {
                        "ip_list":[
                            "$PC_IP"
                        ],
                        "network_configuration":{
                            "network_uuid":"$network_uuid",
                            "subnet_mask":"255.255.255.128",
                            "default_gateway":"$GW"
                        }
                    }
                ]
            }
        ]
    }
}
"@

$APIParams = @{
  method="POST"
  Uri="https://"+$PE_IP+":9440/api/nutanix/v3/prism_central"
  ContentType="application/json"
  Body=$Payload
  Header = $Header_NTNX_Creds
}
try{
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
}catch{
    Write-Output "The PC download and deployment could not be executed. Exiting the script."
    Write-Output "Received error was: $_.Exception.Message"
    exit 1
}


Write-Output "Deployment of PC has started. Now need to wait till it is up and running"
Write-Output "Waiting till PC is ready.. (could take up to 30+ minutes)"
$counter=1
$url="https://"+$PC_IP+":9440"

# Need temporary default credentials

$username = "admin"
$password_default = "Nutanix/4u" | ConvertTo-SecureString -asPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($username,$password_default)
while ($true){
    try{
        $response=invoke-Webrequest -Uri $url -TimeOut 15 -SkipCertificateCheck -Credential $cred
        Break
    }catch{
        Write-Output "PC still not ready. Sleeping 60 seconds before retrying...($counter/45)"
        sleep 60
        if ($counter -eq 45){
            Write-Output "We waited for 45 minutes and the AutoAD didn't got ready in time..."
            exit 1
        }
        $counter++
    }
}
Write-Output "PC is ready for being used. Progressing..."
Write-Output "--------------------------------------"

# Check if registration was successfull of PE to PC

Write-Output "Checking if PE has been registred to PC"
$APIParams = @{
  method="GET"
  Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/multicluster/cluster_external_state"
  ContentType="application/json"
  Body=$Payload
  Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
$count=1
while ($response.clusterDetails.ipAddresses -eq $null){
    Write-Output "PE is not yet registered to PC. Waiting a bit more.."
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    sleep 60
    if ($count -gt 10){
        Write-Output "Waited for 10 minutes. Giving up. Exiting the script."
        exit 3
    }
    $count++
}
Write-Output "PE has been registered to PC. Progressing..."
Write-Output "--------------------------------------"

# **********************************************************************************
# Start the PC environment manipulations
# **********************************************************************************
Write-Output "*************************************************"
Write-Output "Concentrating on Nutanix PC environment.."
Write-Output "*************************************************"

# Set Prism Central password to the same as PE

$Payload='{"oldPassword":"Nutanix/4u","newPassword":"'+$password+'"}'
$APIParams = @{
    method="POST"
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/utils/change_default_system_password"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_PC_temp_creds
}

# Need to use the Default creds to get in and set the password, only once

$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck -Credential $cred)
if ($response = "True"){
    Write-Output "PC Password has been changed to the same as PE"
}else{
    Write-Output "PC Password has NOT been changed to the same as PE. Exiting script."
    exit 2
}

Write-Output "--------------------------------------"


# Accept the PC Eula

$APIParams = @{
    method="POST"
    Body='{"username":"NTNX","companyName":"NTNX","jobTitle":"NTNX"}'
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/eulas/accept"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response = "True"){
    Write-Output "Eula Accepted"
}else{
    Write-Output "Eula NOT accepted"
}

Write-Output "--------------------------------------"


# Disable PC pulse

$APIParams = @{
    method="PUT"
    Body='{"enable":"false","enableDefaultNutanixEmail":"false","isPulsePromptNeeded":"false"}'
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/pulse"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response = "True"){
    Write-Output "Pulse Disabled"
}else{
    Write-Output "Pulse NOT disabled"
}

Write-Output "--------------------------------------"

# Add the AutoAD as the Directory server

$directory_url="ldap://"+$AutoAD+":389"

  
Write-Output "Adding $AutoAD as the Directory Server"

$Payload=@"
{
"connection_type": "LDAP",
"directory_type": "ACTIVE_DIRECTORY",
"directory_url": "$directory_url",
"domain": "ntnxlab.local",
"group_search_type": "RECURSIVE",
"name": "NTNXLAB",
"service_account_username": "administrator@ntnxlab.local",
"service_account_password": "nutanix/4u"
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PC_IP+":9440/api/nutanix/v2.0/authconfig/directories/"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  if ($response = "True"){
      Write-Output "Authorization to use NTNXLab.local has been created"
  }else{
      Write-Output "Authorization to use NTNXLab.local has NOT been created"
  }

Write-Output "--------------------------------------"

# Add the Role to the SSP Admins group

Write-Output "Adding SSP Admins AD Group to Cluster Admin Role"

$Payload=@"
{
    "directoryName": "NTNXLAB",
    "role": "ROLE_CLUSTER_ADMIN",
    "entityType": "GROUP",
    "entityValues":[
        "SSP Admins"
    ]
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/authconfig/directories/NTNXLAB/role_mappings?&entityType=GROUP&role=ROLE_CLUSTER_ADMIN"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  if ($response = "True"){
      Write-Output "Authorization to use NTNXLab.local has been created"
  }else{
      Write-Output "Authorization to use NTNXLab.local has NOT been created"
  }


Write-Output "Role Added"
Write-Output "--------------------------------------"


# **********************************************************************************
# Enable Calm
# **********************************************************************************
Write-Output "Enabling Calm"


# Need to check if the PE to PC registration has been done before we move forward to enable Calm. If we've done that, move on.

$APIParams = @{
    method="POST"
    Body='{"perform_validation_only":true}'
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/nucalm"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).validation_result_list.has_passed
while ($response.length -lt 5){
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).validation_result_list.has_passed
}

# Enable Calm

$APIParams = @{
    method="POST"
    Body='{"enable_nutanix_apps":true,"state":"ENABLE"}'
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/nucalm"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).state

# Sometimes the enabling of Calm is stuck due to an internal error. Need to retry then.

while ($response -Match "ERROR"){
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).state
}

# Check if Calm is enabled

$APIParams = @{
    method="GET"
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/nucalm/status"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_enablement_status
while ($response -NotMatch "ENABLED"){
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_enablement_status
}
sleep 60
Write-Output "Calm has been enabled"
Write-Output "--------------------------------------"

# **********************************************************************************
# Enable Objects
# **********************************************************************************
Write-Output "Enabling Objects"

# Enable Objects

$APIParams = @{
    method="POST"
    Body='{"state":"ENABLE"}'
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/oss"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

sleep 10
# Check if the Objects have been enabled
$APIParams = @{
    method="POST"
    Body='{"entity_type":"objectstore"}'
    Uri="https://"+$PC_IP+":9440/oss/api/nutanix/v3/groups"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).total_group_count

# Run a short waitloop before moving on

$counter=1
while ($response -lt 1){
    Write-Output "Objects not yet ready to be used. Waiting 10 seconds before retry ($counter/30)"
    sleep 10
    if ($counter -eq 30){
        Write-Output "We waited for five minutes and Objects didn't become enabled."
        break
    }
    $counter++
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).total_group_count
}
if ($counter -eq 30){
    Write-Output "Objects has not been enabled. Please use the UI.."
}else{
    Write-Output "Objects has been enabled"
}
Write-Output "--------------------------------------"

# **********************************************************************************
# Enable Leap
# **********************************************************************************
Write-Output "Checking if Leap can be enabled"

# Check if the Objects have been enabled

$APIParams = @{
    method="GET"
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/disaster_recovery/status?include_capabilities=true"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_capabilities.can_enable.state
if ($response -eq $true){
    Write-Output "Leap can be enabled, so progressing."
    $APIParams = @{
        method="POST"
        Body='{"state":"ENABLE"}'
        Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/disaster_recovery"
        ContentType="application/json"
        Header = $Header_NTNX_Creds
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).task_uuid
    # We have been given a task uuid, so need to check if SUCCEEDED as status
    $APIParams = @{
        method="GET"
        Uri="https://"+$PC_IP+":9440/api/nutanix/v3/tasks/"+$response
        ContentType="application/json"
        Header = $Header_NTNX_Creds
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
    # Loop for 2 minutes so we can check the task being run successfuly
    if ($response -NotMatch "SUCCEEDED"){
        $counter=1
        while ($response -NotMatch "SUCCEEDED"){
            sleep 10
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
            if ($counter -eq 12){
                Write-Output "Waited two minutes and Leap didn't get enabled! Please check the PC UI for the reason."
            }else{
                Write-Output "Leap has been enabled"
            }
        }
    }else{
        Write-Output "Leap has been enabled"
    }
}else{
    Write-Output "Leap can not be enabled! Please check the PC UI for the reason."
}
Write-Output "--------------------------------------"

# **********************************************************************************
# Enable Karbon
# **********************************************************************************
Write-Output "Enabling Karbon"

$Payload_en='{"value":"{\".oid\":\"ClusterManager\",\".method\":\"enable_service_with_prechecks\",\".kwargs\":{\"service_list_json\":\"{\\\"service_list\\\":[\\\"KarbonUIService\\\",\\\"KarbonCoreService\\\"]}\"}}"}'
$Payload_chk='{"value":"{\".oid\":\"ClusterManager\",\".method\":\"is_service_enabled\",\".kwargs\":{\"service_name\":\"KarbonUIService\"}}"}'

# Enable Karbon

$APIParams = @{
    method="POST"
    Body=$Payload_en
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/genesis"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
if ($response.value -Match "true"){
    Write-Output "Enable Karbon command has been received. Waiting for karbon to be ready"
}else{
    Write-Output "Retrying enablening Karbon one more time"
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    sleep 10
}

# Checking if Karbon has been enabled

$APIParams = @{
    method="POST"
    Body=$Payload_chk
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/genesis"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
$counter=1
while ($response.value -NotMatch "true"){
    Write-Output "Karbon is not ready"
    sleep 10
    if ($counter -eq 12){
        Write-Output "We tried for 2 minutes and Karbon is still not enabled."
        break
    }
    $counter++
}
if ($counter -eq 12){
    Write-Output "Please use the UI to enable Karbon"
}else{
    Write-Output "Karbon has been enabled"
}

Write-Output "--------------------------------------"

# **********************************************************************************
# Run LCM
# **********************************************************************************
# RUN Inventory
$Payload='{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"perform_inventory\",\"args\":[\"http://download.nutanix.com/lcm/2.0\"]}}"}'
$APIParams = @{
    method="POST"
    Body=$Payload
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/genesis"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck) 
$task_id=($response.value.Replace(".return","task_id")|ConvertFrom-JSON).task_id

# Wait till the LCM inventory job has ran using the task_id we got earlier
$APIParams = @{
        method="GET"
        Uri="https://"+$PC_IP+":9440/api/nutanix/v3/tasks/"+$task_id
        ContentType="application/json"
        Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status

$counter=1
While ($response -NotMatch "SUCCEEDED"){
    write-output "Waiting for LCM inventroy to have completed ($counter/45 mins)."
    sleep 60
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
    if ($counter -eq 45){
        write-out "We have waited for 45 minutes and the LCM did not finish."
        write-out "Please use the PC UI to update the environment."
        Break
    }
    $counter++
}
if ($countert -eq 45){
    write-output "LCM inventory has failed"
}else{
    write-output "LCM Inventory has run successful. Progressing..."
}


# What can we update?
$APIParams = @{
    method="POST"
    Body='{}'
    Uri="https://"+$PC_IP+":9440/lcm/v1.r0.b1/resources/entities/list"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

[array]$uuids=$response.data.entities.uuid
[array]$versions=""
[array]$updates=""
$count=0
foreach ($uuid in $uuids){
    try{
        [array]$version = (($response.data.entities | where {$_.uuid -eq $uuids[$count]}).available_version_list.version | sort-object)
        $software=($response.data.entities | where {$_.uuid -eq $uuids[$count]}).entity_model
        if ($software -NotMatch "pc" -Or $software -NotMatch "NCC"){ # Remove PC and NCC from the upgrade list
            [array]$updates += $software+","+$uuid+","+$version[-1]
        }
    }catch{
        echo "empty UUID" |Out-Null
    }
    $count ++
}
# Build the JSON Payload
$json_payload_lcm='['
foreach ($update in $updates){
    if($update.split(",")[1] -ne $null) {
        $json_payload_lcm +='{"version":"'+$update.Split(",")[2]+'","entity_uuid":"'+$update.Split(",")[1]+'"},'
    }
}
$json_payload_lcm = $json_payload_lcm.subString(0,$json_payload_lcm.length-1) +']'

echo $json_payload_lcm
exit 0

# Can we update?
$APIParams = @{
    method="POST"
    Body=$json_payload_lcm
    Uri="https://"+$PC_IP+":9440/lcm/v1.r0.b1/resources/notifications"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

if ($response.data.upgrade_plan.to_version.length -lt 1){
    echo "LCM can not be run as there is nothing to upgrade.."
}else{
    echo "Firing the upgrade to the LCM platform"
    $json_payload_lcm_upgrade='{"entity_update_spec_list":'+$json_payload_lcm+'}'
    $APIParams = @{
        method="POST"
        Body=$json_payload_lcm_upgrade
        Uri="https://"+$PC_IP+":9440/lcm/v1.r0.b1/operations/update"
    
        ContentType="application/json"
        Header = $Header_NTNX_Creds
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

    $taskuuid=$response.data.task_uuid

    # Wait loop for the TaskUUID to check if done
    $APIParams = @{
        method="GET"
        Uri="https://"+$PC_IP+":9440/api/nutanix/v3/tasks/"+$taskuuid
        ContentType="application/json"
        Header = $Header_NTNX_Creds
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
    # Loop for 2 minutes so we can check the task being run successfuly
    $counter=1
    while ($response -NotMatch "SUCCEEDED"){
        write-output "LCM Upgrade still running ($counter/45 mins)...Retrying in 1 minute."
        sleep 60
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        if ($counter -eq 45){
            break
        }
        $counter ++
    }
    if ($counter -eq 45){
        Write-Output "Waited 45 minutes and LCM didn't finish the updates! Please check the PC UI for the reason."
    }else{
        Write-Output "LCM Ran successfully"
    }
}

# **********************************************************************************
# Add VMware as a provider for Calm
# **********************************************************************************


# **********************************************************************************
# Create Projects
# **********************************************************************************


# **********************************************************************************
# Create PC Admin and role
# **********************************************************************************


# **********************************************************************************
# Deploy and configure Era
# **********************************************************************************