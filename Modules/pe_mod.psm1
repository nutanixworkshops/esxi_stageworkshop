# Specific PE functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testpe{
    param(
        [string] $text
    )
    write-host "You reached module pe_mod.psm1"
    return $text
}

# Change the name of the Storage Pool to SP1
function ChangeSPName {
    param (
        [string] $IP,
        [object] $Header
    )
    # First get the Disk IDs
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/storage_pools?sortOrder=storage_pool_name"
        ContentType="application/json"
        Header = $Header
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
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/storage_pools?sortOrder=storage_pool_name"
        ContentType="application/json"
        Body=$Body
        Header = $Header
    }

    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
    if ($response="True"){
        return "Storage Pool has been renamed"
    }else{
        return "Storage Pool has not been renamed"
    }

}

# Change the name of the defaulxxxx storage container to Default
Function RenameDefaultCNTR{
    param (
        [string] $IP,
        [object] $Header
    )

    # Get the ID and UUID of the default container first
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/storage_containers"
        ContentType="application/json"
        Header = $Header
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
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/storage_containers"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    if ($response = "True"){
        return "Default Storage Container has been updated"
    }else{
        return "Default Storage Container has NOT been updated"
    }
}
# Create the Images datastore
Function CreateImagesCNTR{
    param (
        [string] $IP,
        [object] $Header
    )
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
    Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/storage_containers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    if ($response = "True"){
        return "Images Storage Container has been created"
    }else{
        return "Images Storage Container has NOT been created"
    }

}


# Mount the Images container to all ESXi hosts
Function MountImagesCNTR{
    param (
        [string] $IP,
        [object] $Header
    )
    # Get the ESXi Hosts UUIDS

    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/hosts/"
        ContentType="application/json"
        Header = $Header
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
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/containers/datastores/add_datastore"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        return "The Images container has been mounted on all ESXi hosts"
    }catch{
        return "The Images container has not been mounted on all ESXi hosts"
    }
}


# Deploy Prism Central
Function DeployPC{

    param(
        [string] $IP,
        [object] $Header,
        [string] $PC_IP,
        [string] $AutoAD,
        [string] $GW
    )



    Write-Host "Deploying the Prism Central to the environment"

    # Get the Storage UUID as we need it before we can deploy PC

    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/storage_containers"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $cntr_uuid=($response.entities | where-object {$_.name -Match "vmContainer1"}).storage_container_uuid

    # Get the Network UUID as we need it before we can deploy PC

    $APIParams = @{
    method="GET"
    Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/networks"
    ContentType="application/json"
    Body=$Payload
    Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $network_uuid=($response.entities | where-object {$_.name -Match "VM Network"}).uuid
    
    # Get the version of PC and select the latest version
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/upgrade/prism_central_deploy/softwares"
        ContentType="application/json"
        Body=$Payload
        Header = $Header_NTNX_Creds
        }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities
    $version_pc=($response.name | Sort-Object)[-1]
    
    $name=($response | where-object {$_.name -eq $version_pc}).name
    $version_pc_json=($response | where-object {$_.name -eq $version_pc}).version
    $data_size=536870912000
    $mem_size=27917287424
    
    # Build the deploy JSON and deploy PC using the foudn version
    $Payload=@"
        {
            "resources":{
                "version":"$version_pc_json",
                "should_auto_register":true,
                "pc_vm_list":[
                    {
                        "vm_name":"$name",
                        "container_uuid":"$cntr_uuid",
                        "num_sockets":6,
                        "data_disk_size_bytes":$data_size,
                        "memory_size_bytes":$mem_size,
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
    Uri="https://$($IP):9440/api/nutanix/v3/prism_central"
    ContentType="application/json"
    Body=$Payload
    Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        Write-Host "The PC download and deployment could not be executed. Exiting the script."
        Write-Host "Received error was: $_.Exception.Message"
        exit 1
    }


    Write-Host "Deployment of PC has started. Now need to wait till it is up and running"
    Write-Host "Waiting till PC is ready.. (could take up to 30+ minutes)"
    $counter=1
    $url="https://$($PC_IP):9440"

    # Need temporary default credentials

    $username = "admin"
    $password_default = "Nutanix/4u" | ConvertTo-SecureString -asPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($username,$password_default)
    while ($true){
        try{
            $response=invoke-Webrequest -Uri $url -TimeOut 15 -SkipCertificateCheck -Credential $cred
            Break
        }catch{
            Write-Host "PC still not ready. Sleeping 60 seconds before retrying...($counter/45)"
            Start-Sleep 60
            if ($counter -eq 45){
                Write-Host "We waited for 45 minutes and the PC didn't got ready in time..."
                exit 1
            }
            $counter++
        }
    }
        return "PC is ready for being used. Progressing..."
}

# Check if registration was successfull of PE to PC
Function PERegistered{
    param(
        [string] $IP,
        [object] $Header
    )

    Write-Host "Checking if PE has been registred to PC"
    $APIParams = @{
    method="GET"
    Uri="https://$($IP):9440/PrismGateway/services/rest/v1/multicluster/cluster_external_state"
    ContentType="application/json"
    Body=$Payload
    Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $count=1
    while ($response.clusterDetails.ipAddresses -eq $null){
        Write-Host "PE is not yet registered to PC. Waiting a bit more.."
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        Start-Sleep 60
        if ($count -gt 10){
            Write-Host "Waited for 10 minutes. Giving up. Exiting the script."
            exit 3
        }
        $count++
    }
    return "PE has been registered to PC. Progressing..."
}