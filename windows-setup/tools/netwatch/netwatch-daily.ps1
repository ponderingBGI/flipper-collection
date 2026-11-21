$rep = 'C:\ProgramData\netwatch\reports'
New-Item -ItemType Directory -Force $rep | Out-Null
$out = Join-Path $rep ((Get-Date -Format 'yyyy-MM-dd') + '.txt')
& 'C:\Program Files\netwatch\netwatch.ps1' -Hours 24 *>&1 | Out-String -Width 220 | Set-Content $out -Encoding utf8
Get-ChildItem $rep -Filter *.txt | Sort-Object LastWriteTime -Descending | Select-Object -Skip 60 | Remove-Item -Force
