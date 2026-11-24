# Shortcut / hotkey target: asks once, then hands off to the elevated task (no admin prompt).
Add-Type -AssemblyName PresentationFramework
$r = [System.Windows.MessageBox]::Show(
  "Switch to Omarchy?`n`nWindows hibernates: open apps stay exactly as they are, and you pick up right here the next time you boot Windows.`n`nSave your work and eject any shared USB drives before switching. If hibernation is unavailable the switch stops.",
  'Switch to Omarchy', 'OKCancel', 'Question', 'Cancel')
if ($r -eq 'OK') { Start-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy' }
