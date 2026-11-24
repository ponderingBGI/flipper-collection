# omarchy: restart straight into Omarchy (asks first). Ctrl+Alt+O and the Start menu "Omarchy" shortcut do the same.
# Setup (once, admin): setup\dualboot\windows\install-dualboot.ps1
function Restart-ToOmarchy {
    if (-not (Get-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy' -ErrorAction SilentlyContinue)) {
        Write-Host 'Not set up yet. Run install-dualboot.ps1 as admin once.'; return
    }
    $answer = Read-Host 'Switch into Omarchy now? Save your work and eject shared USB drives first. [y/N]'
    if ($answer -notmatch '^(y|yes)$') { return }
    Start-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy'
}
Set-Alias omarchy Restart-ToOmarchy
