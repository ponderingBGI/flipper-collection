$log='C:\dev\_shrink-loop6.log'
function L($m){ "$(Get-Date -f HH:mm:ss) $m" | Add-Content $log }
function QueryMax {
  "select volume C`r`nshrink querymax`r`nexit" | Out-File -Encoding ascii C:\dev\_dp.txt
  $o = diskpart /s C:\dev\_dp.txt
  $line = $o | ? { $_ -match 'reclaimable bytes is:\s+([\d,\.]+)\s*(MB|GB)' } | select -First 1
  if ($line -match 'is:\s+([\d,\.]+)\s*(MB|GB)') { $v=[double]($matches[1] -replace '[,\.]',''); if($matches[2]-eq'GB'){$v*=1024}; return $v } ; return 0
}
Get-Process defrag -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
L 'start (defrag stopped)'
vssadmin delete shadows /for=C: /all /quiet | Out-Null; Disable-ComputerRestore -Drive 'C:\' -EA SilentlyContinue; L 'restore points deleted, System Restore on C: paused'
$p = Get-Partition -DriveLetter C
$targetMB = [math]::Floor(($p.Size/2)/1MB)
$needMB = [math]::Floor($p.Size/1MB) - $targetMB
L "need to reclaim $needMB MB"
$seen=@{}
for ($i=0; $i -lt 60; $i++) {
  $since = Get-Date
  $max = QueryMax
  L "round ${i}: reclaimable $max MB"
  if ($max -ge $needMB) { break }
  Start-Sleep 2
  $ev = Get-WinEvent -FilterHashtable @{LogName='Application';Id=259;StartTime=$since.AddSeconds(-5)} -MaxEvents 1 -EA SilentlyContinue
  if (-not $ev) { L 'no 259 event'; break }
  if ($ev.Message -match 'unmovable file appears to be:\s*(.+?)::') { $f = $matches[1].Trim() } else { L 'could not parse'; break }
  L "blocker: $f"
  if ($seen[$f]) { L 'same blocker again, stop'; break }; $seen[$f]=1
  $full = 'C:' + $f
  if ($f -match '^\\Users\\[^\\]+\\AppData\\Local\\Temp\\|^\\Windows\\Temp\\|^\\\$Recycle\.Bin\\|^\\Windows\\SoftwareDistribution\\Download\\|^\\ProgramData\\Package Cache\\.+\.tmp') {
     Remove-Item -LiteralPath $full -Force -EA SilentlyContinue
     L ("deleted temp file: " + -not (Test-Path -LiteralPath $full))
  } elseif ($f -match '^\\System Volume Information') {
     vssadmin delete shadows /for=C: /all /quiet | Out-Null; Disable-ComputerRestore -Drive 'C:\' -EA SilentlyContinue; L 'deleted shadow copies again'
  } elseif ($f -match '^\\\$') {
     L 'NTFS metadata blocker'; break
  } elseif ($f -match 'pagefile\.sys') {
     L 'PAGEFILE is the blocker - stopping, nothing changed'; break
  } elseif ($f -match '^\\Users\\' -and (Test-Path -LiteralPath $full)) {
     try {
       $tmp = $full + '.reloc-tmp'
       $h1 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
       $attr = (Get-Item -LiteralPath $full -Force).Attributes
       $mt = (Get-Item -LiteralPath $full -Force).LastWriteTime
       [IO.File]::Copy($full, $tmp, $true)
       if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne $h1) { Remove-Item -LiteralPath $tmp -Force; throw 'hash mismatch on copy' }
       [IO.File]::Delete($full); [IO.File]::Move($tmp, $full)
       (Get-Item -LiteralPath $full -Force).LastWriteTime = $mt; (Get-Item -LiteralPath $full -Force).Attributes = $attr
       if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne $h1) { throw 'hash mismatch after replace' }
       L 'relocated (copy+verify+replace, same content)'
     } catch { L "relocate FAILED: $_"; break }
  } else {
     L 'non-user file, not touching it'; break
  }
}
$max = QueryMax
L "final reclaimable $max MB (need $needMB)"
$shrinkMB = [math]::Min($max, $needMB) - 1024
if ($shrinkMB -gt 50000) {
  $newSize = $p.Size - ([uint64]$shrinkMB * 1MB)
  try { Resize-Partition -DriveLetter C -Size $newSize -ErrorAction Stop; L "resized by $shrinkMB MB" } catch { L "resize FAILED: $_" }
} else { L 'not enough reclaimable to shrink yet' }
$p2 = Get-Partition -DriveLetter C
L ("C now {0:N1} GiB; disk largest free extent {1:N1} GiB" -f ($p2.Size/1GB), ((Get-Disk -Number $p2.DiskNumber).LargestFreeExtent/1GB))
L 'DONE'
