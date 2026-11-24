<#
.SYNOPSIS
    Sets up a fresh Windows 10/11 PC with a selectable app catalog and optional system changes.

.DESCRIPTION
    Re-run to apply selected steps again. Review existing settings first.
    Order: OneDrive removal -> debloat -> Windows settings -> winget apps -> dotfiles -> WSL.
    A step that fails is logged and the script carries on; a summary is printed at the end.

.PARAMETER Groups
    Only install these app groups from the selected catalog (default: every group with enabled=true).
.PARAMETER SkipApps
    Skip winget app installs.
.PARAMETER DryRun
    Print what would change without changing anything.
#>
[CmdletBinding()]
param(
    [string[]]$Groups,
    [switch]$SkipApps,
    [Alias('WhatIf')][switch]$DryRun,
    [string]$AppsConfig = (Join-Path $PSScriptRoot 'apps.default.json'),
    [switch]$RemoveOneDrive,
    [switch]$Debloat,
    [switch]$ApplySettings,
    [switch]$InstallDotfiles,
    [switch]$InstallWsl,
    [string]$ScreenshotsTarget
)

$ErrorActionPreference = 'Stop'
if ($Groups) { $Groups = @($Groups -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }   # "-Groups core,dev" via -File arrives as one string
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
    throw 'Open Windows PowerShell as Administrator and run this script again.'
}
$AppsConfig = (Resolve-Path -LiteralPath $AppsConfig).Path
$cfg = Get-Content -LiteralPath $AppsConfig -Raw | ConvertFrom-Json
if (-not $DryRun) {
    Write-Host 'Review the selected setup steps. Optional removal and settings switches change Windows configuration.'
    if ((Read-Host 'Apply setup now? [y/N]') -notmatch '^(y|yes)$') { return }
}
$logDir = Join-Path $env:SystemDrive 'Setup'
if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $log = Join-Path $logDir ("windows-setup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    Start-Transcript -Path $log -Force | Out-Null
}

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "windows-setup  |  $($os.Caption) build $($os.BuildNumber)  |  user $env:USERNAME  |  $(if($DryRun){'DRY RUN'}else{'live'})" -ForegroundColor Magenta
if (-not $DryRun) { Write-Host "Log: $log" }

$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

if ($RemoveOneDrive) {
    # ---------------------------------------------------------------- 1. OneDrive
    Write-Step "Removing OneDrive and keeping Desktop/Documents/Pictures local"
    Invoke-Safe 'OneDrive removal' {
        if (-not $DryRun) { Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }

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
                        # Keep the source and existing destination files.
                        robocopy $current $target /E /XC /XN /XO /R:1 /W:1 /NFL /NDL /NJH /NJS /XF desktop.ini | Out-Null
                        if ($LASTEXITCODE -ge 8) { throw "Could not copy $current (robocopy exit $LASTEXITCODE)" }
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

        # Keep the old directory and any online-only placeholders available for recovery.
        if (-not $DryRun) {
            [Environment]::SetEnvironmentVariable('OneDrive', $null, 'User')
            [Environment]::SetEnvironmentVariable('OneDriveConsumer', $null, 'User')
        }
        Write-Ok 'OneDrive removed and blocked'
    }
}

if ($Debloat) {
    # ---------------------------------------------------------------- 2. Debloat
    Write-Step "Removing preinstalled junk, ads, Copilot and Bing in Start"
    Invoke-Safe 'Debloat' {
        $junk = @(
            'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp',
            'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People',
            'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
            'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'MicrosoftTeams', 'MSTeams', 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider',
            'Microsoft.OutlookForWindows', 'microsoft.windowscommunicationsapps', 'Microsoft.549981C3F5F10', 'MicrosoftCorporationII.MicrosoftFamily',
            'Microsoft.MicrosoftJournal', 'Microsoft.Office.OneNote', 'Microsoft.SkypeApp', 'Microsoft.YourPhone.Ads', 'Microsoft.Wallet',
            # OEM / Store trialware and promo apps
            'king.com.*', '*CandyCrush*', 'Disney.*', 'Facebook.*', '*Instagram*', 'BytedancePte.Ltd.TikTok', 'AmazonVideo.PrimeVideo',
            'Amazon.com.Amazon', '*McAfee*', '*Norton*', '*WildTangent*', 'AdobeSystemsIncorporated.AdobePhotoshopExpress',
            '*ExpressVPN*', '*Booking*', '*DropboxOEM*', '*.Netflix'
        )
        $isAdmin = Test-Admin   # -AllUsers / provisioned lookups need admin (only matters for -DryRun)
        foreach ($j in $junk) {
            $pkgs = @(if ($isAdmin) { Get-AppxPackage -Name $j -AllUsers -ErrorAction SilentlyContinue } else { Get-AppxPackage -Name $j -ErrorAction SilentlyContinue })
            $prov = @(if ($isAdmin) { Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -like $j })
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

    # ---------------------------------------------------------------- 2b. Driver-delivered bloat (Tobii etc.)
    Write-Step "Removing and blocking software Windows Update pushes through drivers"
    Invoke-Safe 'Driver bloat' { & (Join-Path $Root 'block-bloat.ps1') -Config $AppsConfig -DryRun:$DryRun }
}

if ($ApplySettings) {
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
}

# ---------------------------------------------------------------- 4. Apps (through UniGetUI, which then keeps them updated)
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

$script:UgDir = Join-Path $env:ProgramFiles 'UniGetUI'
$script:UgCli = Join-Path $script:UgDir 'uniget.exe'
$script:UgReady = $false
$script:UgStarted = $false
$script:Installed = @{}

function Invoke-UniGet {
    $out = & $script:UgCli @args 2>&1 | Out-String
    try { $out | ConvertFrom-Json } catch { [pscustomobject]@{ status = 'error'; message = $out.Trim() } }
}

# UniGetUI's CLI talks to a running UniGetUI. --headless runs one without a window.
function Start-UniGetSession {
    if (-not (Test-Path $script:UgCli)) { return $false }
    if ((Invoke-UniGet status).running) { return $true }
    $script:UgStarted = $true
    Start-Process (Join-Path $script:UgDir 'UniGetUI.exe') -ArgumentList '--headless' -WindowStyle Hidden
    foreach ($i in 1..45) { Start-Sleep 2; if ((Invoke-UniGet status).running) { return $true } }
    return $false
}

function Stop-UniGetSession {
    if (-not $script:UgStarted) { return }   # leave a UniGetUI the user already had open alone
    $script:UgStarted = $false
    if (Test-Path $script:UgCli) { Invoke-UniGet 'app' 'quit' | Out-Null; Start-Sleep 3 }
    Get-Process UniGetUI -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Read-InstalledPackages {
    $script:Installed = @{}
    $r = Invoke-UniGet package installed
    foreach ($p in @($r.packages)) { if ($p) { $script:Installed["$($p.manager)|$($p.id)".ToLowerInvariant()] = $true } }
}

function ConvertTo-PackageSpec([string]$Spec) {
    $m = 'winget'; $src = 'winget'; $id = $Spec
    if ($Spec -match '^(msstore|choco|npm|cargo|pwsh|scoop|pip):(.+)$') {
        $id = $Matches[2]
        switch ($Matches[1]) { 'msstore' { $src = 'msstore' } 'choco' { $m = 'chocolatey'; $src = '' } default { $m = $Matches[1]; $src = '' } }
    }
    [pscustomobject]@{ Manager = $m; Source = $src; Id = $id; Key = "$m|$id".ToLowerInvariant() }
}

function Install-WithWinget($p) {
    winget list --id $p.Id --exact --source $p.Source --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -eq 0) { return 'installed' }
    winget install --id $p.Id --exact --source $p.Source --silent --accept-package-agreements --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -in 0, -1978335189, -1978335135, 3010, 1641) { 'ok' } else { "winget exit $LASTEXITCODE" }
}

function Install-App([string]$Spec) {
    $p = ConvertTo-PackageSpec $Spec
    if ($script:Installed.ContainsKey($p.Key)) { Write-Skip "$($p.Id) (installed)"; return }
    if ($DryRun) {
        if ($p.Manager -eq 'winget') {
            winget list --id $p.Id --exact --source $p.Source --accept-source-agreements --disable-interactivity *> $null
            if ($LASTEXITCODE -eq 0) { Write-Skip "$($p.Id) (installed)"; return }
        }
        Write-Host "    [dry]  install $($p.Id) ($($p.Manager))"; return
    }
    $result = 'not attempted'
    if ($script:UgReady) {
        foreach ($attempt in 1, 2) {
            $a = @('package', 'install', '--manager', $p.Manager, '--id', $p.Id, '--wait', 'true')
            if ($p.Source) { $a += @('--source', $p.Source) }
            $r = Invoke-UniGet @a
            if ($r.operationStatus -eq 'succeeded') { $result = 'ok'; break }
            $result = "$($r.operationStatus) $($r.message)".Trim()
            Start-Sleep 3
        }
    }
    if ($result -ne 'ok' -and $p.Manager -eq 'winget') { $result = Install-WithWinget $p }   # fallback without UniGetUI
    if ($result -in 'ok', 'installed') { Write-Ok $p.Id; $script:Installed[$p.Key] = $true }
    else { Write-Warn2 "$($p.Id) failed ($result)"; $script:Failures.Add("$($p.Manager) $($p.Id): $result") }
}

function Install-GitHubApp($app) {
    $dir = Join-Path $env:LOCALAPPDATA "Programs\$($app.name -replace '\s', '')"
    $exe = Join-Path $dir $app.exe
    if (Test-Path $exe) { Write-Skip "$($app.name) (installed)"; return }
    if ($DryRun) { Write-Host "    [dry]  $($app.name) from github.com/$($app.repo)"; return }
    $rel = Invoke-RestMethod "https://api.github.com/repos/$($app.repo)/releases/latest" -Headers @{ 'User-Agent' = 'windows-setup' }
    $asset = $rel.assets | Where-Object name -match $app.asset | Select-Object -First 1
    if (-not $asset) { throw "no asset matching $($app.asset) in $($app.repo) $($rel.tag_name)" }
    $tmp = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing
    Expand-Archive $tmp -DestinationPath $dir -Force
    $lnk = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$($app.name).lnk"
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk); $s.TargetPath = $exe; $s.WorkingDirectory = $dir; $s.Save()
    Write-Ok "$($app.name) $($rel.tag_name) -> $dir ($($app.note))"
}

if (-not $SkipApps) {
    Write-Step "Installing apps through UniGetUI"
    Invoke-Safe 'App installs' {
        if (-not $DryRun) {
            if (-not (Initialize-Winget)) { throw 'winget is not available' }
            winget source update --disable-interactivity *> $null
        }

        # UniGetUI first: it runs every other install and later auto-updates them from the tray
        if (-not (Test-Path $script:UgCli) -and -not $DryRun) {
            winget install --id Devolutions.UniGetUI --exact --source winget --silent --accept-package-agreements --accept-source-agreements `
                --disable-interactivity --custom '/NoAutoStart' *> $null
        }
        if (-not $DryRun) {
            $script:UgReady = Start-UniGetSession
            if ($script:UgReady) {
                foreach ($s in $cfg.unigetui_settings.PSObject.Properties) {
                    $a = @('settings', 'set', '--key', $s.Name)
                    if ($s.Value -is [bool]) { $a += @('--enabled', $s.Value.ToString().ToLower()) } else { $a += @('--value', "$($s.Value)") }
                    Invoke-UniGet @a | Out-Null
                }
                Write-Ok 'UniGetUI running (auto-updates on)'
            } else { Write-Warn2 'UniGetUI did not start - falling back to plain winget (no auto-updates for those)'; $script:Failures.Add('UniGetUI session') }
        }
        if ($script:UgReady) { Read-InstalledPackages }

        $hasNvidia = [bool](Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object Name -match 'NVIDIA')
        $names = $cfg.groups.PSObject.Properties.Name
        if ($Groups) { $names = $names | Where-Object { $_ -in $Groups } }
        else { $names = $names | Where-Object { $cfg.groups.$_.enabled } }
        $names = @($names | Where-Object { $cfg.groups.$_.when -ne 'nvidia-gpu' -or $hasNvidia })

        # Package managers first (winget/msstore/choco/pwsh), then npm/cargo once Node and Rust exist
        $early = @(); $late = @()
        foreach ($g in $names) { foreach ($pkg in $cfg.groups.$g.packages) { if ($pkg -match '^(npm|cargo|pip):') { $late += $pkg } else { $early += [pscustomobject]@{ g = $g; pkg = $pkg } } } }
        $lastGroup = ''
        foreach ($e in $early) {
            if ($e.g -ne $lastGroup) { Write-Host "  -- $($e.g): $($cfg.groups.($e.g).description)" -ForegroundColor White; $lastGroup = $e.g }
            Install-App $e.pkg
        }
        if ($late) {
            Write-Host "  -- npm / cargo tools" -ForegroundColor White
            Update-SessionPath
            if ($script:UgReady -and -not $DryRun) { Stop-UniGetSession; $script:UgReady = Start-UniGetSession; if ($script:UgReady) { Read-InstalledPackages } }  # restart so it sees node/cargo on PATH
            foreach ($pkg in $late) { Install-App $pkg }
        }

        if (-not $Groups) {
            Write-Host "  -- from GitHub releases" -ForegroundColor White
            foreach ($app in $cfg.github) { Invoke-Safe $app.name { Install-GitHubApp $app } }
        }
        if ($script:UgReady) { Stop-UniGetSession }
        Update-SessionPath

        # UniGetUI in the tray at every login = automatic updates
        if (Test-Path $script:UgDir) { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'WingetUI' "`"$script:UgDir\UniGetUI.exe`" --daemon" 'String' }

        # Apps no package manager has: one page of download links
        $manual = Join-Path $logDir 'manual-installs.html'
        $rows = ($cfg.manual | ForEach-Object {
            $n = [Net.WebUtility]::HtmlEncode($_.name); $w = [Net.WebUtility]::HtmlEncode($_.why)
            if ($_.url) { "<li><a href=`"$($_.url)`">$n</a> <small>$w</small></li>" } else { "<li>$n <small>$w</small></li>" }
        }) -join "`n"
        if (-not $DryRun) {
            "<!doctype html><meta charset=utf-8><title>Manual installs</title><style>body{font:16px system-ui;max-width:640px;margin:40px auto;background:#1e1e2e;color:#cdd6f4}a{color:#89b4fa}small{color:#7f849c;margin-left:6px}li{margin:8px 0}</style><h1>Install these by hand</h1><p>Licensed or not in any package manager.</p><ul>$rows</ul>" |
                Set-Content $manual -Encoding UTF8
            $script:Todo.Add("Manual installs (licensed apps etc.): $manual")
        }
    }
} else { Write-Step "Apps skipped (-SkipApps)" }

if ($InstallDotfiles) {
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

        # devhost (`dev` etc.): Windows OpenSSH + Windows Terminal panes. hosts.json is never overwritten.
        $dh = Join-Path $env:USERPROFILE '.config\dev-hosts'
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $dh | Out-Null
            Copy-Item (Join-Path $Dot 'dev-hosts\DevHosts.ps1'), (Join-Path $Dot 'dev-hosts\dev-attach.ps1') $dh -Force
            }
        Write-Ok "devhost -> $dh"

        # git
        $gitcfg = Join-Path $env:USERPROFILE '.gitconfig'
        if (-not $DryRun) {
            if ((Test-Path $gitcfg) -and -not (Test-Path "$gitcfg.bak")) { Copy-Item $gitcfg "$gitcfg.bak" }
            if (-not (Test-Path $gitcfg)) { Copy-Item (Join-Path $Dot 'git\gitconfig') $gitcfg }
            if (Get-Command git -ErrorAction SilentlyContinue) { git lfs install --skip-repo *> $null }
        }
        Write-Ok 'git config'
    }
}

if ($InstallWsl) {
    # ---------------------------------------------------------------- 6. WSL
    Write-Step "WSL with Ubuntu 24.04"
    Invoke-Safe 'WSL' {
        if ($DryRun) { Write-Host '    [dry]  wsl --install -d Ubuntu-24.04 --no-launch'; return }
        $have = (wsl.exe -l -q 2>$null) -replace "`0", '' | Where-Object { $_ -match 'Ubuntu-24.04' }
        if ($have) { Write-Skip 'Ubuntu-24.04 already installed'; return }
        wsl.exe --install -d Ubuntu-24.04 --no-launch
        $script:Todo.Add('Reboot, then open "Ubuntu-24.04" once to create your Linux user.')
    }
}

if ($ScreenshotsTarget) {
    # ---------------------------------------------------------------- 7. Screenshots link

    Write-Step "Link the screenshots folder"
    Invoke-Safe 'Screenshots link' {
        $link = Join-Path $env:USERPROFILE 'Pictures\Screenshots'
        $target = (Resolve-Path -LiteralPath $ScreenshotsTarget).Path
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw 'Screenshot target must be an existing directory.' }
        $item = Get-Item $link -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'SymbolicLink' -and ($item.Target -join '') -eq $target) { Write-Skip "already linked to $target"; return }
        if ($DryRun) { Write-Host "    [dry]  link $link -> $target"; return }
        if ($item) { throw "Move the existing path aside first: $link" }
        New-Item -ItemType Directory -Force -Path (Split-Path $link) | Out-Null
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        Write-Ok "$link -> $target"
    }
}

Write-Host "`n================ DONE ================" -ForegroundColor Magenta
if ($script:Failures.Count) {
    Write-Host "Problems ($($script:Failures.Count)) - review the problems before rerunning:" -ForegroundColor Yellow
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} else { Write-Host "No errors." -ForegroundColor Green }
Write-Host "`nStill for you:" -ForegroundColor White
$script:Todo | ForEach-Object { Write-Host "  - $_" }
if (-not $DryRun) {
    Write-Host "`nLog: $log"
    Stop-Transcript | Out-Null
    $answer = Read-Host "`nRestart now? [y/N]"
    if ($answer -match '^(y|yes)$') { Restart-Computer }
}
