<#
.SYNOPSIS
    Removes bloatware for good, including the kind Windows Update keeps reinstalling through drivers.

.DESCRIPTION
    Works from the "blocked" list in apps.json, so it runs the same on any PC (entries that aren't
    there are simply skipped). Each entry can have:
      match    regex for program, service, process and Store app names to remove
      swc      software-component ids (SWC\...) to block
      folders  folder names to delete under Program Files, ProgramData and AppData\Local

    Why the swc part matters: OEM tools like Tobii Experience come back through Windows Update.
    A device (e.g. the webcam) gets an "Extension" driver, which creates a virtual software-component
    device (SWC\...), whose driver installs the software. So for every swc id this script:
      - adds it to the "Prevent installation of devices that match these device IDs" policy
        (only the software component is blocked; the webcam and its real driver keep working)
      - deletes the driver packages that create or install it (exported to
        C:\ProgramData\windows-setup\driver-backup first) and removes the leftover devices
    Ids found inside those driver packages are blocked too, so newer versions are covered.

    Undo a block: delete the id under HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs.
#>
[CmdletBinding()]
param([string[]]$Only, [switch]$DryRun)

$ErrorActionPreference = 'Continue'
$cfg = Get-Content (Join-Path $PSScriptRoot 'apps.json') -Raw | ConvertFrom-Json
$entries = @($cfg.blocked | Where-Object { -not $Only -or $_.name -in $Only })

function Say($t, $c = 'Gray') { Write-Host "    $t" -ForegroundColor $c }
function Act([string]$What, [scriptblock]$Do) { if ($DryRun) { Say "[dry]  $What" } else { Say $What; & $Do } }

# Driver store packages with the SWC ids they create (Extension: ComponentIDs) or install on (SoftwareComponent)
$packages = @(Get-ChildItem "$env:SystemRoot\INF\oem*.inf" -ErrorAction SilentlyContinue | ForEach-Object {
    $text = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    $ids = @([regex]::Matches($text, '(?i)SWC\\[\w&\-]+') | ForEach-Object { $_.Value })
    $ids += @([regex]::Matches($text, '(?im)^\s*ComponentIDs\s*=\s*([^\r\n;]+)') | ForEach-Object { $_.Groups[1].Value -split '\s*,\s*' } | ForEach-Object { "SWC\$($_.Trim())" })
    if ($ids) {
        [pscustomobject]@{
            Inf   = $_.Name
            Class = if ($text -match '(?im)^\s*Class\s*=\s*(\w+)') { $Matches[1] } else { '' }
            Ids   = @($ids | ForEach-Object { $_.ToUpperInvariant() } | Select-Object -Unique)
        }
    }
})

# NSIS and Inno Setup uninstallers have known silent switches even when the app doesn't register one
function Get-UninstallerExe([string]$cmd) {
    if ($cmd -match '^\s*"([^"]+\.exe)"' -or $cmd -match '^\s*(\S+\.exe)') { if (Test-Path $Matches[1]) { return $Matches[1] } }
    return $null
}
function Get-SilentSwitch([string]$exe) {
    if ((Get-Item $exe).Length -eq 0) { return $null }
    $bytes = [IO.File]::ReadAllBytes($exe)
    $text = [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min($bytes.Length, 4MB))
    if ($text -match 'Nullsoft') { return '/S' }
    if ($text -match 'Inno Setup') { return '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
}

$restr = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$denyKey = "$restr\DenyDeviceIDs"
$uninstallKeys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
$appx = try { @(Get-AppxPackage -AllUsers -ErrorAction Stop) } catch { @(Get-AppxPackage) }
$manual = @()

foreach ($e in $entries) {
    Write-Host "  -- $($e.name)" -ForegroundColor White
    $found = $false

    # 1. Block the software-component ids first, so nothing reinstalls while we clean up
    $ids = @(); $pkgs = @()
    if ($e.swc) {
        $want = @($e.swc | ForEach-Object { $_.ToUpperInvariant() })
        $pkgs = @($packages | Where-Object { $_.Class -in 'SoftwareComponent', 'Extension' -and ($_.Ids | Where-Object { $_ -in $want }) })
        $ids = @($want + ($pkgs | ForEach-Object { $_.Ids }) | Select-Object -Unique)
        $existing = @()
        if (Test-Path $denyKey) { $existing = @((Get-ItemProperty $denyKey).PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object { "$($_.Value)".ToUpperInvariant() }) }
        $new = @($ids | Where-Object { $_ -notin $existing })
        if ($new) {
            Act "block device ids: $($new -join ', ')" {
                New-Item -Path $denyKey -Force | Out-Null
                Set-ItemProperty $restr -Name DenyDeviceIDs -Value 1 -Type DWord
                Set-ItemProperty $restr -Name DenyDeviceIDsRetroactive -Value 0 -Type DWord   # never touches other installed devices
                $n = (@((Get-ItemProperty $denyKey).PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object { [int]$_.Name }) + 0 | Measure-Object -Maximum).Maximum
                foreach ($id in $new) { $n++; New-ItemProperty $denyKey -Name "$n" -Value $id -PropertyType String -Force | Out-Null }
            }
        } else { Say '[ok]   device ids blocked' DarkGray }
    }

    # 2. Services, processes, programs, Store apps
    $services = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match $e.match -or $_.DisplayName -match $e.match })
    foreach ($s in $services) {
        $found = $true
        Act "stop + disable service $($s.Name)" { Stop-Service $s.Name -Force -ErrorAction SilentlyContinue; Set-Service $s.Name -StartupType Disabled -ErrorAction SilentlyContinue }
    }
    $procs = @(Get-Process | Where-Object { $_.Name -match $e.match })
    if ($procs) { $found = $true; Act "kill $($procs.Count) processes" { $procs | Stop-Process -Force -ErrorAction SilentlyContinue } }

    foreach ($app in @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $e.match -and -not $_.SystemComponent })) {
        $found = $true
        if ($app.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$' -and "$($app.UninstallString)" -match 'msiexec') {
            Act "uninstall $($app.DisplayName)" { Start-Process msiexec.exe "/x $($app.PSChildName) /qn /norestart" -Wait }
        } elseif ($app.QuietUninstallString) {
            Act "uninstall $($app.DisplayName)" { Start-Process cmd.exe "/c $($app.QuietUninstallString)" -Wait -WindowStyle Hidden }
        } elseif (($exe = Get-UninstallerExe $app.UninstallString) -and ($silent = Get-SilentSwitch $exe)) {
            Act "uninstall $($app.DisplayName) ($silent)" { Start-Process $exe $silent -Wait }
        } elseif (($exe = Get-UninstallerExe $app.UninstallString) -eq $null -or (Get-Item $exe).Length -eq 0) {
            # uninstaller missing or empty: the install is already broken, so just drop its leftovers below and the entry
            Act "remove broken entry $($app.DisplayName)" { Remove-Item $app.PSPath -Recurse -Force }
        } else {
            Say "$($app.DisplayName) has no silent uninstaller - remove it in Settings > Apps" Yellow
            $manual += $app.DisplayName
        }
    }
    foreach ($a in @($appx | Where-Object { $_.Name -match $e.match -or $_.Publisher -match $e.match })) {
        $found = $true
        Act "remove Store app $($a.Name)" { Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
    }

    # 3. Software-component devices and driver packages
    if ($ids) {
        foreach ($d in @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'SWD\DRIVERENUM\*' })) {
            $hw = @((Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_HardwareIds -ErrorAction SilentlyContinue).Data)
            if ($hw | Where-Object { "$_".ToUpperInvariant() -in $ids }) { $found = $true; Act "remove device $($d.InstanceId)" { pnputil /remove-device $d.InstanceId | Out-Null } }
        }
        $backup = Join-Path $env:ProgramData "windows-setup\driver-backup\$($e.name -replace '\W', '-')"
        foreach ($p in $pkgs) {
            $found = $true
            Act "delete driver package $($p.Inf) ($($p.Class))" {
                New-Item -ItemType Directory -Force -Path $backup | Out-Null
                pnputil /export-driver $p.Inf $backup | Out-Null
                pnputil /delete-driver $p.Inf /uninstall /force | Out-Null
            }
        }
    }

    # 4. Leftovers
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match $e.match -or $_.TaskPath -match $e.match })) {
        $found = $true
        Act "delete scheduled task $($t.TaskName)" { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false }
    }
    foreach ($s in @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match $e.match -or $_.DisplayName -match $e.match })) {
        Act "delete service $($s.Name)" { sc.exe delete $s.Name | Out-Null }
    }
    Get-Process | Where-Object { $_.Name -match $e.match } | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($f in @($e.folders | Where-Object { $_ -match '^[\w .-]+$' })) {   # plain names only, never a path
        foreach ($dir in "$env:ProgramFiles\$f", "${env:ProgramFiles(x86)}\$f", "$env:ProgramData\$f", "$env:LOCALAPPDATA\$f", "$env:SystemRoot\System32\config\systemprofile\AppData\Local\$f") {
            if (Test-Path $dir) { $found = $true; Act "delete $dir" { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue } }
        }
    }
    if (-not $found) { Say '[ok]   not on this PC' DarkGray }
}
if ($manual) { Write-Host "  Remove by hand (no silent uninstaller): $($manual -join ', ')" -ForegroundColor Yellow }
