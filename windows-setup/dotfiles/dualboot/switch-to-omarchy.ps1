# Shortcut / hotkey target: asks once, then hands off to the elevated task (no admin prompt).
Add-Type -AssemblyName PresentationFramework
$r = [System.Windows.MessageBox]::Show(
  "Switch to Omarchy?`n`nWindows hibernates: open apps stay exactly as they are, and you pick up right here the next time you boot Windows.`n`nThe T7 is safely ejected first so Omarchy can use it.",
  'Switch to Omarchy', 'OKCancel', 'Question', 'OK')
if ($r -eq 'OK') { Start-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy' }
