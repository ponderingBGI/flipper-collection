<#
  One-time, as admin. Sets up switching from Windows to Omarchy:
  - scripts in C:\Program Files\DualBoot (admin-only, because they run elevated)
  - task DualBoot-RebootToOmarchy: the 'omarchy' command, Start menu shortcut and Ctrl+Alt+O ask before switching
  - task DualBoot-KeepWindowsOnRestart: restarts started in Windows come back to Windows
  - Start menu + desktop shortcut "Omarchy" with the Ctrl+Alt+O hotkey
#>
param([Alias('WhatIf')][switch]$DryRun, [switch]$Yes)
$From = $PSScriptRoot
Write-Host '==> Install Windows switch tasks, scripts, and shortcuts'
if ($DryRun) { return }
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an administrator Windows PowerShell.'
}
if (-not $Yes -and (Read-Host 'Install the dual-boot tasks and shortcuts? [y/N]') -notmatch '^(y|yes)$') { return }
$ErrorActionPreference = 'Stop'
$pf = Join-Path $env:ProgramFiles 'DualBoot'
New-Item -ItemType Directory -Force $pf | Out-Null
foreach ($f in 'reboot-to-omarchy.ps1', 'keep-windows-on-restart.ps1', 'switch-to-omarchy.ps1') { Copy-Item (Join-Path $From $f) $pf -Force }
$ico = Join-Path $From 'omarchy.ico'; if (Test-Path $ico) { Copy-Item $ico $pf -Force }

$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$db = Join-Path $HOME '.config\dualboot'
New-Item -ItemType Directory -Force -Path $db | Out-Null
Copy-Item (Join-Path $From 'DualBoot.ps1') $db -Force
Register-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy' -Force `
  -Action (New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\reboot-to-omarchy.ps1`"") `
  -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest) `
  -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) | Out-Null

$trigger = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler | New-CimInstance -ClientOnly
$trigger.Enabled = $true
$trigger.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''User32''] and EventID=1074]]</Select></Query></QueryList>'
Register-ScheduledTask -TaskName 'DualBoot-KeepWindowsOnRestart' -Force -Trigger $trigger `
  -Action (New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\keep-windows-on-restart.ps1`"") `
  -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest) `
  -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1)) | Out-Null

# shortcuts with a global hotkey (Windows honours hotkeys on Start menu and desktop shortcuts)
$sh = New-Object -ComObject WScript.Shell
$targets = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Omarchy.lnk")
$desk = [Environment]::GetFolderPath('CommonDesktopDirectory'); if ($desk) { $targets += Join-Path $desk 'Omarchy.lnk' }
foreach ($t in $targets) {
  $l = $sh.CreateShortcut($t)
  $l.TargetPath = $ps
  $l.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$pf\switch-to-omarchy.ps1`""
  $l.Description = 'Restart into Omarchy'
  $l.IconLocation = if (Test-Path "$pf\omarchy.ico") { "$pf\omarchy.ico,0" } else { "$env:SystemRoot\System32\shell32.dll,27" }
  if ($t -like '*Start Menu*') { $l.Hotkey = 'CTRL+ALT+O' }
  $l.WindowStyle = 1
  $l.Save()
}
'installed: tasks DualBoot-RebootToOmarchy, DualBoot-KeepWindowsOnRestart; shortcut Omarchy (Ctrl+Alt+O)'
