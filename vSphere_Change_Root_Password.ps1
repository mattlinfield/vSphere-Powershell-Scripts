<#
    .SYNOPSIS
    Updates the root password on multiple VMhosts

    .PARAMETER vCenter
    The vCenter host address

    .PARAMETER HostsToUpdate
    The vSphere host(s) on which to update the root password (have to match exactly, but not case sensitive)

    .PARAMETER Username
    Username to update (defaults to root)

    .PARAMETER CurrentPassword
    The current password

    .PARAMETER NewPassword
    The new password to change it to

    .LINK
    https://github.com/mattlinfield/vSphere-Powershell-Scripts

#>

#Requires -Modules VMware.PowerCLI, Posh-SSH
#Requires -Version 5.0

param (
    [Parameter(Mandatory=$true)]
    [string]$vCenter,

    [Parameter(Mandatory=$true)]
    [string[]]$HostsToUpdate,

    [string]$Username = 'root',

    [Parameter(Mandatory=$true)]
    [securestring]$CurrentPassword,

    [Parameter(Mandatory=$true)]
    [securestring]$NewPassword
)

# connect vCentre
Connect-VIServer -Server $VCenter -ErrorAction Stop

# get hosts
$HostsToUpdate = $HostsToUpdate | ForEach-Object {$_.ToLower()}
$VMHosts = Get-VMHost | Where-Object {$_.Name.ToLower() -in $HostsToUpdate}
if (-not $VMHosts) {
    throw 'Error getting hosts'
}

# get confirmation before continuing
Write-Output "Updating password for user $Username on the following hosts:"
Write-Output $VMHosts.Name
$Continue = Read-Host -Prompt 'Are you sure you want to continue? (y/n)'
if ($Continue -notmatch 'y') {
    exit
}

# connect via SSH and update password
$CurrentCreds = New-Object System.Management.Automation.PSCredential ($Username, $CurrentPassword) -ErrorAction Stop
try {
    $VMHosts | Get-VMHostService | Where-Object {$_.Label -eq 'SSH'} | Start-VMHostService -ErrorAction Stop
    $Sessions = New-SSHSession -ComputerName $VMHosts.name -Credential $CurrentCreds -ErrorAction Stop
    if (-not $Sessions) {
        throw 'Failed to get SSH sessions'
    }
    Invoke-SSHCommand -Command "echo $($NewPassword | ConvertFrom-SecureString -AsPlainText)| passwd $Username -s" -SSHSession $Sessions | Format-Table
}
catch {
    throw $_
}
finally {
    $Sessions | Remove-SSHSession -ErrorAction SilentlyContinue
    $VMHosts | Get-VMHostService | Where-Object {$_.Label -eq 'SSH'} | Stop-VMHostService -Confirm:$false
}