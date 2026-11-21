# omarchy: restart straight into Omarchy (asks first). Ctrl+Alt+O and the Start menu "Omarchy" shortcut do the same.
# Setup (once, admin): windows-setup\dotfiles\dualboot\install-dualboot.ps1
function Restart-ToOmarchy {
    if (-not (Get-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy' -ErrorAction SilentlyContinue)) {
        Write-Host 'Not set up yet. Run install-dualboot.ps1 as admin once (windows-setup does it for you).'; return
    }
    $answer = Read-Host 'Restart into Omarchy now? Save your work first. [Y/n]'
    if ($answer -match '^[nN]') { return }
    Start-ScheduledTask -TaskName 'DualBoot-RebootToOmarchy'
}
Set-Alias omarchy Restart-ToOmarchy
