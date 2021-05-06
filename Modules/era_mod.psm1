# Specific Era functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testera{
    param(
        [string] $text
    )
    write-host "You reached module era_mod.psm1"
    return $text
}


# VMware part done, focusing on Era/PE side of the house
# Checking to see if Era is available. 1. Get IP address of Era, 2. try to connect so we know it is ready, 3. configure to use static IP and configure Era.
# Getting IP address of Era VM
Function ConfigBasicEra{
    param(
        [string] $IP,
        [object] $Header,
        [object] $Header_Temp,
        [string] $Era_IP,
        [string] $ip_subnet,
        [string] $AutoAD,
        [string] $password,
        [string] $PE_IP
    )

    $Payload=@"
    {
        "entity_type":"mh_vm",
        "group_member_sort_attribute":"vm_name",
        "group_member_sort_order":"ASCENDING",
        "group_member_attributes":[
            {
                "attribute":"vm_name"
            },{
                "attribute":"ip_addresses"
            }
        ],
        "filter_criteria":"vm_name==Era"
    }
"@
    $APIParams = @{
        method="POST"
        Uri="https://$($IP):9440/api/nutanix/v3/groups"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $era_temp_ip=($response.group_results.entity_results.data | where-object {$_.name -Match "ip_addresses"}).values.values
    $counter=0
    while ($era_temp_ip -eq $null){
        Write-Host "VM is still not up. Waiting 60 seconds before retrying.."
        Start-Sleep 60
        if ($counter -eq 30){
            Write-Host "Era VM not started witin 30 minutes. Exiting script"
            exit 1
        }else{
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
            $era_temp_ip=($response.group_results.entity_results.data | where-object {$_.name -Match "ip_addresses"}).values.values
            $counter++
        }
    }

    # Now that we have the IP address of the era server, we need to check if Era is up and running

    $APIParams = @{
        method="GET"
        Uri="https://"+$era_temp_ip+"/era/v0.9/clusters"
        ContentType="application/json"
        Body=$Payload
        Header = $Header_Temp
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        while ($_.Exception.Response.StatusCode.Value__ -as [int] -ne 402){
            try{
                $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
            }catch{
                if ($_.Exception.Response.StatusCode.Value__ -as [int] -eq 402){
                    break
                }
            }
            Write-Host "Era server processes are not yet ready. Waiting 60 seconds before proceeding"
            start-sleep 60
        }
        Write-Host "Era server is up, now we can configure it"
    }
    # Configuring Era; Set password to match PE and PC
    $APIParams = @{
        method="POST"
        Body='{"password": "'+$password+'"}'
        Uri="https://"+$era_temp_ip+"/era/v0.9/auth/update"
        ContentType="application/json"
        Header = $Header_Temp
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    Write-Host "Era password set to PE and PC password."

    # Accepting EULA
    $APIParams = @{
        method="POST"
        Body='{"eulaAccepted": true}'
        Uri="https://"+$era_temp_ip+"/era/v0.9/auth/validate"
        ContentType="application/json"
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    Write-Host "Era Eula accepted."

    # Change Era IP to the .43
    $Command="/usr/bin/sshpass"
    $Argument = "-p Nutanix.1 ssh -2 -o ServerAliveCountMax=2 -o ServerAliveInterval=5 -o StrictHostKeyChecking=no era@$era_temp_ip `"echo yes |era-server -c 'era_server set ip="+$Era_IP+" gateway="+$ip_subnet+".1 netmask=255.255.255.128 nameserver="+$AutoAD+"'`""
    $era_change = Start-Process -FilePath $Command -ArgumentList $Argument -wait -NoNewWindow -PassThru

    # Is Era ready???
    $APIParams = @{
        method="GET"
        Uri="https://"+$Era_IP+"/era/v0.9/clusters"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        while ($_.Exception.Response.StatusCode.Value__ -as [int] -ne 200){
            try{
                $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
            }catch{
                if ($_.Exception.Response.StatusCode.Value__ -as [int] -eq 200){
                    break
                }
            }
            Write-Host "Era server processes are not yet ready. Waiting 60 seconds before proceeding"
            start-sleep 60
        }
    }
    Write-Host "Era IP address has changed to $Era_IP"


    # Configure Era - Basic configurations
    $Payload=@"
    {
        "dnsServers":[
            "$AutoAD"
        ],
        "ntpServers":[
            "0.centos.pool.ntp.org",
            "1.centos.pool.ntp.org",
            "2.centos.pool.ntp.org",
            "3.centos.pool.ntp.org",
            "pool.ntp.org"
        ],
        "smtpConfig":{
            "smtpServerIPPort":":",
            "smtpUsername":"",
            "smtpPassword":null,
            "isSmtpPasswordChanged":false,
            "emailFromAddress":"",
            "tlsEnabled":true,
            "testEmailToAddress":null,
            "slackAPIURL":null,
            "unsecured":false
        },
        "timezone":"UTC"
    }
"@

    $APIParams = @{
        method="PUT"
        Uri="https://"+$Era_IP+"/era/v0.9/config/era-server"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        sleep 10
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }


    # Configure Era - Phase 1 - API call

    $Payload=@"
    {
        "name":"EraCluster",
        "description":"Era Bootcamp Cluster",
        "ipAddresses":["$PE_IP"],
        "username":"admin",
        "password":"$password",
        "status":"UP",
        "version":"v2",
        "cloudType":"NTNX"
    }
"@

    $APIParams = @{
        method="POST"
        Uri="https://"+$Era_IP+"/era/v0.9/clusters"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        Write-Host "Waiting for 3 minutes as the Era server needs some time to settle..."
        sleep 180 # Sleeping 3 minutes before progressing
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }

    $cluster_uuid=$response.id


    # Configure Era - Phase 1 - Json Upload 

    $URL = "https://$Era_IP/era/v0.9/clusters/$cluster_uuid/json"
    $Json = @"
    {
    "protocol": "https",
    "ip_address": "$Era_IP",
    "port": "9440",
    "creds_bag": {
        "username": "admin",
        "password": "$password"
    }
    }
"@

    $filename = "$((get-date).ticks).json"
    $json | out-file $filename
    $filepath = (get-item $filename).fullname

    $fileBin = [System.IO.File]::ReadAlltext($filePath)
    #$fileEnc = [System.Text.Encoding]::GetEncoding('UTF-8').GetString($fileBytes);
    $boundary = [System.Guid]::NewGuid().ToString(); 
    $LF = "`r`n";

    $bodyLines = ( 
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$filename`"",
        "Content-Type: application/json$LF",
        $fileBin,
        "--$boundary--$LF" 
    ) -join $LF

    try {
        $task = Invoke-RestMethod -SkipCertificateCheck -Uri $URL -method POST -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines -headers $Header;
    } catch {
        sleep 10
        $task = Invoke-RestMethod -SkipCertificateCheck -Uri $URL -method POST -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines -headers $Header;
    }  


    # Configure Era - Phase 2 - API call

    $Payload=@"
    {
        "name":"EraCluster",
        "description":"Era Bootcamp Cluster",
        "ipAddresses":["$PE_IP"],
        "username":"admin",
        "password":"$password",
        "status":"UP",
        "version":"v2",
        "cloudType":"NTNX",
        "managementServerInfo":{
            "username":"administrator@vsphere.local",
            "password":"$password"
        }
    }
"@

    $APIParams = @{
        method="PUT"
        Uri="https://"+$Era_IP+"/era/v0.9/clusters/$cluster_uuid"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        sleep 10
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }

    # Configure Era - Phase 2 - Json Upload 

    $URL = "https://$Era_IP/era/v0.9/clusters/$cluster_uuid/json"
    $Json = @"
    {
    "protocol": "https",
    "ip_address": "$Era_IP",
    "port": "9440",
    "creds_bag": {
        "username": "admin",
        "password": "$password"
    }
    }
"@

    $filename = "$((get-date).ticks).json"
    $json | out-file $filename
    $filepath = (get-item $filename).fullname

    $fileBin = [System.IO.File]::ReadAlltext($filePath)
    #$fileEnc = [System.Text.Encoding]::GetEncoding('UTF-8').GetString($fileBytes);
    $boundary = [System.Guid]::NewGuid().ToString(); 
    $LF = "`r`n";

    $bodyLines = ( 
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$filename`"",
        "Content-Type: application/json$LF",
        $fileBin,
        "--$boundary--$LF" 
    ) -join $LF

    try {
        $task = Invoke-RestMethod -SkipCertificateCheck -Uri $URL -method POST -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines -headers $Header;
    } catch {
        sleep 10
        $task = Invoke-RestMethod -SkipCertificateCheck -Uri $URL -method POST -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines -headers $Header;
    }  

    # Configure Era - Phase 3 - API Call

    $Payload=@"
    {
        "name":"EraCluster",
        "description":"Era Bootcamp Cluster",
        "ipAddresses":["$PE_IP"],
        "username":"admin",
        "password":"$password",
        "status":"UP",
        "version":"v2",
        "cloudType":"NTNX",
        "properties":[
            {
                "name":"ERA_STORAGE_CONTAINER",
                "value":"vmContainer1"
            }
        ]
    }
"@

    $APIParams = @{
        method="PUT"
        Uri="https://"+$Era_IP+"/era/v0.9/clusters/$cluster_uuid"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        sleep 10
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }

    # Configure Era - Phase 3 - Json Upload 

    $URL = "https://$Era_IP/era/v0.9/clusters/$cluster_uuid/json"
    $Json = @"
    {
    "protocol": "https",
    "ip_address": "$Era_IP",
    "port": "9440",
    "creds_bag": {
        "username": "admin",
        "password": "$password"
    }
    }
"@

    $filename = "$((get-date).ticks).json"
    $json | out-file $filename
    $filepath = (get-item $filename).fullname

    $fileBin = [System.IO.File]::ReadAlltext($filePath)
    #$fileEnc = [System.Text.Encoding]::GetEncoding('UTF-8').GetString($fileBytes);
    $boundary = [System.Guid]::NewGuid().ToString(); 
    $LF = "`r`n";

    $bodyLines = ( 
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$filename`"",
        "Content-Type: application/json$LF",
        $fileBin,
        "--$boundary--$LF" 
    ) -join $LF

    try {
        $task = Invoke-RestMethod -SkipCertificateCheck -Uri $URL -method POST -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines -headers $Header;
    } catch {
        sleep 10
        $task = Invoke-RestMethod -SkipCertificateCheck -Uri $URL -method POST -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines -headers $Header;
    } 
    Write-Host "PE has been registered as the Cluster for Era."

    # Create the needed network

    $Payload=@"
    {
        "name": "Secondary",
        "type": "Static",
        "clusterId": "$cluster_uuid",
        "ipPools": [
            {
                "startIP": "$ip_subnet.211",
                "endIP": "$ip_subnet.253"
            }
        ],
        "properties": [
            {
                "name": "VLAN_GATEWAY",
                "value": "$ip_subnet.129"
            },
            {
                "name": "VLAN_PRIMARY_DNS",
                "value": "$AutoAD"
            },
            {
                "name": "VLAN_SUBNET_MASK",
                "value": "255.255.255.128"
            },
            {
            "name": "VLAN_DNS_DOMAIN",
                "value": "ntnxlab.local"
            }
        ]
        }
    }
"@

    $APIParams = @{
        method="POST"
        Uri="https://"+$Era_IP+"/era/v0.9/resources/networks"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        sleep 10 # Sleeping 3 minutes before progressing
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }

    Write-Host "Network has been created"
    return "Era has been installed with basic configuration"
}

# Create the compute Profiles
Function EraComputeProfiles{
    param(
        [string] $Era_IP,
        [object] $Header
    )
    # Create the Compute profiles
    $Payload=@"
    {
        "type": "Compute",
        "topology": "ALL",
        "dbVersion": "ALL",
        "systemProfile": false,
        "properties": [
        {
            "name": "CPUS",
            "value": "1",
            "description": "Number of CPUs in the VM"
        },
        {
            "name": "CORE_PER_CPU",
            "value": "2",
            "description": "Number of cores per CPU in the VM"
        },
        {
            "name": "MEMORY_SIZE",
            "value": 4,
            "description": "Total memory (GiB) for the VM"
        }
        ],
        "name": "CUSTOM_EXTRA_SMALL"
    }
"@

    $APIParams = @{
        method="POST"
        Uri="https://"+$Era_IP+"/era/v0.9/profiles"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        sleep 10 # Sleeping 3 minutes before progressing
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }

    $Payload=@"
    {
        "type": "Compute",
        "topology": "ALL",
        "dbVersion": "ALL",
        "systemProfile": false,
        "properties": [
        {
            "name": "CPUS",
            "value": "4",
            "description": "Number of CPUs in the VM"
        },
        {
            "name": "CORE_PER_CPU",
            "value": "1",
            "description": "Number of cores per CPU in the VM"
        },
        {
            "name": "MEMORY_SIZE",
            "value": 5,
            "description": "Total memory (GiB) for the VM"
        }
        ],
        "name": "LAB_COMPUTE"
    }
"@

    $APIParams = @{
        method="POST"
        Uri="https://"+$Era_IP+"/era/v0.9/profiles"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        sleep 10 # Sleeping 3 minutes before progressing
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }

    return "Compute profiles have been created"
}

# Create the NTNXLAB Domain Profile
Function EraDomainProfile{
    param(
        [string] $Era_IP,
        [object] $Header
    )

    $Payload=@"
    {
        "engineType": "sqlserver_database",
        "type": "WindowsDomain",
        "topology": "ALL",
        "dbVersion": "ALL",
        "systemProfile": false,
        "properties": [
        {
            "name": "DOMAIN_NAME",
            "value": "ntnxlab.local",
            "secure": false,
            "description": "Name of the Windows domain"
        },
        {
            "name": "DOMAIN_USER_NAME",
            "value": "Administrator@ntnxlab.local",
            "secure": false,
            "description": "Username with permission to join computer to domain"
        },
        {
            "name": "DOMAIN_USER_PASSWORD",
            "value": "nutanix/4u",
            "secure": false,
            "description": "Password for the username with permission to join computer to domain"
        },
        {
            "name": "DB_SERVER_OU_PATH",
            "value": "",
            "secure": false,
            "description": "Custom OU path for database servers"
        },
        {
            "name": "CLUSTER_OU_PATH",
            "value": "",
            "secure": false,
            "description": "Custom OU path for server clusters"
        },
        {
            "name": "SQL_SERVICE_ACCOUNT_USER",
            "value": "Administrator@ntnxlab.local",
            "secure": false,
            "description": "Sql service account username"
        },
        {
            "name": "SQL_SERVICE_ACCOUNT_PASSWORD",
            "value": "nutanix/4u",
            "secure": false,
            "description": "Sql service account password"
        },
        {
            "name": "ALLOW_SERVICE_ACCOUNT_OVERRRIDE",
            "value": false,
            "secure": false,
            "description": "Allow override of sql service account in provisioning workflows"
        },
        {
            "name": "ERA_WORKER_SERVICE_USER",
            "value": "Administrator@ntnxlab.local",
            "secure": false,
            "description": "Era worker service account username"
        },
        {
            "name": "ERA_WORKER_SERVICE_PASSWORD",
            "value": "nutanix/4u",
            "secure": false,
            "description": "Era worker service account password"
        },
        {
            "name": "RESTART_SERVICE",
            "value": "",
            "secure": false,
            "description": "Restart sql service on the dbservers"
        },
        {
            "name": "UPDATE_CREDENTIALS_IN_DBSERVERS",
            "value": "true",
            "secure": false,
            "description": "Update the credentials in all the dbservers"
        }
        ],
        "name": "NTNXLAB"
    }
"@

    $APIParams = @{
        method="POST"
        Uri="https://"+$Era_IP+"/era/v0.9/profiles"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        sleep 10 # Sleeping 3 minutes before progressing
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }

    Return "NTNXLAB Domain profile has been created"
}

# Create the MariaDB network Profile
Function EraMariaDBNetwork{
    param(
        [string] $Era_IP,
        [object] $Header
    )
    $APIParams = @{
        method="GET"
        Uri="https://"+$Era_IP+"/era/v0.9/clusters"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        Write-Host "Waiting for 3 minutes as the Era server needs some time to settle..."
        sleep 180 # Sleeping 3 minutes before progressing
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }
    $cluster_uuid=$response.id

    $Payload=@"
    {
        "engineType":"mariadb_database",
        "type":"Network",
        "topology":"ALL",
        "dbVersion":"ALL",
        "systemProfile":false,
        "properties":[
            {
                "name":"VLAN_NAME",
                "value":"Secondary",
                "secure":false,
                "description":"Name of the vLAN"
            }
        ],
        "versionClusterAssociation":[
            {
                "nxClusterId":"$cluster_uuid"
            }
        ],
        "name":"Era_Managed_MariaDB",
        "description":"Era Managed VLAN"
    }
"@

    $APIParams = @{
        method="POST"
        Uri="https://"+$Era_IP+"/era/v0.9/profiles"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }catch{
        sleep 10 # Sleeping 3 minutes before progressing
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }
    return "Era_Managed_MariaDB network profile has been created"
}
