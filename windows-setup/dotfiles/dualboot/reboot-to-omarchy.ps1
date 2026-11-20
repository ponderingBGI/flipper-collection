# Runs elevated from the DualBoot-RebootToOmarchy task: one-time boot into Limine/Omarchy, then restart.
$log = Join-Path $env:TEMP 'reboot-to-omarchy.log'
$fw = bcdedit /enum firmware | Out-String
$entry = $null
foreach ($block in ($fw -split '(\r?\n){2,}')) {
    if ($block -match '(?im)^description\s+.*(Omarchy|Limine|Linux)' -and $block -match '(?im)^identifier\s+(\{[0-9a-f-]+\})') { $entry = $Matches[1]; break }
}
if (-not $entry) { "No Omarchy/Limine boot entry found in firmware:`n$fw" | Out-File $log; exit 1 }
bcdedit /set '{fwbootmgr}' bootsequence $entry | Out-File $log
shutdown.exe /r /t 0
