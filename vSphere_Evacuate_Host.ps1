<#
    .SYNOPSIS
    Evacuates VMs from a vSphere host

    .DESCRIPTION
    Attempts to migrate all VMs from the chosen host to other hosts in the cluster (basically what DRS does when you put a host in to maintenance mode, but on vSphere Standard).
    Migrations are attempted one at a time to avoid conflicts / resource issues.
    VMs are migrated in order of allocated memory size descending.
    Destination host is chosen by filtering hosts based on having enough memory, then selecting the host with the lowest CPU usage.
    Requires the VMware PowerCLI module

    .PARAMETER vCenter
    The vCenter host address

    .PARAMETER HostToEvacuate
    The vSphere host to evacuate

    .LINK
    https://github.com/mattlinfield/vSphere-Powershell-Scripts

#>

#Requires -Modules VMware.PowerCLI
#Requires -Version 3.0

param (
    [Parameter(Mandatory=$true)]
    [string]$vCenter,

    [Parameter(Mandatory=$true)]
    [string]$HostToEvacuate
)


# connect vCentre
Connect-VIServer -Server $VCenter -ErrorAction Stop

# get source host
$SourceHost = Get-VMHost | Where-Object {$_.Name -match $HostToEvacuate}
if ($SourceHost -is [array]) {
    throw 'Got more than one source host - ensure name is specific enough'
}
if (-not $SourceHost) {
    throw 'Couldn''t find source host'
}

$MigrationAttempts = @{}

do {

    # throttle
    $HostVMs = $SourceHost | Get-VM
    do {
        $RunningVMotions = Get-Task | Where-Object {$_.Name -eq 'RelocateVM_Task' -and $_.ObjectId -in $HostVMs.Id -and ($_.State -eq 'Running' -or $_.PercentComplete -eq 0)}
        if ($RunningVMotions.Count -ge 2) {
            Start-Sleep -Seconds 10
        }
    } until ($RunningVMotions.Count -lt 2)

    # get next VM and filter out VMs that have had 3 attempts already
    $TooManyAttempts = $MigrationAttempts.Keys | Where-Object {$MigrationAttempts[$_] -gt 2}
    $SourceVM = $SourceHost | Get-VM | Where-Object {$_.Id -notin $RunningVMotions.ObjectId -and $_.Id -notin $TooManyAttempts} | Sort-Object -Property MemoryMB -Descending | Select-Object -First 1

    # get elligible hosts
    $EligibleHosts = $Sourcehost.Parent | Get-VMHost | Where-Object {$_.Name -ne $SourceHost.Name -and (($_.MemoryTotalGB) - $_.MemoryUsageGB) -gt ($SourceVM.MemoryGB)}
    if (-not $EligibleHosts) {
        throw "Couldn't migrate $SourceVM - no eligible hosts with enough free memory found in the cluster $($SourceHost.Parent)"
    }
    
    # start vmotion
    $MigrationAttempts[$SourceVM.Id] += 1
    $DestHost =  $EligibleHosts | Sort-Object -Property {$_.CpuTotalMhz - $_.CpuUsageMhz} -Descending | Select-Object -First 1
    Write-Output "Moving $SourceVM to $DestHost"
    $SourceVM | Move-VM -Destination $DestHost -VMotionPriority Standard -RunAsync | Out-Null
    Start-Sleep -Seconds 2

} until (-not $SourceVM)

Write-Output 'Finished attempting migrations'
$RunningVMotions = Get-Task | Where-Object {$_.Name -eq 'RelocateVM_Task' -and ($_.State -eq 'Running' -or $_.PercentComplete -eq 0)}
$VMsNotMigrated = $SourceHost | Get-VM | Where-Object {$_.Id -notin $RunningVMotions.ObjectId}
if ($VMsNotMigrated) {
    Write-Output 'It appears some VMs may not have migrated successfully. Please check the host.'
}