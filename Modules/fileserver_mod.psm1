# Specific Fileserver functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testfile{
    param(
        [string] $text
    )
    write-host "You reached module fileserver_mod.psm1"
    return $text
}

# Download the needed FS installation stuff (PE)
Function DownloadDeployFS{
    param(
        [string] $IP,
        [object] $Header
    )

    Write-Host "Preparing the download of the File Server Binaries."
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/upgrade/afs/softwares"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        [array]$names=($response.entities.name | sort-object)
        $name_afs=$names[-1]    
    }catch{
        Start-Sleep 300 # PE needs some time to settle on the upgradeable version before we can grab them... Then retry..
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        [array]$names=($response.entities.name | sort-object)
        $name_afs=$names[-1]
    }
    Write-Host "Downloading File Server version $name_afs"
    $version_afs_need=($response.entities | where-object {$_.name -eq $name_afs}).version
    $md5sum_afs_need=($response.entities | where-object {$_.name -eq $name_afs}).md5sum
    $totalsize_afs_need=($response.entities | where-object  {$_.name -eq $name_afs}).totalSizeInBytes
    $url_afs_need=($response.entities | where-object {$_.name -eq $name_afs}).url
    $comp_nos_ver_afs_need=($response.entities | where-object {$_.name -eq $name_afs}).compatibleNosVersions | ConvertTo-JSON
    $comp_ver_afs_need=($response.entities | where-object {$_.name -eq $name_afs}).compatibleVersions | ConvertTo-JSON
    $release_afs_need=($response.entities | where-object {$_.name -eq $name_afs}).releaseDate
    $comp_fsvm_afs_need=($response.entities | where-object {$_.name -eq $name_afs}).compatibleFsmVersions | ConvertTo-Json

    # Build the Payload
    $Payload=@"
    {
        "name":"$name_afs",
        "version":"$version_afs_need",
        "md5Sum":"$md5sum_afs_need",
        "totalSizeInBytes":$totalsize_afs_need,
        "softwareType":"FILE_SERVER",
        "url":"$url_afs_need",
        "compatibleNosVersions":$comp_nos_ver_afs_need,
        "compatibleVersions":$comp_ver_afs_need,
        "releaseDate":$release_afs_need,
        "compatibleFsmVersions":$comp_fsvm_afs_need
    }
"@

    $APIParams = @{
        method="POST"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/upgrade/afs/softwares/"+$name_afs+"/download"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

    # Getting the status to be completed
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/upgrade/afs/softwares"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities | where-object {$_.name -eq $name_afs}

    Write-Host "Download of the File Server with version $name_afs has started"
    $status=$response.status
    $counter=1
    while ($status -ne "COMPLETED"){
        Write-Host "Software is still being downloaded ($counter/20). Retrying in 1 minute.."
        Start-Sleep 60
        if ($counter -eq 20){
            Write-Host "We have tried for 20 minutes and still not ready."
            break;
        }
        $counter ++
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities | where-object {$_.name -eq $name_afs}
        $status=$response.status
    }
    if ($counter -eq 20){
        return "Please use the UI to get the File server installed"
    }else{
        Write-Host "The software for the File Server has been downloaded, deploying..."

        # Get the Network UUIDs that we need
        $APIParams = @{
            method="GET"
            Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/networks"
            ContentType="application/json"
            Header = $Header
        }
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        $network_uuid_vm_network=($response.entities | where-object {$_.name -eq "VM Network"}).uuid
        $network_uuid_secondary=($response.entities | where-object {$_.name -eq "Secondary"}).uuid


        # Build the Payload json
        $ip_subnet=$PE_IP.Substring(0,$PE_IP.Length-3)
        $Payload=@"
        {
            "name":"BootCampFS",
            "numCalculatedNvms":"1",
            "numVcpus":"4",
            "memoryGiB":"12",
            "internalNetwork":{
                "subnetMask":"255.255.255.128",
                "defaultGateway":"$ip_subnet.1",
                "uuid":"$network_uuid_vm_network",
                "pool":["$ip_subnet.13 $ip_subnet.13"]
            },
            "externalNetworks":[
                {
                    "subnetMask":"255.255.255.128",
                    "defaultGateway":"$ip_subnet.129",
                    "uuid":"$network_uuid_secondary",
                    "pool":["$ip_subnet.140 $ip_subnet.140"]
                }
            ],
            "windowsAdDomainName":"ntnxlab.local",
            "windowsAdUsername":"administrator",
            "windowsAdPassword":"nutanix/4u",
            "dnsServerIpAddresses":["$ip_subnet.41"],
            "ntpServers":["pool.ntp.org"],
            "sizeGib":"1024",
            "version":"$name_afs",
            "dnsDomainName":"ntnxlab.local",
            "nameServicesDTO":{
                "adDetails":{
                    "windowsAdDomainName":"ntnxlab.local",
                    "windowsAdUsername":"administrator",
                    "windowsAdPassword":"nutanix/4u",
                    "addUserAsFsAdmin":true,
                    "protocolType":"1"
                }
            },
            "addUserAsFsAdmin":true,
            "fsDnsOperationsDTO":{
                "dnsOpType":"MS_DNS",
                "dnsServer":"",
                "dnsUserName":"administrator",
                "dnsPassword":"nutanix/4u"
            }
        }
"@
        $APIParams = @{
            method="POST"
            Uri="https://$($IP):9440/PrismGateway/services/rest/v1/vfilers"
            ContentType="application/json"
            Body=$Payload
            Header = $Header
        }
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        $taskuuid=$response.taskUuid

        # Wait loop for the TaskUUID to check if done
        $APIParams = @{
            method="GET"
            Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$taskuuid
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status

        # Loop for 20 minutes so we can check the task being run successfuly
        $counter=1
        while ($response -NotMatch "SUCCEEDED"){
            Write-Host "File Server Deployment is still running ($counter/20 mins)...Retrying in 1 minute."
            Start-Sleep 60
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
            if ($counter -eq 20){
                break
            }
            $counter ++
        }
        if ($counter -eq 20){
            return "Waited 20 minutes and the File Server deployment didn't finish in time!"
        }else{
            return "File Server deployment has been successful. Progressing..."
        }
    
    }
}   

# Deploy File Server Analytics (PE)
Function DeployFSAnalytics{
    param(
        [string] $IP,
        [object] $Header
    )

    # Get the vserion that can be deployed
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/upgrade/file_analytics/softwares"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    [array]$versions=($response.entities.name | sort-object)
    $version=$versions[-1]

    # Get the network UUID of the VM Network
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/networks"
        ContentType="application/json"
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $network_uuid_vm_network=($response.entities | where-object {$_.name -eq "VM Network"}).uuid

    # Get the UUID of the vmContainer1 container
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/storage_containers"
        ContentType="application/json"
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $cntr_uuid_vm=($response.entities | where-object {$_.name -eq "vmContainer1"}).storage_container_uuid

    # Build the Payload
    $Payload=@"
    {
        "image_version":"$version",
        "vm_name":"Analytics",
        "network":{
            "uuid":"$network_uuid_vm_network",
            "ip":"$ip_subnet.14",
            "netmask":"255.255.255.128",
            "gateway":"$ip_subnet.1"
        },
        "resource":{
            "memory":"24",
            "vcpu":"8"
        },
        "dns_servers":["$AutoAD"],
        "ntp_servers":["pool.ntp.org"],
        "disk_size":"2",
        "container_uuid":"$cntr_uuid_vm",
        "container_name":"vmContainer1"
    }
"@

    # Deploy the File Analytics solution
    $APIParams = @{
        method="POST"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/analyticsplatform"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $taskuuid=$response.task_uuid

    # Wait loop for the TaskUUID to check if done
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$taskuuid
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status

    # Loop for 20 minutes so we can check the task being run successfuly
    $counter=1
    while ($response -NotMatch "SUCCEEDED"){
        Write-Host "File Analytics deployment is still running ($counter/20 mins)...Retrying in 1 minute."
        Start-Sleep 60
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        if ($counter -eq 20){
            break
        }
        $counter ++
    }
    if ($counter -eq 20){
        return "Waited 20 minutes and the File Analytics deployment didn't finish in time!"
    }else{
        return "File Analytics deployment has been successful. Progressing..."
    }
}