<#
.SYNOPSIS
    Sets up a fresh Windows 10/11 PC the way Milo likes it.

.DESCRIPTION
    Idempotent: safe to re-run; every step checks first and skips what is already done.
    Order: OneDrive removal -> debloat -> Windows settings -> winget apps -> dotfiles -> WSL.
    A step that fails is logged and the script carries on; a summary is printed at the end.

.PARAMETER Groups
    Only install these app groups from apps.json (default: every group with enabled=true).
.PARAMETER SkipApps
    Skip winget app installs.
.PARAMETER DryRun
    Print what would change without changing anything.
#>
[CmdletBinding()]
param(
    [string[]]$Groups,
    [switch]$SkipApps,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
# When launched from PowerShell 7, Windows PowerShell inherits PS7's module path and its core modules fail to load
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $env:PSModulePath = @(
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'),
        "$env:ProgramFiles\WindowsPowerShell\Modules",
        "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
    ) -join ';'
}
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is 10x faster without the progress bar
$Root = $PSScriptRoot
$Dot = Join-Path $Root 'dotfiles'
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Todo = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------- helpers
function Write-Step($t)  { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Write-Ok($t)    { Write-Host "    [ok]   $t" -ForegroundColor Green }
function Write-Skip($t)  { Write-Host "    [skip] $t" -ForegroundColor DarkGray }
function Write-Warn2($t) { Write-Host "    [warn] $t" -ForegroundColor Yellow }

function Invoke-Safe {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action }
    catch {
        Write-Warn2 "$Name failed: $($_.Exception.Message)"
        $script:Failures.Add("$Name - $($_.Exception.Message)")
    }
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -ne $current -and "$current" -eq "$Value") { return }
    if ($DryRun) { Write-Host "    [dry]  $Path\$Name = $Value"; return }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- preflight
if (-not $DryRun -and -not (Test-Admin)) {   # a dry run only reads, so it can run unelevated
    Write-Host "Restarting as administrator..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Groups) { $argList += @('-Groups', ($Groups -join ',')) }
    if ($SkipApps) { $argList += '-SkipApps' }
    if ($DryRun) { $argList += '-DryRun' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

$logDir = Join-Path $env:SystemDrive 'Setup'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("windows-setup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $log -Force | Out-Null

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "windows-setup  |  $($os.Caption) build $($os.BuildNumber)  |  user $env:USERNAME  |  $(if($DryRun){'DRY RUN'}else{'live'})" -ForegroundColor Magenta
Write-Host "Log: $log"

# Keep the PC awake while this runs (restored at the end)
if (-not $DryRun) { powercfg /change standby-timeout-ac 0 | Out-Null; powercfg /change monitor-timeout-ac 0 | Out-Null }
if (-not $DryRun) { try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop } catch { Write-Warn2 "execution policy: $($_.Exception.Message)" } }

$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

# ---------------------------------------------------------------- 1. OneDrive
Write-Step "Removing OneDrive and keeping Desktop/Documents/Pictures local"
Invoke-Safe 'OneDrive removal' {
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # 1a. Move any folders OneDrive "backed up" (Known Folder Move) back to the user profile
    $usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $sf  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    $folders = @(
        @{ Names = @('Desktop', '{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}'); Local = 'Desktop' },
        @{ Names = @('Personal', '{F42EE2D3-909F-4907-8871-4C22FC0BF756}'); Local = 'Documents' },
        @{ Names = @('My Pictures', '{0DDD015D-B06C-45D5-8C4C-F59713854639}'); Local = 'Pictures' }
    )
    foreach ($f in $folders) {
        $target = Join-Path $env:USERPROFILE $f.Local
        $current = [Environment]::ExpandEnvironmentVariables(((Get-ItemProperty $usf -ErrorAction SilentlyContinue).($f.Names[0])))
        if ($current -and $current -ne $target -and $current -match 'OneDrive') {
            if ($DryRun) { Write-Host "    [dry]  move $current -> $target" }
            else {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                if (Test-Path $current) {
                    # robocopy /MOVE keeps going on locked files; /R:1 /W:1 so it never hangs
                    robocopy $current $target /E /MOVE /XO /R:1 /W:1 /NFL /NDL /NJH /NJS /XF desktop.ini | Out-Null
                }
            }
            Write-Ok "$($f.Local): $current -> $target"
        }
        foreach ($n in $f.Names) { Set-Reg $usf $n "%USERPROFILE%\$($f.Local)" 'ExpandString' }
        Set-Reg $sf $f.Names[0] $target 'String'
    }

    # 1b. Uninstall (classic installer, both locations, plus the Store/MSIX package)
    foreach ($exe in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
                     "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe") {
        if (Test-Path $exe) {
            if ($DryRun) { Write-Host "    [dry]  $exe /uninstall" } else { Start-Process $exe '/uninstall' -Wait -ErrorAction SilentlyContinue }
        }
    }
    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $DryRun) { Start-Process $_.FullName '/uninstall' -Wait -ErrorAction SilentlyContinue }
    }
    Get-AppxPackage -Name '*OneDrive*' -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $DryRun) { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }
    }

    # 1c. Never come back: block sync client + folder backup, hide from Explorer, remove first-logon installer
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSync' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' 'KFMBlockOptIn' 1
    Set-Reg 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
    if (-not $DryRun) {
        Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -ErrorAction SilentlyContinue
        # Default user hive: stops OneDrive being installed for any new account
        reg load 'HKU\DefaultSetup' "$env:SystemDrive\Users\Default\NTUSER.DAT" 2>$null | Out-Null
        reg delete 'HKU\DefaultSetup\Software\Microsoft\Windows\CurrentVersion\Run' /v OneDriveSetup /f 2>$null | Out-Null
        [gc]::Collect(); Start-Sleep -Milliseconds 500
        reg unload 'HKU\DefaultSetup' 2>$null | Out-Null
        Get-ScheduledTask -TaskName 'OneDrive*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    }

    # 1d. Delete the leftover OneDrive folder only if nothing real is left in it
    $odDir = Join-Path $env:USERPROFILE 'OneDrive'
    if (Test-Path $odDir) {
        $left = @(Get-ChildItem $odDir -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' -and $_.Name -notlike '.*' })
        if ($left.Count -eq 0) {
            if (-not $DryRun) { cmd /c "attrib -r -s -h `"$odDir`" /s /d" | Out-Null; Remove-Item $odDir -Recurse -Force -ErrorAction SilentlyContinue }
            Write-Ok "removed empty $odDir"
        } else {
            Write-Warn2 "$odDir still has $($left.Count) files (probably online-only). Left it alone."
            $script:Todo.Add("Check ${odDir}: $($left.Count) files were not moved (download them from onedrive.live.com if you need them).")
        }
    }
    if (-not $DryRun) {
        [Environment]::SetEnvironmentVariable('OneDrive', $null, 'User')
        [Environment]::SetEnvironmentVariable('OneDriveConsumer', $null, 'User')
    }
    Write-Ok 'OneDrive removed and blocked'
}

# ---------------------------------------------------------------- 2. Debloat
Write-Step "Removing preinstalled junk, ads, Copilot and Bing in Start"
Invoke-Safe 'Debloat' {
    $junk = @(
        'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp',
        'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People',
        'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
        'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'MicrosoftTeams', 'MSTeams', 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider',
        'Microsoft.OutlookForWindows', 'microsoft.windowscommunicationsapps', 'Microsoft.549981C3F5F10', 'MicrosoftCorporationII.MicrosoftFamily',
        'Microsoft.MicrosoftJournal', 'Microsoft.Office.OneNote', 'Microsoft.SkypeApp', 'Microsoft.YourPhone.Ads', 'Microsoft.Wallet'
    )
    $isAdmin = Test-Admin   # -AllUsers / provisioned lookups need admin (only matters for -DryRun)
    foreach ($j in $junk) {
        $pkgs = @(if ($isAdmin) { Get-AppxPackage -Name $j -AllUsers -ErrorAction SilentlyContinue } else { Get-AppxPackage -Name $j -ErrorAction SilentlyContinue })
        $prov = @(if ($isAdmin) { Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $j })
        if ($pkgs.Count -eq 0 -and $prov.Count -eq 0) { continue }
        if ($DryRun) { Write-Host "    [dry]  remove $j"; continue }
        $pkgs | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
        $prov | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
        Write-Ok "removed $j"
    }

    # Ads, suggestions, auto-installed "promoted" apps
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'PreInstalledAppsEnabled',
                   'OemPreInstalledAppsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                   'SubscribedContent-310093Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
                   'SubscribedContent-88000326Enabled', 'RotatingLockScreenOverlayEnabled') { Set-Reg $cdm $n 0 }
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0   # "finish setting up your device" nags

    # Bing / web results in Start search
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0

    # Copilot, Recall, Widgets
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Write-Ok 'debloat done'
}

# ---------------------------------------------------------------- 3. Windows settings
Write-Step "Windows settings (dark mode, Explorer, taskbar, keyboard, power)"
Invoke-Safe 'Windows settings' {
    $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-Reg $p 'AppsUseLightTheme' 0; Set-Reg $p 'SystemUsesLightTheme' 0; Set-Reg $p 'EnableTransparency' 1

    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'HideFileExt' 0          # show file extensions
    Set-Reg $adv 'Hidden' 1               # show hidden files
    Set-Reg $adv 'TaskbarDa' 0            # no Widgets button
    Set-Reg $adv 'TaskbarMn' 0            # no Chat/Teams button
    Set-Reg $adv 'ShowCopilotButton' 0
    Set-Reg $adv 'Start_IrisRecommendations' 0
    Set-Reg $adv 'LaunchTo' 1             # Explorer opens "This PC"
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 2   # search box

    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1

    if (-not $DryRun) {
        # Keyboard: English (US) + Swiss German, US first
        $langs = New-WinUserLanguageList en-US
        $langs[0].InputMethodTips.Clear(); $langs[0].InputMethodTips.Add('0409:00000409')
        $langs.Add('de-CH'); $langs[1].InputMethodTips.Clear(); $langs[1].InputMethodTips.Add('0807:00000807')
        Set-WinUserLanguageList $langs -Force
        Set-TimeZone -Id 'Romance Standard Time'
        # High performance power plan (create it if this edition hides it)
        $hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        if (-not (powercfg /list | Select-String $hp)) { powercfg -duplicatescheme $hp | Out-Null }
        powercfg /setactive $hp 2>$null
    }
    Write-Ok 'settings applied'
}

# ---------------------------------------------------------------- 4. Apps
function Initialize-Winget {
    Update-SessionPath
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if ($wg) { try { winget --version | Out-Null; return $true } catch {} }
    Write-Host "    winget missing or broken - repairing via Microsoft.WinGet.Client"
    if ($DryRun) { return $false }
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module Microsoft.WinGet.Client -Force -Scope AllUsers -AllowClobber | Out-Null
    Import-Module Microsoft.WinGet.Client -Force
    Repair-WinGetPackageManager -AllUsers -Force -Latest | Out-Null
    Update-SessionPath
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Install-App([string]$Spec) {
    $source = 'winget'; $id = $Spec
    if ($Spec -like 'msstore:*') { $source = 'msstore'; $id = $Spec.Substring(8) }
    winget list --id $id --exact --source $source --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -eq 0) { Write-Skip "$id (installed)"; return }
    if ($DryRun) { Write-Host "    [dry]  winget install $id ($source)"; return }
    foreach ($attempt in 1, 2) {
        winget install --id $id --exact --source $source --silent --accept-package-agreements --accept-source-agreements --disable-interactivity *> $null
        $code = $LASTEXITCODE
        # 0 ok, -1978335189 already installed, -1978335135 newer already installed, 3010/1641 reboot needed
        if ($code -in 0, -1978335189, -1978335135, 3010, 1641) { Write-Ok $id; return }
        Start-Sleep -Seconds 5
    }
    Write-Warn2 "$id failed (exit $code)"
    $script:Failures.Add("winget $id (exit $code)")
}

if (-not $SkipApps) {
    Write-Step "Installing apps with winget"
    Invoke-Safe 'App installs' {
        if (-not (Initialize-Winget)) { throw 'winget is not available' }
        winget source update --disable-interactivity *> $null
        $cfg = Get-Content (Join-Path $Root 'apps.json') -Raw | ConvertFrom-Json
        $names = $cfg.groups.PSObject.Properties.Name
        if ($Groups) { $names = $names | Where-Object { $_ -in $Groups } }
        else { $names = $names | Where-Object { $cfg.groups.$_.enabled } }
        foreach ($g in $names) {
            Write-Host "  -- ${g}: $($cfg.groups.$g.description)" -ForegroundColor White
            foreach ($pkg in $cfg.groups.$g.packages) { Install-App $pkg }
            Update-SessionPath
        }
    }
} else { Write-Step "Apps skipped (-SkipApps)" }

# ---------------------------------------------------------------- 5. Dotfiles
Write-Step "oh-my-posh, fonts, PowerShell profile, Windows Terminal, git"
Invoke-Safe 'Dotfiles' {
    Update-SessionPath

    # oh-my-posh theme + Nerd Fonts used by the theme and the terminal
    $themeDir = Join-Path $env:LOCALAPPDATA 'oh-my-posh\themes'
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $themeDir | Out-Null
        Copy-Item (Join-Path $Dot 'oh-my-posh\jblab_2021_better_windows.omp.json') $themeDir -Force
    }
    $omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if ($omp) {
        foreach ($font in 'Monofur', 'Go-Mono') {
            if ($DryRun) { Write-Host "    [dry]  oh-my-posh font install $font"; continue }
            & $omp.Source font install $font *> $null
            Write-Ok "font $font"
        }
    } else { Write-Warn2 'oh-my-posh not found - fonts skipped'; $script:Failures.Add('oh-my-posh fonts') }

    # Same profile for Windows PowerShell 5.1 and PowerShell 7
    $docs = [Environment]::GetFolderPath('MyDocuments')
    foreach ($sub in 'WindowsPowerShell', 'PowerShell') {
        $dest = Join-Path $docs "$sub\Microsoft.PowerShell_profile.ps1"
        if ($DryRun) { Write-Host "    [dry]  profile -> $dest"; continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        if ((Test-Path $dest) -and -not (Test-Path "$dest.bak")) { Copy-Item $dest "$dest.bak" }
        Copy-Item (Join-Path $Dot 'powershell\Microsoft.PowerShell_profile.ps1') $dest -Force
        Write-Ok "profile $dest"
    }

    # Windows Terminal (Store and winget installs both use this path)
    $wtDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $wtDir | Out-Null
        $wtFile = Join-Path $wtDir 'settings.json'
        if ((Test-Path $wtFile) -and -not (Test-Path "$wtFile.bak")) { Copy-Item $wtFile "$wtFile.bak" }
        Copy-Item (Join-Path $Dot 'windows-terminal\settings.json') $wtFile -Force
    }
    Write-Ok 'Windows Terminal settings'

    # Windows Terminal keeps its own copy of the folder registry keys (MSIX virtualisation).
    # If it ever cached the OneDrive paths, PowerShell launched from it would miss the profile.
    if (-not $DryRun -and (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
        $k = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $fix = Join-Path $env:TEMP 'wt-shellfolders.cmd'
        @(
            "reg add `"$k`" /v Desktop /t REG_EXPAND_SZ /d `"%%USERPROFILE%%\Desktop`" /f",
            "reg add `"$k`" /v {754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5} /t REG_EXPAND_SZ /d `"%%USERPROFILE%%\Desktop`" /f",
            "reg add `"$k`" /v Personal /t REG_EXPAND_SZ /d `"%%USERPROFILE%%\Documents`" /f",
            "reg add `"$k`" /v {F42EE2D3-909F-4907-8871-4C22FC0BF756} /t REG_EXPAND_SZ /d `"%%USERPROFILE%%\Documents`" /f",
            "reg add `"$k`" /v `"My Pictures`" /t REG_EXPAND_SZ /d `"%%USERPROFILE%%\Pictures`" /f",
            "reg add `"$k`" /v {0DDD015D-B06C-45D5-8C4C-F59713854639} /t REG_EXPAND_SZ /d `"%%USERPROFILE%%\Pictures`" /f"
        ) | Set-Content $fix -Encoding ascii
        Start-Process wt.exe -ArgumentList @('-w', 'new', 'cmd.exe', '/c', $fix) -WindowStyle Minimized -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 4
    }

    # git
    $gitcfg = Join-Path $env:USERPROFILE '.gitconfig'
    if (-not $DryRun) {
        if ((Test-Path $gitcfg) -and -not (Test-Path "$gitcfg.bak")) { Copy-Item $gitcfg "$gitcfg.bak" }
        Copy-Item (Join-Path $Dot 'git\gitconfig') $gitcfg -Force
        if (Get-Command git -ErrorAction SilentlyContinue) { git lfs install --skip-repo *> $null }
    }
    Write-Ok 'git config'
}

# ---------------------------------------------------------------- 6. WSL
Write-Step "WSL with Ubuntu 24.04"
Invoke-Safe 'WSL' {
    $have = (wsl.exe -l -q 2>$null) -replace "`0", '' | Where-Object { $_ -match 'Ubuntu-24.04' }
    if ($have) { Write-Skip 'Ubuntu-24.04 already installed'; return }
    if ($DryRun) { Write-Host '    [dry]  wsl --install -d Ubuntu-24.04 --no-launch'; return }
    wsl.exe --install -d Ubuntu-24.04 --no-launch
    $script:Todo.Add('Reboot, then open "Ubuntu-24.04" once to create your Linux user.')
    $script:Todo.Add('Copy your dev-hal helper into WSL (~/.local/bin/dev-hal) so the `dev` command can reach Hal.')
}

# ---------------------------------------------------------------- 7. Finish
Write-Step "Finishing"
if (-not $DryRun) {
    powercfg /change monitor-timeout-ac 15 | Out-Null
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue   # picks up taskbar/Explorer changes; restarts itself
}

$script:Todo.Add('Sign in: gh auth login, Proton Drive, Proton Pass, Bitwarden, Syncthing (pair your phone), Tailscale/Netbird.')
$script:Todo.Add('Ableton: once Proton Drive has synced, set Settings > Library (User Library + Packs folder) to your Proton copies.')

Write-Host "`n================ DONE ================" -ForegroundColor Magenta
if ($script:Failures.Count) {
    Write-Host "Problems ($($script:Failures.Count)) - re-run the same command to retry just these:" -ForegroundColor Yellow
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} else { Write-Host "No errors." -ForegroundColor Green }
Write-Host "`nStill for you:" -ForegroundColor White
$script:Todo | ForEach-Object { Write-Host "  - $_" }
Write-Host "`nLog: $log"
Stop-Transcript | Out-Null

if (-not $DryRun) {
    $answer = Read-Host "`nRestart now to finish (recommended)? [Y/n]"
    if ($answer -notmatch '^[nN]') { Restart-Computer -Force }
}
