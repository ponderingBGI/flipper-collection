# Runs elevated from the DualBoot-RebootToOmarchy task (installed under C:\Program Files\DualBoot, admin-only).
# One-time boot into Limine/Omarchy, then restart.
$dir = 'C:\ProgramData\DualBoot'; New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir 'switch.log'
$fw = bcdedit /enum firmware | Out-String
$entry = $null
foreach ($block in ($fw -split '(\r?\n){2,}')) {
  if ($block -match '(?im)^description\s+.*(Omarchy|Limine|Linux)' -and $block -match '(?im)^identifier\s+(\{[0-9a-f-]+\})') { $entry = $Matches[1]; break }
}
if (-not $entry) { "$(Get-Date -f s) no Omarchy/Limine firmware entry:`n$fw" | Add-Content $log; exit 1 }
# tell the restart guard this restart is a switch, not a normal Windows restart
(Get-Date).ToUniversalTime().ToString('o') | Set-Content (Join-Path $dir 'switching')
bcdedit /set '{fwbootmgr}' bootsequence $entry | Out-Null
"$(Get-Date -f s) switching to $entry" | Add-Content $log
shutdown.exe /r /t 5 /c 'Switching to Omarchy'
