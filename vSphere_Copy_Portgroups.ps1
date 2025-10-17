<#
    .SYNOPSIS
    Copies portgroups from one vSphere host to another

    .DESCRIPTION
    Copies portgroups from the SourceHost to the DestinationHost (and vSwitches if they don't already exist).
    It will attempt to add NICs with matching names to the switch as well.
    Requires the VMware PowerCLI module

    .PARAMETER vCenter
    The vCenter host address

    .PARAMETER SourceHost
    The vSphere host to copy switches / portgroups from

    .PARAMETER DestinationHost
    The vSphere host to copy switches / portgroups to

    .LINK
    Online version: http://www.fabrikam.com/add-extension.html

#>

#Requires -Modules VMware.PowerCLI

param (
    [Parameter(Mandatory=$true)]
    [string]$vCenter,

    [Parameter(Mandatory=$true)]
    [string]$SourceHost,

    [Parameter(Mandatory=$true)]
    [string]$DestinationHost
)

# connect vCentre
Connect-VIServer -Server $VCenter -ErrorAction Stop

# get source networks
$Switches = Get-VirtualSwitch -VMHost $SourceHost -ErrorAction Stop
$PortGroups = Get-VirtualPortGroup -VMHost $SourceHost -ErrorAction Stop | Where-Object {$_.VLanId}
if (-not $Switches -or -not $PortGroups) {
    throw 'Error getting source networks'
}
Write-Output "Got $($Switches.count) vSwitches and $($PortGroups.count) portgroups"

foreach ($Switch in $Switches) {

    # add NICs to vSwitches
    try {
        New-VirtualSwitch -VMHost $DestinationHost -Name $Switch.Name -Nic $Switch.Nic -ErrorAction Stop | Out-Null
        Write-Output "Created $($Switch.Name)"
    }
    catch {
        Get-VirtualSwitch -VMHost $DestinationHost -Name $Switch.Name | Set-VirtualSwitch -Nic $Switch.Nic -Confirm:$false | Out-Null
        Write-Output "Updated $($Switch.Name)"
    }

    # add port groups
    foreach ($PortGroup in ($PortGroups | Where-Object {$_.VirtualSwitch.Name -eq $Switch.Name})) {
        Get-VirtualSwitch -VMHost $DestinationHost -Name $Switch.Name | New-VirtualPortGroup -Name $PortGroup.Name -VLanId $PortGroup.VLanId
        Write-Output "Added portgroup $($PortGroup.Name) to $($Switch.Name) "   
    }

}

#disconnect vCentre
Disconnect-VIServer -Server $VCenter -Force -Confirm:$false