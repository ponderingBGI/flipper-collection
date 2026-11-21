"select volume C`r`nshrink querymax`r`nexit" | Out-File -Encoding ascii C:\dev\_dp.txt
diskpart /s C:\dev\_dp.txt | Out-File C:\dev\_dp-out.txt
Start-Sleep 3
Get-WinEvent -FilterHashtable @{LogName='Application';Id=259} -MaxEvents 1 -EA SilentlyContinue | % { $_.TimeCreated.ToString('HH:mm:ss') + ' ' + $_.Message } | Out-File C:\dev\_dp-event.txt
Get-CimInstance Win32_PageFileUsage | % { "pagefile $($_.Name) $($_.AllocatedBaseSize) MB" } | Add-Content C:\dev\_dp-event.txt
'DIAG-DONE' | Add-Content C:\dev\_dp-event.txt
