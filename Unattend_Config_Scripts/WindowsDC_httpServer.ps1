<#
    httpServer.ps1
    
    Script is designed to run a simple HTTP server that can be
    deployed after the AD Setup Scripts so that completion of
    the task can be confirmed using a RestAPI by checking for
    a status 200 on the assigned IP and port.

    The port is assigned in the $port variable and the IP address
    is determined by looking up the IPv4 address of the interface
    named "Ethernet"

    By default it returns plain text "AD is running", but can be
    modified to return a page with more details.

    The firewall is disabled since it is a lab machine but can be
    altered to remin on and just open the correct port.

    Last Updated: Jan-21-2020
    Author: John Walker
#>

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

if (-not [System.Net.HttpListener]::IsSupported) {
    "HTTP Listener is not supported"
    exit 1
}

$port = "8000"

$listener = New-Object System.Net.HttpListener

$ip = Get-NetIpaddress -InterfaceAlias Ethernet0 -AddressFamily IPv4 | select -ExpandProperty IPAddress 

$url = -join ("http://",$ip,":",$port,"/")

$listener.Prefixes.Add($url)

try {
    $listener.Start()
} catch {
    "Unable to start listener"
    exit 1
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $response = $context.Response
    $response.ContentType = "text/plain"
    $content = [System.Text.Encoding]::UTF8.GetBytes("AD Is Running")
    $response.OutputStream.Write($content,0,$content.Length)
    $response.Close()
}

Write-Host "AD Is Running, you may close this PS Console"

# Sync Clock/Time
w32tm /config /manualpeerlist:216.239.35.0,0x8 /syncfromflags:manual /reliable:yes /update

$listener.Stop()
