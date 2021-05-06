# Specific Objects functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testobj{
    param(
        [string] $text
    )
    write-host "You reached module objects_mod.psm1"
    return $text
}

# Add an Objects store to the cluster (PC)
Function CreateObjects{
    param(
        [string] $IP,
        [object] $Header,
        [string] $password,
        [string] $VCENTER,
        [string] $AutoAD,
        [string] $ip_subnet

    )
    # Add vCenter to Objects UI including IPAM
    Write-Host "Adding vCenter to the Objects UI"
    $Payload=@"
    {
        "api_version":"1.0",
        "password":"$password",
        "username":"administrator@vsphere.local",
        "vcenter_endpoint":"$VCENTER"
    }
"@
    $APIParams = @{
        method="POST"
        Body=$Payload
        Uri="https://$($IP):9440/oss/api/nutanix/v3/platform_client"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).platform_client_uuid
    if ($response -ne $null){
        Write-Host "vCenter has been added with UUID $response"
        Start-Sleep 60 # Give the environment some time to settle

        # Add the IPAM setting to vCenter
        $Payload=@"
        {
            "api_version":"1.0",
            "esx_datacenter":"Datacenter1",
            "esx_network":"VM Network",
            "netmask":"255.255.255.128",
            "gateway":"$ip_subnet.1",
            "dns_servers":["$AutoAD"],
            "ip_ranges":[
                {
                    "start_ip":"$ip_subnet.15",
                    "end_ip":"$ip_subnet.18"
                }
            ]
        }
"@

        $APIParams = @{
            method="POST"
            Body=$Payload
            Uri="https://$($IP):9440/oss/api/nutanix/v3/platform_client/"+$response+"/ipam"
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        if ($response -ne $null){
            Write-Host "IPAM settings have been added to the vCenter configuration"
            $pre_config_ok="Yes"
        }else{
            Write-Host "IPAM settings have not been added to the vCenter configuration. Please use the UI to create the Object Store"
            $pre_config_ok="No"
        }
    }else{
        Write-Host "vCenter has not been added. Please use the UI to add vCenter to Objects"
        $pre_config_ok="No"
    }


    if ($pre_config_ok -Match "Yes"){
        Write-Host "Creating the Objectstore"
        # Get the Cluster UUID of the PE environment
        $Payload=@"
        {
            "entity_type":"cluster",
            "group_member_sort_attribute":"cluster_name",
            "group_member_sort_order":"ASCENDING",
            "group_member_attributes":[
                {
                    "attribute":"cluster_name"
                }
            ]
        }
"@
        $APIParams = @{
            method="POST"
            Body=$Payload
            Uri="https://$($IP):9440/api/nutanix/v3/groups"
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        $cluster_uuid=($response.group_results.entity_results | where-object {$_.data.values.values -Match $cluster_name}).entity_id

        # Get the network UUIDs of the VM Network network
        
        $APIParams = @{
            method="GET"
            Uri="https://$($IP):9440/oss/api/nutanix/v3/platform_client/pe_ipams/"+$cluster_uuid
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        $net_uuid=$response.pe_ipam_list.ipam_name

        # Build the payload for the Objects Store creation

        $Payload=@"
        {
            "api_version":"3.0",
            "metadata":{
                "kind":"objectstore"
            },
            "spec":{
                "name":"ntnx-object",
                "description":"ntnx-object",
                "resources":{
                    "domain":"ntnxlab.local",
                    "cluster_reference":{
                        "kind":"cluster","uuid":"$cluster_uuid"
                    },
                    "buckets_infra_network_dns":"",
                    "buckets_infra_network_vip":"",
                    "buckets_infra_network_reference":{
                        "kind":"subnet",
                        "uuid":"$net_uuid"
                    },
                    "client_access_network_reference":{
                        "kind":"subnet","uuid":"$net_uuid"
                    },
                    "aggregate_resources":{
                        "total_vcpu_count":10,
                        "total_memory_size_mib":32768,
                        "total_capacity_gib":5120
                    },
                    "client_access_network_ipv4_range":{
                        "ipv4_start":"$ip_subnet.19",
                        "ipv4_end":"$ip_subnet.22"
                    }
                }
            }
        } 
"@
        $APIParams = @{
            method="POST"
            Body=$Payload
            Uri="https://$($IP):9440/oss/api/nutanix/v3/objectstores"
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

        # Let's check if the call succeeded and wait for oit to become available for 30 min
        $Payload=@"
        {
            "entity_type":"objectstore",
            "group_member_sort_attribute":"name",
            "group_member_sort_order":"ASCENDING",
            "group_member_count":20,
            "group_member_offset":0,
            "group_member_attributes":[
                {"attribute":"name"},
                {"attribute":"state"},
                {"attribute":"percentage_complete"}
            ]
        }
"@
        $APIParams = @{
            method="POST"
            Body=$Payload
            Uri="https://$($IP):9440/oss/api/nutanix/v3/groups"
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        $percentage=($response.group_results.entity_results.data | where-object {$_.name -Match "percentage_complete"}).values.values
        $counter=1
        while (($percentage -as [int]) -lt 15){
            Start-Sleep 60
            Write-Host "Objects store is at $percentage %. Retrying in 1 minute ($counter/30)..."
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
            $percentage=($response.group_results.entity_results.data | where-object {$_.name -Match "percentage_complete"}).values.values
            if ($counter -eq 30){
                Write-Host "We have waited 30 minutes and the Objects store has not reached the building process. Please look at the UI if it has become ready later."
                break
            }else{
                $counter++
            }
        }
        if ($counter -lt 30){
            if (($response.group_results.entity_results.data | where-object {$_.name -Match "state"}).values.values -NotMatch "FAILED"){
                return "The Objects store ntnx-object is still in the creation process. It has successfully passed the pre-check phase. We are not waiting anymore. Please check the UI for it's progress."
            }else{
                return "The Objects store ntnx-object has not been created successfully. Please check the UI to see the reason."
            }
        }
    }else{
        return "Due to earlier issues, an objects store can not be created. please use the UI to create one."
    }

}