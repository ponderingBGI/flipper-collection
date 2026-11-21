<#
netwatch.ps1 - who on this PC talks to whom, and what's new.

Needs Sysmon (logs every connection + DNS lookup with the process that made it):
  winget install Microsoft.Sysinternals.Sysmon
  Invoke-WebRequest https://raw.githubusercontent.com/olafhartong/sysmon-modular/master/sysmonconfig.xml -OutFile $env:TEMP\sysmon.xml
  sysmon64 -accepteula -i $env:TEMP\sysmon.xml          (admin)

Usage (admin PowerShell):
  .\netwatch.ps1                 # last 24h: new process->domain pairs since last run
  .\netwatch.ps1 -Hours 168 -All # everything in the last week, not just new
  .\netwatch.ps1 -Reset          # forget the baseline (next run = everything is new)

First run builds the baseline. After that only NEW pairs show up, and unsigned
or user-folder programs are marked with !!.
#>
param([int]$Hours = 24, [switch]$All, [switch]$Reset)

$dir  = Join-Path $env:ProgramData 'netwatch'
$base = Join-Path $dir 'baseline.json'
New-Item -ItemType Directory -Force $dir | Out-Null
if ($Reset) { Remove-Item $base -ErrorAction SilentlyContinue }

$known = @{}
if (Test-Path $base) { (Get-Content $base -Raw | ConvertFrom-Json) | ForEach-Object { $known[$_] = $true } }

$since = (Get-Date).AddHours(-$Hours)
$ev = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Sysmon/Operational'; Id = 3, 22; StartTime = $since } -ErrorAction SilentlyContinue
if (-not $ev) { Write-Host "No Sysmon events. Is Sysmon installed and running? (Get-Service Sysmon64)"; return }

function Field($e, $name) { ([xml]$e.ToXml()).Event.EventData.Data | Where-Object Name -eq $name | Select-Object -ExpandProperty '#text' }

# IP -> name from DNS events, so connections show domains instead of bare IPs
$ipName = @{}
$rows = foreach ($e in $ev) {
  $img = Field $e 'Image'
  if ($e.Id -eq 22) {
    $q = Field $e 'QueryName'; $r = Field $e 'QueryResults'
    if ($r) { $r -split ';' | ForEach-Object { if ($_ -match '\d+\.\d+\.\d+\.\d+|[0-9a-f:]{6,}') { $ipName[$Matches[0]] = $q } } }
    [pscustomobject]@{ Time = $e.TimeCreated; Image = $img; Dest = $q; Port = 'dns' }
  } else {
    $ip = Field $e 'DestinationIp'
    if ($ip -match '^(127\.|::1|0\.0\.0\.0|fe80|ff0)') { continue }
    [pscustomobject]@{ Time = $e.TimeCreated; Image = $img; Dest = $ip; Port = Field $e 'DestinationPort' }
  }
}
foreach ($r in $rows) { if ($ipName[$r.Dest]) { $r.Dest = $ipName[$r.Dest] } }

$sigCache = @{}
function Flag($path) {
  if (-not $sigCache.ContainsKey($path)) {
    $s = (Get-AuthenticodeSignature $path -ErrorAction SilentlyContinue).Status
    $sigCache[$path] = ($s -ne 'Valid') -or ($path -match '\\(ProgramData|AppData\\Roaming|Temp|Users\\Public)\\')
  }
  if ($sigCache[$path]) { '!!' } else { '  ' }
}

$groups = $rows | Group-Object { "$($_.Image)|$($_.Dest)" }
$out = foreach ($g in $groups) {
  $isNew = -not $known.ContainsKey($g.Name)
  if ($All -or $isNew) {
    $f = $g.Group[0]
    [pscustomobject]@{
      Flag    = Flag $f.Image
      New     = if ($isNew) { 'NEW' } else { '' }
      Process = Split-Path $f.Image -Leaf
      Dest    = $f.Dest
      Ports   = ($g.Group.Port | Sort-Object -Unique) -join ','
      Count   = $g.Count
      Last    = ($g.Group.Time | Measure-Object -Maximum).Maximum.ToString('MM-dd HH:mm')
      Path    = $f.Image
    }
  }
}

$out | Sort-Object Flag, Process, Dest -Descending | Format-Table Flag, New, Process, Dest, Ports, Count, Last -AutoSize
$flagged = @($out | Where-Object Flag -eq '!!')
if ($flagged) { "`n!! = unsigned or running from a user-writable folder. Paths:"; $flagged.Path | Sort-Object -Unique }

$groups.Name + @($known.Keys) | Sort-Object -Unique | ConvertTo-Json | Set-Content $base -Encoding utf8
"`n$($groups.Count) process->destination pairs in the last $Hours h, $(@($out | Where-Object New).Count) new. Baseline: $base"
