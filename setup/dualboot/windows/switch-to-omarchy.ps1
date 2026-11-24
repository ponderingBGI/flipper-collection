# Shortcut / hotkey target: hands off to the elevated task (no admin prompt).
# Asks once by default; installed with -NoConfirm (flag file below) it switches straight away.
$noConfirm = Test-Path (Join-Path $env:ProgramData 'DualBoot\no-confirm')
if (-not $noConfirm) {
  Add-Type -AssemblyName PresentationFramework
  $r = [System.Windows.MessageBox]::Show(
    "Switch to Omarchy?`n`nWindows hibernates: open apps stay exactly as they are, and you pick up right here the next time you boot Windows.`n`nExternal USB drives are safely ejected first, so Omarchy can use them. If hibernation is unavailable the switch stops.",
    'Switch to Omarchy', 'OKCancel', 'Question', 'Cancel')
  if ($r -ne 'OK') { return }
}
Start-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy'
