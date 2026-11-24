param([string]$OutputDirectory = (Join-Path $env:TEMP 'dualboot-shrink'))
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
"select volume C`r`nshrink querymax`r`nexit" | Out-File -Encoding ascii (Join-Path $OutputDirectory 'query.txt')
diskpart /s (Join-Path $OutputDirectory 'query.txt') | Out-File (Join-Path $OutputDirectory 'diskpart.txt')
Start-Sleep 3
Get-WinEvent -FilterHashtable @{LogName='Application';Id=259} -MaxEvents 1 -EA SilentlyContinue | % { $_.TimeCreated.ToString('HH:mm:ss') + ' ' + $_.Message } | Out-File (Join-Path $OutputDirectory 'events.txt')
Get-CimInstance Win32_PageFileUsage | % { "pagefile $($_.Name) $($_.AllocatedBaseSize) MB" } | Add-Content (Join-Path $OutputDirectory 'events.txt')
'DIAG-DONE' | Add-Content (Join-Path $OutputDirectory 'events.txt')

Write-Host "==> Reports in $OutputDirectory"
