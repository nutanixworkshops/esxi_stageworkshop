<#
Installs Domain Services.
Creates Domain.

#>



$a=1;
$b=1;
$failedUsers = @()
$usersAlreadyExist =@()
$successUsers = @()
$VerbosePreference = "Continue"
$LogFolderPath = "c:\Config_Scripts\"
$LogFolderName = "Logs"

new-item -itemtype "directory" -path $LogFolderPath -name $LogFolderName -Force 

$plainpw = "nutanix/4u"
$securepw = ConvertTo-SecureString -AsPlainText $plainpw -Force

Install-WindowsFeature AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools

Import-Module ADDSDeployment

Install-ADDSForest -DomainName "ntnxlab.local" -DomainNetbiosName "NTNXLAB" -SafeModeAdministratorPassword $securepw -CreateDnsDelegation:$false -DomainMode "Win2012R2" -ForestMode "Win2012R2" -InstallDns:$true -Force:$true -NoRebootOnCompletion -DatabasePath "C:\Windows\NTDS" -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL"

# Setup Runonce and Autologin to lauch the Add Groups and Users
Set-AutoLogon -DefaultUsername "ntnxlab\administrator" -DefaultPassword "nutanix/4u"
Set-Location -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
Set-ItemProperty -Path . -Name addDomainUsers -Value 'C:\WINDOWS\system32\WindowsPowerShell\v1.0\powershell.exe "c:\Config_Scripts\WindowsDC_AddUsers.ps1"'
#Set-ItemProperty -Path . -Name addDomainUsers -Value "c:\Config_Scripts\WindowsDC_AddUsers.ps1"

# Change the Local IP address to .41 as it should for HPOC
$old_ip=(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias Ethernet0).IPaddress
$new_ip=$old_ip.Substring(0,$old_ip.length-2)+"41"
$gateway=$old_ip.Substring(0,$old_ip.length-2)+"1"
Get-NetAdapter | ? {$_.Status -eq "up"} |New-NetIPAddress -AddressFamily IPv4 -IPAddress $new_ip -PrefixLength 25 -DefaultGateway $gateway
# Configure the DNS client server IP addresses
Get-NetAdapter | ? {$_.Status -eq "up"} | Set-DnsClientServerAddress -ServerAddresses "8.8.8.8,8.8.4.4"

Restart-Computer

#start-sleep -s 180


<#
$Groups = Import-csv c:\Config_Scripts\WindowsDC_add-groups.csv

$password = "nutanix/4u" | ConvertTo-SecureString -asPlainText -Force
$username = "ntnxlab\administrator" 
$credential = New-Object System.Management.Automation.PSCredential($username,$password)

$plainpw = "nutanix/4u"
$securepw =  $plainpw | ConvertTo-SecureString -AsPlainText -Force

# Create Groups and Users
Import-module activedirectory



ForEach($UserGroup in $Groups)
{
$Group = $UserGroup.group
NEW-ADGroup -name $Group -groupscope Global -Credential $credential
$Users = Import-csv c:\Config_Scripts\WindowsDC_add-users_$Group.csv
    ForEach($User in $Users)
    {
    $User.FirstName = $User.FirstName.substring(0,1).toupper()+$User.FirstName.substring(1).tolower()
    $FullName = $User.FirstName
    $Sam = $User.FirstName 
    $dnsroot = '@' + (Get-ADDomain).dnsroot
    $SAM = $sam.tolower()
    $UPN = $SAM + "$dnsroot"
    $OU = "CN=users, DC=NTNXLAB, DC=LOCAL"
    $email = $Sam + "$dnsroot"
    $password = $user.password
        try {
        if (!(get-aduser -Filter {samaccountname -eq "$SAM"})){
        New-ADUser -Name $FullName -AccountPassword (ConvertTo-SecureString $password -AsPlainText -force) -GivenName $User.FirstName  -Path $OU -SamAccountName $SAM -Surname $User.LastName  -UserPrincipalName $UPN -EmailAddress $Email -Enabled $TRUE -Credential $credential
        Add-ADGroupMember -Identity $Group -Members $Sam -Credential $credential
        Write-Verbose "[PASS] Created $FullName"
        $successUsers += $FullName 
        }
        }
        catch {
        Write-Warning "[ERROR]Can't create user [$($FullName)] : $_"
        $failedUsers += $FullName
        }
    }
}

#>
if ( !(test-path $LogFolderPath)) {
    new-item -itemtype "directory" -path $LogFolderPath -name $LogFolderName -Force   
}

$failedUsers |ForEach-Object {"$($b).) $($_)"; $b++} | out-file -FilePath  $LogFolder\FailedUsers.log -Force -Verbose
$successUsers | ForEach-Object {"$($a).) $($_)"; $a++} |out-file -FilePath  $LogFolder\successUsers.log -Force -Verbose 
