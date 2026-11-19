# Bootstrap for windows-setup. Usage (admin PowerShell, or Win+R):
#   irm https://raw.githubusercontent.com/PonderingAI/flipper-collection/main/windows-setup/go.ps1 | iex
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072   # TLS 1.2 on older Windows 10
$repo = 'PonderingAI/flipper-collection'; $branch = 'main'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/$repo/$branch/windows-setup/go.ps1 | iex`""
    return
}

Write-Host "Downloading windows-setup..." -ForegroundColor Cyan
$work = Join-Path $env:TEMP 'windows-setup'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Path $work | Out-Null
$zip = Join-Path $work 'repo.zip'
foreach ($i in 1..3) {
    try { Invoke-WebRequest "https://codeload.github.com/$repo/zip/refs/heads/$branch" -OutFile $zip -UseBasicParsing; break }
    catch { if ($i -eq 3) { throw }; Write-Host "Download failed, retrying in 5s (is the network up?)"; Start-Sleep 5 }
}
Expand-Archive $zip -DestinationPath $work -Force
$setup = Get-ChildItem $work -Recurse -Filter setup.ps1 | Where-Object { $_.Directory.Name -eq 'windows-setup' } | Select-Object -First 1
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setup.FullName
