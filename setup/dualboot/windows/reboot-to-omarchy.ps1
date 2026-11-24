# Runs elevated from the DualBoot-RebootToOmarchy task (installed under C:\Program Files\DualBoot, admin-only).
# Sets a one-time boot into Limine/Omarchy, then HIBERNATES, so Windows resumes exactly where you left it
# the next time you boot Windows (Limine menu, or 'windows' / SUPER+ALT+W on Omarchy).
# While Windows is hibernated, Linux must not write to C: (Omarchy mounts it read-only).
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
$available = (Get-Item (Join-Path $env:SystemDrive 'hiberfil.sys') -Force -ErrorAction SilentlyContinue)
if (-not $available) { "$(Get-Date -f s) hibernation file missing" | Add-Content $log; exit 1 }
bcdedit /set '{fwbootmgr}' bootsequence $entry | Out-Null
if ($LASTEXITCODE -ne 0) { "$(Get-Date -f s) could not set BootNext" | Add-Content $log; exit 1 }
"$(Get-Date -f s) switching to $entry (hibernate)" | Add-Content $log
shutdown.exe /h
if ($LASTEXITCODE -ne 0) {
  bcdedit /deletevalue '{fwbootmgr}' bootsequence | Out-Null
  "$(Get-Date -f s) hibernation failed" | Add-Content $log
  exit 1
}
