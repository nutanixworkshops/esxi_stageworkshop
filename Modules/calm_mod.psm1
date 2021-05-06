# Specific Calm functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Enable Calm
Function EnableCalm{
    param(
        [string] $IP,
        [object] $Header
    )
    Write-Host "Enabling Calm"

    # Need to check if the PE to PC registration has been done before we move forward to enable Calm. If we've done that, move on.

    $APIParams = @{
        method="POST"
        Body='{"perform_validation_only":true}'
        Uri="https://$($IP):9440/api/nutanix/v3/services/nucalm"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).validation_result_list.has_passed
    while ($response.length -lt 5){
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).validation_result_list.has_passed
    }

    # Enable Calm

    $APIParams = @{
        method="POST"
        Body='{"enable_nutanix_apps":true,"state":"ENABLE"}'
        Uri="https://$($IP):9440/api/nutanix/v3/services/nucalm"
        ContentType="application/json"
        Header = $Header
    } 
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).state
    }catch{
        sleep 10
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).state
    }

    # Sometimes the enabling of Calm is stuck due to an internal error. Need to retry then.

    while ($response -Match "ERROR"){
        sleep 10
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).state
    }

    # Check if Calm is enabled

    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/services/nucalm/status"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_enablement_status
    while ($response -NotMatch "ENABLED"){
        Start-Sleep 60
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_enablement_status
    }
    Start-Sleep 60
    return "Calm has been enabled"
}

# Add VMware as the provider
Function VMwareProviderCalm{
    param(
        [string] $IP,
        [object] $Header,
        [string] $VCENTER,
        [string] $password
    )
    $Payload=@"
    {
        "api_version":"3.0",
        "metadata":{
            "kind":"account"
        },
        "spec":{
            "name":"VMware",
            "resources":{
                "type":"vmware",
                "data":{
                    "server":"$VCENTER",
                    "username":"administrator@vsphere.local",
                    "password":{
                        "value":"$password",
                        "attrs":{
                            "is_secret_modified":true
                        }
                    },
                    "port":"443",
                    "datacenter":"Datacenter1"
                },
            "sync_interval_secs":1200
            }
        }
    }
"@

    $APIParams = @{
        method="POST"
        Body=$Payload
        Uri="https://$($IP):9440/api/nutanix/v3/accounts"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    # Get the admin uuid from the response
    $admin_uuid=$response.metadata.uuid

    # Verify the VMware provider
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/accounts/"+$admin_uuid+"/verify"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

    if ($response -Match "verified"){
        return "The VMware environment has been added as a provider.."
    }else{
        return "The VMware environment has not been added as a provider.."
        exit 4
    }
}

# Add BootCampInfra project to Calm
Function AddPRojectBootcampInfra{
    param(
        [string] $IP,
        [object] $Header
    )


    # Get the network UUIDs of the VM Network and the Secondary network
    $Payload=@"
    {
        "entity_type":"subnet",
        "group_member_count":40,
        "group_member_offset":0,
        "group_member_sort_attribute":"name",
        "group_member_sort_order":"ASCENDING",
        "group_member_attributes":[
            {
                "attribute":"name"
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
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).group_results
    $net_uuid_vm_network=($response.entity_results | where-object {$_.data.values.values -eq "VM Network"}).entity_id
    $net_uuid_secondary=($response.entity_results | where-object {$_.data.values.values -eq "Secondary"}).entity_id

    # Get the Nutanix PC account UUID

    $APIParams = @{
        method="POST"
        Body='{"kind":"account","filter":"type==nutanix_pc"}'
        Uri="https://$($IP):9440/api/nutanix/v3/accounts/list"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $nutanix_pc_account_uuid=$response.entities.metadata.uuid

    # Creating the Project BootCampInfra
    $Payload=@"
    {
        "api_version":"3.1.0",
        "metadata":{
        "kind":"project"
        },
        "spec":{
        "name":"BootcampInfra",
        "resources":{
            "account_reference_list":[
                {
                    "uuid":"$nutanix_pc_account_uuid",
                    "kind":"account",
                    "name":"nutanix_pc"
                }
            ],
            "subnet_reference_list":[
                {
                    "kind":"subnet",
                    "name": "Primary",
                    "uuid": "$net_uuid_vm_network"
                },
                {
                "kind":"subnet",
                "name": "Secondary",
                "uuid": "$net_uuid_secondary"
                }
            ],
            "user_reference_list":[
                {
                    "kind":"user",
                    "name":"admin",
                    "uuid":"00000000-0000-0000-0000-000000000000"
                }
            ],
            "environment_reference_list":[]
        }
        }
    }
"@

    $APIParams = @{
        method="POST"
        Body=$Payload
        Uri="https://$($IP):9440/api/nutanix/v3/projects"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $taskuuid=$response.status.execution_context.task_uuid

    # Wait loop for the TaskUUID to check if done
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$taskuuid
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status

    # Loop for 5 minutes so we can check the task being run successfuly
    $counter=1
    while ($response -NotMatch "SUCCEEDED"){
        Write-Host "Calm project not yet created ($counter/30)...Retrying in 10 seconds."
    Start-Sleep 10
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        if ($counter -eq 30){
            break
        }
        $counter ++
    }
    if ($counter -eq 30){
        Write-Host "Waited 5 minutes and the Calm Project hasn't been created! Please check the PC UI for the reason."
    }else{
        Write-Host "Calm project created succesfully!"
    }
}

# Assigning the VMware environment to the BootCampInfra
Function AddVMwareToBootcampInfra{
    param(
        [string] $IP,
        [object] $Header
    )
    # Get the UUID of the default project
    $Payload=@"
    {
        "entity_type":"project",
        "group_member_attributes":[
            {"attribute":"name"},
            {"attribute":"uuid"}
        ],
        "filter_criteria":"name==BootcampInfra",
        "group_member_offset":0,
        "group_member_count":1000
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
    $proj_uuid=$response.group_results.entity_results.entity_id

    # Get the Spec version of the Project
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/projects_internal/"+$proj_uuid
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $spec_version=$response.metadata.spec_version

    # Get the Administrator@vsphere.local uuid
    $APIParams = @{
        method="POST"
        Body='{"length":250,"filter":"name==VMware"}'
        Uri="https://$($IP):9440/api/nutanix/v3/accounts/list"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $admin_uuid=$response.entities.metadata.uuid

    # Add the Vmware provider to the BootcampInfra Project
    $Payload=@"
    {
        "spec":{
            "access_control_policy_list":[],
            "project_detail":{
                "name":"BootcampInfra",
                "resources":{
                    "account_reference_list":[
                        {
                            "kind":"account",
                            "uuid":"$admin_uuid"
                        }
                    ],
                    "environment_reference_list":[],
                    "user_reference_list":[
                        {
                            "kind":"user",
                            "name":"admin",
                            "uuid":"00000000-0000-0000-0000-000000000000"
                        }
                    ],
                    "tunnel_reference_list":[],
                    "external_user_group_reference_list":[],
                    "subnet_reference_list":[],
                    "external_network_list":[]
                }
            },
            "user_list":[],
            "user_group_list":[]
        },
        "api_version":"3.1",
        "metadata":{
            "categories_mapping":{},
            "spec_version":$spec_version,
            "kind":"project",
            "uuid":"$proj_uuid",
            "categories":{},
            "owner_reference":{
                "kind":"user",
                "name":"admin",
                "uuid":"00000000-0000-0000-0000-000000000000"
            }
        }
    }
"@

    $APIParams = @{
        method="PUT"
        Body=$Payload
        Uri="https://$($IP):9440/api/nutanix/v3/calm_projects/"+$proj_uuid
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $taskuuid=$response.status.execution_context.task_uuid

    # Wait loop for the TaskUUID to check if done
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$taskuuid
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status

    # Loop for 2 minutes so we can check the task being run successfuly
    $counter=1
    while ($response -NotMatch "SUCCEEDED"){
        Write-Host "Calm project not yet updated ($counter/12)...Retrying in 10 seconds."
        Start-Sleep 10
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        if ($counter -eq 12){
            break
        }
        $counter ++
    }
    if ($counter -eq 12){
        return "Waited 2 minutes and the Calm Project didn't update! Please check the PC UI for the reason."
    }else{
        return "Calm project updated succesfully!"
    }
}
