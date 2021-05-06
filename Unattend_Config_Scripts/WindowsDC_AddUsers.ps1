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


if ( !(test-path $LogFolderPath)) {
    new-item -itemtype "directory" -path $LogFolderPath -name $LogFolderName -Force   
}

$failedUsers |ForEach-Object {"$($b).) $($_)"; $b++} | out-file -FilePath  $LogFolder\FailedUsers.log -Force -Verbose
$successUsers | ForEach-Object {"$($a).) $($_)"; $a++} |out-file -FilePath  $LogFolder\successUsers.log -Force -Verbose 


# Setup Runonce and Autologin to lauch the Add Groups and Users
Set-AutoLogon -DefaultUsername "ntnxlab\administrator" -DefaultPassword "nutanix/4u"
Set-Location -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
Set-ItemProperty -Path . -Name addDomainUsers -Value 'C:\WINDOWS\system32\WindowsPowerShell\v1.0\powershell.exe "c:\Config_Scripts\WindowsDC_httpServer.ps1"'
Restart-Computer