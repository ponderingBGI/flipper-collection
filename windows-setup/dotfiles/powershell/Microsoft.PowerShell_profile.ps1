# Shared profile for Windows PowerShell 5.1 and PowerShell 7 (installed by windows-setup)

$ompTheme = Join-Path $env:LOCALAPPDATA 'oh-my-posh\themes\jblab_2021_better_windows.omp.json'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}

# dev: open a 4-pane Windows Terminal session on Hal (needs the dev-hal helper inside WSL)
function Start-DevSession {
    [CmdletBinding()]
    param(
        [ValidateSet("Auto", "Lan", "Tail")]
        [string]$Target = "Auto",
        [switch]$Check
    )

    $distro = "Ubuntu-24.04"
    $helper = "/home/wsl/.local/bin/dev-hal"
    $mode = $Target.ToLowerInvariant()

    if ($Check) {
        & wsl.exe -d $distro -- $helper check $mode
        return
    }

    $selectedTarget = & wsl.exe -d $distro -- $helper select $mode
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($selectedTarget)) {
        Write-Error "Could not connect to Hal. Run 'dev -Check' for route diagnostics."
        return
    }

    $selectedTarget = $selectedTarget.Trim()
    $wtArgs = @(
        "--window", "new",
        "new-tab", "--title", "main",
        "wsl.exe", "-d", $distro, "--", $helper, "pane", $selectedTarget, "main",
        ";",
        "split-pane", "-V", "--title", "code",
        "wsl.exe", "-d", $distro, "--", $helper, "pane", $selectedTarget, "code",
        ";",
        "split-pane", "-H", "--title", "logs",
        "wsl.exe", "-d", $distro, "--", $helper, "pane", $selectedTarget, "logs",
        ";",
        "move-focus", "left",
        ";",
        "split-pane", "-H", "--title", "misc",
        "wsl.exe", "-d", $distro, "--", $helper, "pane", $selectedTarget, "misc"
    )

    & wt.exe @wtArgs
}
Set-Alias dev Start-DevSession

function Start-Claude { claude --dangerously-skip-permissions @args }
Set-Alias cc Start-Claude

function Start-ClaudeResume { claude --dangerously-skip-permissions --resume @args }
Set-Alias ccr Start-ClaudeResume

# Chocolatey tab completion (only if Chocolatey is installed)
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if ($env:ChocolateyInstall -and (Test-Path $ChocolateyProfile)) {
    Import-Module "$ChocolateyProfile"
}

# winget "command not found" suggestions (PowerShell 7 only)
if ($PSVersionTable.PSVersion.Major -ge 7 -and (Get-Module -ListAvailable Microsoft.WinGet.CommandNotFound)) {
    Import-Module -Name Microsoft.WinGet.CommandNotFound
}
