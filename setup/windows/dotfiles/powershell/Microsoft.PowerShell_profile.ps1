# Shared profile for Windows PowerShell 5.1 and PowerShell 7 (installed by windows-setup)

$ompTheme = Join-Path $env:LOCALAPPDATA 'oh-my-posh\themes\jblab_2021_better_windows.omp.json'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}

# devhost / dev: SSH + tmux workspaces (see ~\.config\dev-hosts\DevHosts.ps1; `devhost add` to set one up)
$devHosts = Join-Path $HOME '.config\dev-hosts\DevHosts.ps1'
if (Test-Path $devHosts) { . $devHosts }

# omarchy: restart into Omarchy once (dual boot)
$dualBoot = Join-Path $HOME '.config\dualboot\DualBoot.ps1'
if (Test-Path $dualBoot) { . $dualBoot }

# Chocolatey tab completion (only if Chocolatey is installed)
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if ($env:ChocolateyInstall -and (Test-Path $ChocolateyProfile)) {
    Import-Module "$ChocolateyProfile"
}

# winget "command not found" suggestions (PowerShell 7 only)
if ($PSVersionTable.PSVersion.Major -ge 7 -and (Get-Module -ListAvailable Microsoft.WinGet.CommandNotFound)) {
    Import-Module -Name Microsoft.WinGet.CommandNotFound
}
