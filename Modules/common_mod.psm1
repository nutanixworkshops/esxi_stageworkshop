# Commonly used functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testcommon{
    param(
        [string] $text
    )
    write-host "You reached module Common_mod.psm1"
    return $text
}

# Get the Clustername
function GetClustername {
    param (
        [string] $IP,
        [object] $Header
    )

    $URL="https://$($IP):9440/api/nutanix/v3/clusters/list"
    $Payload='{"kind":"cluster","length":500,"offset":0}'
    
    $cluster_name=(Invoke-RestMethod -Method "POST" -Body $Payload -Uri $URL -ContentType 'application/json' -Headers $($Header) -SkipCertificateCheck).entities.status.name
    return $cluster_name
}

# Accept the EULA

function AcceptEula{
    param(
        [string] $IP,
        [object] $Header
    )

    $APIParams = @{
        method="POST"
        Body='{"username":"NTNX","companyName":"NTNX","jobTitle":"NTNX"}'
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/eulas/accept"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
    if ($response = "True"){
        Write-Host "Eula Accepted"
    }else{
        Write-Host "Eula not accepted"
    }
}

# Disable Pulse
function DisablePulse {
    param (
        [string] $IP,
        [object] $Header
    )
    $APIParams = @{
        method="PUT"
        Body='{"enable":"false","enableDefaultNutanixEmail":"false","isPulsePromptNeeded":"false"}'
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/pulse"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
    if ($response = "True"){
        return "Pulse Disabled"
    }else{
        return "Pulse NOT disabled"
    }
}

# Confiure PE or PC to use AutoAD for authentication and DNS server
Function AddAutoADtoPE{
    param(
        [string] $AutoAD,
        [string] $IP,
        [object] $Header
    )


    $directory_url="ldap://"+$AutoAD+":389"
    
    Write-Host "Adding $AutoAD as the Directory Server"

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
        Uri="https://$($IP):9440/api/nutanix/v2.0/authconfig/directories/"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    if ($response = "True"){
        Write-Host "Authorization to use NTNXLab.local has been created"
    }else{
        Write-Host "Authorization to use NTNXLab.local has NOT been created"
    }


    Write-Host "Updating DNS Servers"

    # Fill the array with the DNS servers that are there

    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/cluster/name_servers"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    $servers=$response

    # Delete the DNS servers so we can add just one

    foreach($server in $servers){
        $Payload='[{"ipv4":"'+$server+'"}]'
        $APIParams = @{
            method="POST"
            Uri="https://$($IP):9440/PrismGateway/services/rest/v1/cluster/name_servers/remove_list"
            ContentType="application/json"
            Body=$Payload
            Header = $Header
        }
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    }

    # Get the AutoAD as correct DNS in

    $Payload='{"value":"'+$AutoAD+'"}'
    $APIParams = @{
        method="POST"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/cluster/name_servers"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)


    return "AutoAD added as authentication server and DNS server ($AutoAD)"
}

# Adding the Rolemapping from PE to AD
Function RoleMapPEtoAD{
    param(
        [string] $IP,
        [object] $Header 
    )


    Write-Host "Adding SSP Admins AD Group to Cluster Admin Role"

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
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/authconfig/directories/NTNXLAB/role_mappings?&entityType=GROUP&role=ROLE_CLUSTER_ADMIN"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    if ($response = "True"){
        return "SSP Admins have been added as the Cluster Admin Role"
    }else{
        return "SSP Admins have not been added as the CLuster Admin Role"
    }

}

# Add NTP servers
Function AddNTPServers{
    param(
        [string] $IP,
        [object] $Header
    )
    Write-Host "Adding NTP Servers"
    foreach ($ntp in (1,2,3)){
        if ($ntp -ne $null){
            $APIParams = @{
                method="POST"
                Body='[{"hostname":"'+$ntp+'.pool.ntp.org"}]'
                Uri="https://$($IP):9440/PrismGateway/services/rest/v1/cluster/ntp_servers/add_list"
                ContentType="application/json"
                Header = $Header
            } 
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
            if ($response = "True"){
                Write-Host "NTP Server $ntp.pool.ntp.org added"
                $Fail="No"
            }else{
                Write-Host "NTP Server $ntp.pool.ntp.org not added"
                $Fail="Yes"
            }
        }
    }
    if ($Fail -Match "No"){
        return "All NTP servers have been added."
    }else{
        return "Issues have risen during the adding of NTP Servers."
    }
}