# Specific PC functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testpc{
    param(
        [string] $text
    )
    write-host "You reached module pc_mod.psm1"
    return $text
}

# Reset PC Password to match PE's password
Function ResetPCPassword{
    param(
        [string] $IP,
        [string] $password,
        [object] $Header
    )
    # Set Prism Central password to the same as PE

    $Payload='{"oldPassword":"Nutanix/4u","newPassword":"'+$password+'"}'
    $APIParams = @{
        method="POST"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/utils/change_default_system_password"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }

    # Need to use the Default creds to get in and set the password, only once

    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    if ($response = "True"){
        return "PC Password has been changed to the same as PE"
    }else{
        return "PC Password has NOT been changed to the same as PE. Exiting script."
        exit 2
    }
}

# LCM run inventory and upgrade all, except PC and NCC
Function PCLCMRun{
    param(
        [string] $IP,
        [object] $Header
    )

    Write-Host "Running LCM Inventory"
    # RUN Inventory
    $Payload='{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"perform_inventory\",\"args\":[\"http://download.nutanix.com/lcm/2.0\"]}}"}'
    $APIParams = @{
        method="POST"
        Body=$Payload
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/genesis"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck) 
    $task_id=($response.value.Replace(".return","task_id")|ConvertFrom-JSON).task_id

    # Wait till the LCM inventory job has ran using the task_id we got earlier
    $APIParams = @{
            method="GET"
            Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$task_id
            ContentType="application/json"
            Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status

    $counter=1
    While ($response -NotMatch "SUCCEEDED"){
        Write-Host "Waiting for LCM inventory to be completed ($counter/45 mins)."
        Start-Sleep 60
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        if ($counter -eq 45){
            write-out "We have waited for 45 minutes and the LCM did not finish."
            write-out "Please use the PC UI to update the environment."
            Break
        }
        $counter++
    }
    if ($countert -eq 45){
        return "LCM inventory has failed"
    }else{
        Write-Host "LCM Inventory has run successful. Progressing..."
    }


    # What can we update?
    $APIParams = @{
        method="POST"
        Body='{}'
        Uri="https://$($IP):9440/lcm/v1.r0.b1/resources/entities/list"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

    [array]$uuids=$response.data.entities.uuid
    [array]$versions=""
    [array]$updates=""
    $count=0
    foreach ($uuid in $uuids){
        try{
            [array]$version = (($response.data.entities | where-object {$_.uuid -eq $uuids[$count]}).available_version_list.version | sort-object)
            $software=($response.data.entities | where-object {$_.uuid -eq $uuids[$count]}).entity_model
            if ($software -NotMatch "NCC"){ # Remove NCC from the upgrade list
                [array]$updates += $software+","+$uuid+","+$version[-1]
            }
        }catch{
            Write-Host "No update for $software"
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
    # Can we update?
    $APIParams = @{
        method="POST"
        Body=$json_payload_lcm
        Uri="https://$($IP):9440/lcm/v1.r0.b1/resources/notifications"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

    if ($response.data.upgrade_plan.to_version.length -lt 1){
        return "LCM can not be run as there is nothing to upgrade.."
    }else{
        Write-Host "Firing the upgrade to the LCM platform"
        $json_payload_lcm_upgrade='{"entity_update_spec_list":'+$json_payload_lcm+'}'
        $APIParams = @{
            method="POST"
            Body=$json_payload_lcm_upgrade
            Uri="https://$($IP):9440/lcm/v1.r0.b1/operations/update"
        
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

        $taskuuid=$response.data.task_uuid

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
            Write-Host "LCM Upgrade still running ($counter/60 mins)...Retrying in 1 minute."
            Start-Sleep 60
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
            if ($counter -eq 60){
                break
            }
            $counter ++
        }
        if ($counter -eq 60){
            return "Waited 60 minutes and LCM didn't finish the updates! Please check the PC UI for the reason."
        }else{
            return "LCM Ran successfully"
        }
    }
}

# Enable Calm
Function EnableCalm{
    param(
        [string] $IP,
        [object] $Header
    )
    $APIParams = @{
        method="POST"
        Body='{"enable_nutanix_apps":true,"state":"ENABLE"}'
        Uri="https://$($IP):9440/api/nutanix/v3/services/nucalm"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).state

    # Sometimes the enabling of Calm is stuck due to an internal error. Need to retry then.

    while ($response -Match "ERROR"){
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
    Return "Calm has been enabled"
}

# Enable Objects
Function EnableObjects{
    param(
        [string] $IP,
        [object] $Header
    )

    Write-Host "Enabling Objects"
    $APIParams = @{
        method="POST"
        Body='{"state":"ENABLE"}'
        Uri="https://$($IP):9440/api/nutanix/v3/services/oss"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    
    Start-Sleep 120

    # Check if the Objects have been enabled
    $APIParams = @{
        method="POST"
        Body='{"entity_type":"objectstore"}'
        Uri="https://$($IP):9440/oss/api/nutanix/v3/groups"
        ContentType="application/json"
        Header = $Header
    } 
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).total_group_count
    }catch{
        sleep 120
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).total_group_count
    }

    # Run a short waitloop before moving on

    $counter=1
    while ($response -lt 1){
        Write-Host "Objects not yet ready to be used. Waiting 10 seconds before retry ($counter/30)"
        Start-Sleep 10
        if ($counter -eq 30){
            break
        }
        $counter++
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).total_group_count
    }
    if ($counter -eq 30){
        return "Objects has not been enabled. Please use the UI.."
    }else{
        return "Objects has been enabled"
    }
}

# Enable Leap
Function EnableLeap{
    param(
        [string] $IP,
        [object] $Header
    )
    Write-Host "Checking if Leap can be enabled"

    # Check if the Objects have been enabled

    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/services/disaster_recovery/status?include_capabilities=true"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_capabilities.can_enable.state
    if ($response -eq $true){
        Write-Host "Leap can be enabled, so progressing."
        $APIParams = @{
            method="POST"
            Body='{"state":"ENABLE"}'
            Uri="https://$($IP):9440/api/nutanix/v3/services/disaster_recovery"
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).task_uuid
        # We have been given a task uuid, so need to check if SUCCEEDED as status
        $APIParams = @{
            method="GET"
            Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$response
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        # Loop for 2 minutes so we can check the task being run successfuly
        if ($response -NotMatch "SUCCEEDED"){
            $counter=1
            while ($response -NotMatch "SUCCEEDED"){
                Start-Sleep 10
                $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
                if ($counter -eq 12){
                    return "Waited two minutes and Leap didn't get enabled! Please check the PC UI for the reason."
                }else{
                    return "Leap has been enabled"
                }
            }
        }else{
            return "Leap has been enabled"
        }
    }else{
        return "Leap can not be enabled! Please check the PC UI for the reason."
    }
}

# Enable File Server manager
Function EnableFileServerMGR{
    param(
        [string] $IP,
        [object] $Header
    )
    Write-Host "Enabling File Server Manager"
    $APIParams = @{
        method="POST"
        Body='{"state":"ENABLE"}'
        Uri="https://$($IP):9440/api/nutanix/v3/services/files_manager"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

    # We have started the enablement of the file server manager, let's wait till it's ready
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/services/files_manager/status"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_enablement_status
    # Loop for 2 minutes so we can check the task being run successfuly
    if ($response -NotMatch "ENABLED"){
        $counter=1
        while ($response -NotMatch "ENABLED"){
            Start-Sleep 20
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_enablement_status
            if ($counter -eq 6){
                return "Waited two minutes and the Files Server Manager didn't get enabled! Please check the PC UI for the reason."
            }else{
                return "Files Server Manager not yet enabled. Retrying in 20 seconds"
            }
            $counter++
        }
    }else{
        return "Files Server Manager has been enabled"
    }
}