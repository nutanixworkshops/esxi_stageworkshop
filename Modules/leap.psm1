# Specific Leap functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testleap{
    param(
        [string] $text
    )
    write-host "You reached module leap_mod.psm1"
    return $text
}
