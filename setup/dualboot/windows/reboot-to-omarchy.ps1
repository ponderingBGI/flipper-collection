# Runs elevated from the DualBoot-RebootToOmarchy task (installed under C:\Program Files\DualBoot, admin-only).
# Sets a one-time boot into Limine/Omarchy, then HIBERNATES, so Windows resumes exactly where you left it
# the next time you boot Windows (Limine menu, or 'windows' / SUPER+ALT+W on Omarchy).
# While Windows is hibernated, Linux must not write to C: (Omarchy mounts it read-only).
# External USB drives are flushed and dismounted first, so Linux can use them.
$dir = $PSScriptRoot
$log = Join-Path $dir 'switch.log'
$fw = bcdedit /enum firmware | Out-String
$entries = @(
foreach ($block in ($fw -split '(\r?\n){2,}')) {
  if ($block -match '(?im)^description\s+.*(Omarchy|Limine)' -and $block -match '(?im)^identifier\s+(\{[0-9a-f-]+\})') { $Matches[1] }
}
)
if ($entries.Count -ne 1) { "$(Get-Date -f s) expected one Omarchy/Limine firmware entry:`n$fw" | Add-Content $log; exit 1 }

$entry = $entries[0]
# The switch must preserve the Windows session.
# Hibernation must be enabled (powercfg /h on). Don't rely on reading hiberfil.sys: it's a locked system file.
$hibOn = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction SilentlyContinue).HibernateEnabled -eq 1
$avail = (powercfg /a | Out-String) -split '(?m)^The following sleep states are not available' | Select-Object -First 1
if (-not $hibOn -or $avail -notmatch '(?m)^\s*Hibernate\s*$') { "$(Get-Date -f s) hibernation not available (HibernateEnabled=$hibOn)" | Add-Content $log; exit 1 }
bcdedit /set '{fwbootmgr}' bootsequence $entry | Out-Null
if ($LASTEXITCODE -ne 0) { "$(Get-Date -f s) could not set BootNext" | Add-Content $log; exit 1 }
# External USB drives (e.g. a shared data SSD): flush and dismount them, so Linux can use them safely
# while Windows is hibernated. Windows mounts them again by itself after resuming.
$usb = Get-Disk | Where-Object BusType -eq 'USB' | ForEach-Object { Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue } | Where-Object DriveLetter
foreach ($p in $usb) { "$(Get-Date -f s) dismount $($p.DriveLetter): $((fsutil volume dismount "$($p.DriveLetter):" 2>&1 | Out-String).Trim())" | Add-Content $log }
"$(Get-Date -f s) switching to $entry (hibernate)" | Add-Content $log
shutdown.exe /h
if ($LASTEXITCODE -ne 0) {
  bcdedit /deletevalue '{fwbootmgr}' bootsequence | Out-Null
  "$(Get-Date -f s) hibernation failed" | Add-Content $log
  exit 1
}
