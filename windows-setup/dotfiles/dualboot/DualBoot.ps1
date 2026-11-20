# omarchy: restart straight into Omarchy once (next boot after that is back to the normal order).
# The first run asks for admin once to register a scheduled task; after that it runs without a prompt.

$script:DualBootTask = 'DualBoot-RebootToOmarchy'

function Restart-ToOmarchy {
    param([switch]$Setup)
    $task = Get-ScheduledTask -TaskName $script:DualBootTask -ErrorAction SilentlyContinue
    if (-not $task -or $Setup) {
        $script = Join-Path $HOME '.config\dualboot\reboot-to-omarchy.ps1'
        if (-not (Test-Path $script)) { Write-Error "Missing $script (re-run windows-setup)."; return }
        Write-Host 'One-time setup: registering the reboot task (admin prompt)...'
        $cmd = "Register-ScheduledTask -TaskName '$script:DualBootTask' -Force " +
               "-Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`"') " +
               "-Principal (New-ScheduledTaskPrincipal -UserId '$env:USERDOMAIN\$env:USERNAME' -LogonType Interactive -RunLevel Highest) " +
               "-Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) | Out-Null"
        Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile', '-Command', $cmd
        if (-not (Get-ScheduledTask -TaskName $script:DualBootTask -ErrorAction SilentlyContinue)) { Write-Error 'Task was not created.'; return }
        if ($Setup) { return }
    }
    $answer = Read-Host 'Restart into Omarchy now? Save your work first. [Y/n]'
    if ($answer -match '^[nN]') { return }
    Start-ScheduledTask -TaskName $script:DualBootTask
}
Set-Alias omarchy Restart-ToOmarchy
