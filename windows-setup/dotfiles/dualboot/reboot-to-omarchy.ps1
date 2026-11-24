# Runs elevated from the DualBoot-RebootToOmarchy task (installed under C:\Program Files\DualBoot, admin-only).
# Sets a one-time boot into Limine/Omarchy, then HIBERNATES, so Windows resumes exactly where you left it
# the next time you boot Windows (Limine menu, or 'windows' / SUPER+ALT+W on Omarchy).
# While Windows is hibernated, Linux must not write to C: (Omarchy mounts it read-only).
# External drives (the T7) are flushed and dismounted first so Linux can use them safely;
# Windows remounts them by itself after resuming.
$dir = 'C:\ProgramData\DualBoot'; New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir 'switch.log'
$fw = bcdedit /enum firmware | Out-String
$entry = $null
foreach ($block in ($fw -split '(\r?\n){2,}')) {
  if ($block -match '(?im)^description\s+.*(Omarchy|Limine|Linux)' -and $block -match '(?im)^identifier\s+(\{[0-9a-f-]+\})') { $entry = $Matches[1]; break }
}
if (-not $entry) { "$(Get-Date -f s) no Omarchy/Limine firmware entry:`n$fw" | Add-Content $log; exit 1 }

# hibernation must be available (full hiberfile); otherwise fall back to a normal restart
$canHibernate = (powercfg /a | Out-String) -match '(?im)^\s*Hibernate\s*$'
(Get-Date).ToUniversalTime().ToString('o') | Set-Content (Join-Path $dir 'switching')   # restart guard: this is a switch
bcdedit /set '{fwbootmgr}' bootsequence $entry | Out-Null

# flush + dismount volumes on USB disks (T7 etc.)
$usb = Get-Disk | Where-Object BusType -eq 'USB' | ForEach-Object { Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue } | Where-Object DriveLetter
foreach ($p in $usb) {
  $dl = "$($p.DriveLetter):"
  $out = (fsutil volume dismount $dl 2>&1 | Out-String).Trim()
  "$(Get-Date -f s) dismount $dl : $out" | Add-Content $log
}

if ($canHibernate) {
  "$(Get-Date -f s) switching to $entry (hibernate)" | Add-Content $log
  Start-Sleep 2
  shutdown.exe /h
} else {
  "$(Get-Date -f s) switching to $entry (restart, hibernation not available)" | Add-Content $log
  shutdown.exe /r /t 5 /c 'Switching to Omarchy'
}
