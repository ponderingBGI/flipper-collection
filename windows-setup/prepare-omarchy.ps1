<#
.SYNOPSIS
    Gets this PC ready for an Omarchy dual boot. Run once, as admin.

.DESCRIPTION
    1. Turns off Fast Startup, so Windows really shuts down and Omarchy can safely mount C:.
    2. Makes Windows keep the hardware clock in UTC like Linux does (otherwise the clock jumps when switching).
    3. Shrinks C: to leave unallocated space for Omarchy's "Free space install".
    4. Turns off BitLocker / Device encryption on C: (Omarchy's free-space install refuses to run otherwise).
       Omarchy encrypts its own partition anyway.
#>
param([int]$OmarchyGB = 100, [switch]$KeepEncryption, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
function Do-It($what, [scriptblock]$action) { if ($DryRun) { Write-Host "[dry] $what" } else { Write-Host "==> $what"; & $action } }

Do-It 'Fast Startup off (powercfg /h off)' { powercfg /h off }
Do-It 'Hardware clock in UTC' {
    New-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name RealTimeIsUniversal -Value 1 -PropertyType DWord -Force | Out-Null
}

$part = Get-Partition -DriveLetter C
$disk = Get-Disk -Number $part.DiskNumber
$unallocated = $disk.Size - (Get-Partition -DiskNumber $disk.Number | Measure-Object Size -Sum).Sum
if ($unallocated -ge ($OmarchyGB - 1) * 1GB) {
    Write-Host "    already $([math]::Round($unallocated/1GB)) GB unallocated - not shrinking"
} else {
    $target = $part.Size - $OmarchyGB * 1GB
    $min = (Get-PartitionSupportedSize -DriveLetter C).SizeMin
    if ($target -lt $min) {
        Write-Warning ("Windows can only shrink C: to {0:N0} GB right now (unmovable files such as the paging file). " +
                       "Turn off virtual memory, restart, run this again, then turn it back on.") -f ($min / 1GB)
    } else {
        Do-It "Shrink C: by $OmarchyGB GB" { Resize-Partition -DriveLetter C -Size $target }
    }
}

if (-not $KeepEncryption) {
    $bl = Get-BitLockerVolume -MountPoint C: -ErrorAction SilentlyContinue
    if ($bl -and $bl.VolumeStatus -ne 'FullyDecrypted') {
        Do-It 'Turn off device encryption on C: (runs in the background, check with: manage-bde -status C:)' { manage-bde -off C: | Out-Null }
    } else { Write-Host '    C: is not encrypted' }
}
Write-Host "`nNext: wait until 'manage-bde -status C:' says Fully Decrypted, then boot the Omarchy USB."
