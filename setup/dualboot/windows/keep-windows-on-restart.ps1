# Runs as SYSTEM on System event 1074 (a shutdown or restart was started).
# A restart started inside Windows (Start menu, Windows Update, installers) comes back to Windows,
# even though power-on goes to Omarchy. A switch via the 'omarchy' command is left alone.
$dir = $PSScriptRoot
$log = Join-Path $dir 'restart-guard.log'
$ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1074 } -MaxEvents 1 -ErrorAction SilentlyContinue
if (-not $ev) { exit 0 }
$type = "$($ev.Properties[4].Value) $($ev.Message)"
if ($type -notmatch '(?i)restart|neustart|reinicio|red.marr') { exit 0 }      # power off: leave the default (Omarchy)
bcdedit /set '{fwbootmgr}' bootsequence '{bootmgr}' | Out-Null
"$(Get-Date -f s) Windows restart -> next boot Windows ($($ev.Properties[0].Value))" | Add-Content $log
