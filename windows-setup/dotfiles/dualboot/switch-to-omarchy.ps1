# Shortcut / hotkey target: asks once, then hands off to the elevated task (no admin prompt).
Add-Type -AssemblyName PresentationFramework
$r = [System.Windows.MessageBox]::Show(
  "Restart into Omarchy now?`n`nOpen apps get a few seconds to save. Next power-on goes to Omarchy anyway; restarts from Windows stay in Windows.",
  'Switch to Omarchy', 'OKCancel', 'Question', 'OK')
if ($r -eq 'OK') { Start-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy' }
