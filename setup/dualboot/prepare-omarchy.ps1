[CmdletBinding()]
param(
    [ValidateRange(1, 100000)][int]$OmarchyGB = 100,
    [switch]$KeepEncryption,
    [Alias('WhatIf')][switch]$DryRun
)
$ErrorActionPreference = 'Stop'

function Invoke-Step([string]$Description, [scriptblock]$Action) {
    Write-Host "==> $Description"
    if ($DryRun) { return }
    if ((Read-Host 'Apply this change? [y/N]') -match '^(y|yes)$') { & $Action }
}

$part = Get-Partition -DriveLetter C
$disk = Get-Disk -Number $part.DiskNumber
if ($disk.PartitionStyle -ne 'GPT') { throw 'The system disk must use GPT and boot in UEFI mode.' }

$requested = [long]$OmarchyGB * 1GB
if ([long]$disk.LargestFreeExtent -lt $requested) {
    # Existing free space elsewhere on disk cannot be combined with the shrink.
    $next = Get-Partition -DiskNumber $disk.Number | Where-Object Offset -gt $part.Offset |
        Sort-Object Offset | Select-Object -First 1
    $end = if ($next) { $next.Offset } else { $disk.Size }
    $adjacent = [math]::Max(0L, [long]$end - [long]$part.Offset - [long]$part.Size - 1MB)
    $target = [long]$part.Size - [math]::Max(0L, $requested - $adjacent)
    if ($target -lt (Get-PartitionSupportedSize -DriveLetter C).SizeMin) {
        throw 'Windows cannot make a large enough contiguous extent. See shrink/README.md.'
    }
    Invoke-Step "Shrink C: on disk $($disk.Number) to $([math]::Round($target / 1GB, 1)) GiB" {
        Resize-Partition -DriveLetter C -Size $target
    }
} else { Write-Host '==> The disk already has enough contiguous unallocated space.' }

Invoke-Step 'Disable Fast Startup while keeping full hibernation available' {
    powercfg /hibernate on
    if ($LASTEXITCODE -ne 0) { throw 'Could not enable hibernation.' }
    powercfg /hibernate /type full
    if ($LASTEXITCODE -ne 0) { throw 'Could not enable the full hibernation file.' }
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0
}
Invoke-Step 'Set the Windows hardware clock convention to UTC' {
    New-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name RealTimeIsUniversal -Value 1 -PropertyType DWord -Force | Out-Null
}
if (-not $KeepEncryption) {
    Invoke-Step 'Turn off BitLocker/Device Encryption on C: if active' {
        $volume = Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue
        if ($volume -and (Get-BitLockerVolume -MountPoint C:).VolumeStatus -eq 'FullyDecrypted') { return }
        manage-bde -off C:
        if ($LASTEXITCODE -ne 0) { throw 'Check encryption status in Windows Settings or with manage-bde -status C:.' }
    }
}
Write-Host 'Before installing, verify unallocated space in Disk Management and verify full decryption with manage-bde -status C:.'
