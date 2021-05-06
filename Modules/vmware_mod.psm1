# Specific VMware functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testvmware{
    param(
        [string] $text
    )
    write-host "You reached module vmware_mod.psm1"
    return $text
}

# Connect to the vCenter of the environment
Function ConnectVMware{
    param(
        [string] $vcenter,
        [string] $password
    )
    try{
        connect-viserver $($vcenter) -User administrator@vsphere.local -Password $($password) | Out-Null
        return "Connected to vCenter $($vcenter)"
    }catch{
        return "Connection to vCenter $($vcenter) failed.."
    }
}

    # Enable DRS on the vCenter

Function EnableDRSDisableAdmissionContol{
    param(
        [string] $vcenter,
        [string] $password
    )
    $vm_cluster_name=(get-cluster| select-object $_.name).Name
    try{
        Set-Cluster -Cluster $vm_cluster_name -DRSEnabled:$true -HAAdmissionControlEnabled:$false -Confirm:$false | Out-Null
        return "DRS has been enabled and Adminission Control has been disabled ($vm_cluster_name)."
    }catch{
        return "DRS has not been enabled and Adminission Control is still enabled ($vm_cluster_name)."
    }
}


# Create a new Portgroup called Secondary with the correct VLAN
Function CreateSecondaryNetwork{
    param(
        [string] $vm_cluster_name,
        [string] $vlan
    )

    $vmhosts = Get-Cluster $vm_cluster_name | Get-VMhost

    ForEach ($vmhost in $vmhosts){
        Try{
            Get-VirtualSwitch -VMhost $vmhost -Name "vSwitch0" | New-VirtualPortGroup -Name 'Secondary' -VlanId $vlan | Out-Null
            $Fail="No"
            
        }catch{
            $Fail="Yes"
        }
    }
    if ($Fail -Match "No"){
        return "Secondary Network has been created"
    }else{
        return "Secondary Network has not been created. Maybe it already existed?"
    }
    
}


# Create a ContentLibray and copy the needed images to it
Function UploadImage{
    param(
        [string] $image,
        [string] $nfs_host
    )

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
    return "Uploaded $image_name as $image_short in the deploy ContentLibrary"
}

Function DeployAutoAD{
    param(
        [string] $AutoAD,
        [string] $vm_cluster_name
    )
    $vmhosts = Get-Cluster $vm_cluster_name | Get-VMhost
    $ESXi_Host=$vmhosts[0]
    # Deploy an AutoAD OVA. DRS will take care of the rest.

    Write-Host "Creating AutoAD VM"
    Get-ContentLibraryitem -name 'AutoAD_Sysprep' | new-vm -Name AutoAD -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null

    # Set the network to VM-Network before starting the VM

    get-vm 'AutoAD' | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'VM Network' -Confirm:$false | Out-Null

    Start-VM -VM 'AutoAD' | Out-Null
    Write-Host "AutoAD VM has been created and started."

    Write-Host "Waiting till AutoAD is ready."
    $counter=1
    $url="http://"+$AutoAD+":8000"
    while ($true){
        try{
            $response=invoke-Webrequest -Uri $url -TimeOut 15
            Break
        }catch{
            Write-Host "AutoAD still not ready. Sleeping 60 seconds before retrying...($counter/45)"
            Start-Sleep 60
            if ($counter -eq 45){
                Write-Host "We waited for 45 minutes and the AutoAD didn't got ready in time... Exiting script.."
                exit 1
            }
            $counter++
        }
    }
    return "AutoAD is ready for being used. Progressing..."
}
# Deploy the default VMs these are always needed
Function DeployVMTemplate{
    param(
        [string] $vm_cluster_name,
        [string] $templ_name
    )

    $vmhosts = Get-Cluster $vm_cluster_name | Get-VMhost
    $ESXi_Host=$vmhosts[0]

    Get-ContentLibraryitem -name $templ_name | new-vm -Name "$templ_name-templ" -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null
    get-vm "$templ_name-templ" | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'Secondary' -Confirm:$false | Out-Null
    Get-VM -Name "$templ_name-templ" | Set-VM -ToTemplate -Confirm:$false | Out-Null

    return "Template for $templ_name has been created"
}

Function DeployWinToolsVM{
    param(
        [string] $vm_cluster_name
    )

    $vmhosts = Get-Cluster $vm_cluster_name | Get-VMhost
    $ESXi_Host=$vmhosts[0]

    # Deploy the Windows Tools VM and create the templates for Centos and Windows
    
    Write-Host "Deploying the WinTools VM via a Content Library in the Image Datastore"
    Get-ContentLibraryitem -name 'WinTools-AHV' | new-vm -Name 'WinTools-VM' -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null
    get-vm 'WinTools-VM' | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'Secondary' -Confirm:$false | Out-Null

    return "WindowsTools VM has been created"
}

Function DeployEraVM{
    param(
        [string] $vm_cluster_name
    )

    $vmhosts = Get-Cluster $vm_cluster_name | Get-VMhost
    $ESXi_Host=$vmhosts[0]

    # Deploy the Windows Tools VM and create the templates for Centos and Windows
    
    Write-Host "Deploying the Era VM via a Content Library in the Image Datastore"
    Get-ContentLibraryitem -name 'ERA-Server-build-2.1.1.2' | new-vm -Name 'Era' -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null
    get-vm 'Era' | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'VM Network' -Confirm:$false | Out-Null

    Start-VM -VM 'Era' | Out-Null
    return "Era has been created and started."
}

# Close the VMware connection
Function DisconnectvCenter {
    try{
        disconnect-viserver * -Confirm:$false
        return "Disconnected from vCenter"
    }catch{
        return "Still connections to vCenter are active. Please close them yourself."
    }

}
