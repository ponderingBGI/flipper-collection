#requires -Version 7
<#
 Copies the planned files from the T7 into Proton Drive in rounds (default 60 GB), checks every copy by SHA-256,
 then waits until Proton has uploaded the round (the file can be made online-only) before starting the next.
 Never touches the source. Resumable: progress in C:\dev\t7-to-proton\progress.csv. Status: status.txt.
#>
param([long]$RoundGB = 60, [long]$KeepFreeGB = 40)
$work = 'C:\dev\t7-to-proton'; $root = "$env:USERPROFILE\Proton Drive\mpcinema\My files"
$status = "$work\status.txt"; $prog = "$work\progress.csv"; $errlog = "$work\errors.txt"
$mutex = [Threading.Mutex]::new($false, 'Global\t7-to-proton'); if (-not $mutex.WaitOne(0)) { exit }
function Say($m) { "$(Get-Date -f 'yyyy-MM-dd HH:mm') $m" | Add-Content $status }
function Hash($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Online($p) { $a = [int](Get-Item -LiteralPath $p -Force).Attributes; ($a -band 0x400000) -or ($a -band 0x1000) }

$plan = Import-Csv "$work\plan.csv"
$done = @{}; if (Test-Path $prog) { Import-Csv $prog | ForEach-Object { $done[$_.Dst] = $_ } }
if (-not (Test-Path 'D:\stuff')) { Say 'T7 not connected - waiting for next run'; exit }
$todo = @($plan | Where-Object { -not $done.ContainsKey($_.Dst) -or $done[$_.Dst].State -ne 'uploaded' })
Say ("start: $($todo.Count) files left, {0:N1} GB" -f (($todo | Measure-Object Size -Sum).Sum/1GB))

while ($todo.Count) {
  # 1. copy one round
  $free = (Get-Volume C).SizeRemaining; $budget = [math]::Min($RoundGB * 1GB, $free - $KeepFreeGB * 1GB)
  if ($budget -lt 1GB) { Say ("C: too full ({0:N0} GB free) - waiting" -f ($free/1GB)); Start-Sleep 900; continue }
  $round = @(); $sum = 0
  foreach ($f in $todo) { if ($done.ContainsKey($f.Dst) -and $done[$f.Dst].State -eq 'verified') { $round += $f; continue }
                         if ($sum + [long]$f.Size -gt $budget -and $round.Count) { continue }; $round += $f; $sum += [long]$f.Size }
  Say ("round: $($round.Count) files, {0:N1} GB" -f ($sum/1GB))
  foreach ($f in $round) {
    $dst = Join-Path $root $f.Dst
    if ($done.ContainsKey($f.Dst) -and $done[$f.Dst].State -eq 'verified' -and (Test-Path -LiteralPath $dst)) { continue }
    try {
      New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
      if ((Test-Path -LiteralPath $dst) -and (Get-Item -LiteralPath $dst).CreationTime -gt [datetime]'2026-11-21' -and (Get-Item -LiteralPath $dst).Length -ne [long]$f.Size) { Remove-Item -LiteralPath $dst -Force }
      if (Test-Path -LiteralPath $dst) { $n = 1; $base = [IO.Path]::GetFileNameWithoutExtension($dst); $ext = [IO.Path]::GetExtension($dst)
        $hs = Hash $f.Src; if ((Hash $dst) -eq $hs) { $done[$f.Dst] = [pscustomobject]@{ Dst = $f.Dst; Src = $f.Src; Sha256 = $hs; State = 'verified' }; continue }
        while (Test-Path -LiteralPath $dst) { $dst = Join-Path (Split-Path $dst) "$base ($n)$ext"; $n++ } }
      Copy-Item -LiteralPath $f.Src -Destination $dst -Force
      $hs = Hash $f.Src; $hd = Hash $dst
      if ($hs -ne $hd) { Copy-Item -LiteralPath $f.Src -Destination $dst -Force; $hd = Hash $dst }
      if ($hs -ne $hd) { "$(Get-Date -f s) HASH MISMATCH $($f.Src)" | Add-Content $errlog; continue }
      (Get-Item -LiteralPath $dst).LastWriteTime = (Get-Item -LiteralPath $f.Src).LastWriteTime
      $done[$f.Dst] = [pscustomobject]@{ Dst = $f.Dst; Src = $f.Src; Sha256 = $hs; State = 'verified' }
    } catch { "$(Get-Date -f s) $($f.Src): $_" | Add-Content $errlog }
  }
  $done.Values | Export-Csv $prog -NoTypeInformation -Encoding utf8
  # 2. wait until Proton has uploaded the round: ask for online-only, then wait until each file actually is
  $wait = @($round | Where-Object { $done.ContainsKey($_.Dst) -and $done[$_.Dst].State -eq 'verified' })
  $wait | ForEach-Object { attrib +U -P (Join-Path $root $_.Dst) 2>$null | Out-Null }
  $t0 = Get-Date
  while ($wait.Count) {
    Start-Sleep 300
    $still = @(); foreach ($f in $wait) { $p = Join-Path $root $f.Dst
      if ((Test-Path -LiteralPath $p) -and (Online $p)) { $done[$f.Dst].State = 'uploaded' } else { attrib +U -P $p 2>$null | Out-Null; $still += $f } }
    $wait = $still; $done.Values | Export-Csv $prog -NoTypeInformation -Encoding utf8
    Say ("uploading: $($wait.Count) files of this round left ({0:N1} GB), running {1:N0} min" -f (($wait | Measure-Object Size -Sum).Sum/1GB), ((Get-Date) - $t0).TotalMinutes)
  }
  $todo = @($plan | Where-Object { -not $done.ContainsKey($_.Dst) -or $done[$_.Dst].State -ne 'uploaded' })
  Say ("round uploaded. left: $($todo.Count) files, {0:N1} GB" -f (($todo | Measure-Object Size -Sum).Sum/1GB))
}
Say 'ALL UPLOADED'
