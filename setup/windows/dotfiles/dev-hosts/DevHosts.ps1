# devhost: open a tmux workspace on a remote machine over SSH, from any PowerShell or a Windows Terminal hotkey.
#
#   devhost add            wizard: SSH key, ~/.ssh/config, tmux check, command names, Terminal hotkey
#   devhost list           show configured hosts
#   devhost check [name]   probe LAN / Tailscale routes
#   devhost remove name    forget a host (leaves ~/.ssh/config alone)
#   <command> [-Target Lan|Tail] [-Check] [-Here]    e.g. `dev` opens a workstation in a new window with 4 tmux panes
#
# Config: ~\.config\dev-hosts\hosts.json. Uses Windows' built-in OpenSSH (no WSL needed).
# Works in Windows PowerShell 5.1 and PowerShell 7.

$script:DevHostsDir  = Join-Path $HOME '.config\dev-hosts'
$script:DevHostsFile = Join-Path $script:DevHostsDir 'hosts.json'
$script:SshDir       = Join-Path $HOME '.ssh'
$script:SshConfig    = Join-Path $script:SshDir 'config'
$script:CacheSeconds = 120

function Get-DevSsh {
    $c = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $p = "$env:SystemRoot\System32\OpenSSH\ssh.exe"
    if (Test-Path $p) { return $p }
    throw 'OpenSSH client not found. Install it: Settings > System > Optional features > OpenSSH Client.'
}

function Get-DevHostConfig {
    if (Test-Path $script:DevHostsFile) { $cfg = Get-Content $script:DevHostsFile -Raw | ConvertFrom-Json }
    else { $cfg = [pscustomobject]@{ hosts = @() } }
    if (-not $cfg.hosts) { $cfg | Add-Member -NotePropertyName hosts -NotePropertyValue @() -Force }
    $cfg.hosts = @($cfg.hosts)
    $cfg
}

function Save-DevHostConfig($cfg) {
    New-Item -ItemType Directory -Force -Path $script:DevHostsDir | Out-Null
    $clean = [pscustomobject]@{ hosts = @($cfg.hosts) }      # drops the old WSL fields (distro, helper)
    $clean | ConvertTo-Json -Depth 6 | Set-Content $script:DevHostsFile -Encoding UTF8
}

# Routes are "NAME-lan" and "NAME-tail" Host entries in ~/.ssh/config, tried in that order.
function Get-DevRoutes([string]$Name) {
    if (-not (Test-Path $script:SshConfig)) { return @() }
    $hostsDeclared = Select-String -Path $script:SshConfig -Pattern '^\s*Host\s+(.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value -split '\s+' }
    @("$Name-lan", "$Name-tail") | Where-Object { $hostsDeclared -contains $_ }
}

function Test-DevRoute([string]$Route) {
    $timeout = if ($Route -like '*-lan') { 3 } else { 12 }
    $argsList = @('-n', '-o', 'BatchMode=yes', '-o', "ConnectTimeout=$timeout", '-o', 'ConnectionAttempts=1', $Route, 'true')
    $p = Start-Process (Get-DevSsh) -ArgumentList $argsList -NoNewWindow -PassThru -RedirectStandardError "$env:TEMP\devhost-probe.err"
    if (-not $p.WaitForExit(($timeout + 3) * 1000)) { try { $p.Kill() } catch {}; return $false }
    $p.ExitCode -eq 0
}

function Select-DevRoute([string]$Name, [string]$Mode = 'auto', [switch]$NoCache) {
    $cache = Join-Path $env:TEMP "devhost-route-$Name"
    if (-not $NoCache -and $Mode -eq 'auto' -and (Test-Path $cache) -and ((Get-Date) - (Get-Item $cache).LastWriteTime).TotalSeconds -lt $script:CacheSeconds) {
        return (Get-Content $cache -Raw).Trim()
    }
    $routes = @(Get-DevRoutes $Name)
    if ($Mode -eq 'lan')  { $routes = @($routes | Where-Object { $_ -like '*-lan' }) }
    if ($Mode -eq 'tail') { $routes = @($routes | Where-Object { $_ -like '*-tail' }) }
    if (-not $routes) { throw "No routes for '$Name' in ~/.ssh/config. Run: devhost add" }
    foreach ($r in $routes) { if (Test-DevRoute $r) { Set-Content $cache $r; return $r } }
    throw "$Name is unreachable ($Mode). Run: devhost check $Name"
}

function Show-DevCheck([string]$Name, [string]$Mode = 'auto') {
    $routes = @(Get-DevRoutes $Name)
    if ($Mode -eq 'lan')  { $routes = @($routes | Where-Object { $_ -like '*-lan' }) }
    if ($Mode -eq 'tail') { $routes = @($routes | Where-Object { $_ -like '*-tail' }) }
    if (-not $routes) { Write-Host "  no routes for $Name in ~/.ssh/config"; return }
    foreach ($r in $routes) {
        $sw = [Diagnostics.Stopwatch]::StartNew(); $ok = Test-DevRoute $r
        "{0,-16} {1,-7} {2,5} ms" -f $r, $(if ($ok) { 'OK' } else { 'FAILED' }), $sw.ElapsedMilliseconds
    }
}

# What each pane runs: ssh straight into tmux. The session name is checked, so nothing odd reaches the remote shell.
function Get-DevPaneCommand([string]$Route, [string]$Session) {
    if ($Session -notmatch '^[A-Za-z0-9_.-]+$') { throw "Invalid tmux session name: $Session" }
    @((Get-DevSsh), '-tt', $Route, "tmux -u new-session -A -s $Session")
}

# Pane layout shared by the `dev` command and the Terminal hotkey: up to 4 panes in a 2x2 grid.
function Get-DevLayout([string[]]$Sessions) {
    $s = @($Sessions | Select-Object -First 4)
    $steps = @(@{ kind = 'tab'; session = $s[0] })
    if ($s.Count -ge 2) { $steps += @{ kind = 'split'; dir = 'right'; session = $s[1] } }
    if ($s.Count -ge 3) { $steps += @{ kind = 'split'; dir = 'down'; session = $s[2] } }
    if ($s.Count -ge 4) { $steps += @{ kind = 'focus'; dir = 'left' }; $steps += @{ kind = 'split'; dir = 'down'; session = $s[3] } }
    $steps
}

function Start-DevSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Auto', 'Lan', 'Tail')][string]$Target = 'Auto',
        [switch]$Check,
        [switch]$Here    # open in the current Terminal window instead of a new one
    )
    $cfg = Get-DevHostConfig
    $h = $cfg.hosts | Where-Object name -eq $Name | Select-Object -First 1
    if (-not $h) { Write-Error "Unknown host '$Name'. Run: devhost add"; return }
    $mode = $Target.ToLowerInvariant()
    if ($Check) { Show-DevCheck $Name $mode; return }
    try { $route = Select-DevRoute $Name $mode -NoCache:($mode -ne 'auto') } catch { Write-Error $_; return }

    $wtArgs = @('--window', $(if ($Here) { '0' } else { 'new' }))
    foreach ($step in (Get-DevLayout $h.sessions)) {
        if ($wtArgs.Count -gt 2) { $wtArgs += ';' }
        switch ($step.kind) {
            'tab'   { $wtArgs += @('new-tab', '--title', $step.session) }
            'split' { $wtArgs += @('split-pane', $(if ($step.dir -eq 'right') { '-V' } else { '-H' }), '--title', $step.session) }
            'focus' { $wtArgs += @('move-focus', $step.dir) }
        }
        if ($step.kind -ne 'focus') { $wtArgs += Get-DevPaneCommand $route $step.session }
    }
    & wt.exe @wtArgs
}

function Register-DevHostCommands {
    $cfg = Get-DevHostConfig
    foreach ($h in $cfg.hosts) {
        foreach ($c in @($h.commands)) {
            if (-not $c) { continue }
            $body = [scriptblock]::Create("Start-DevSession -Name '$($h.name)' @args")
            Set-Item -Path "function:global:$c" -Value $body
        }
    }
}

# Windows Terminal hotkey: one action per host; each pane runs dev-attach.ps1 (picks the route, then ssh -> tmux).
function Update-DevHostTerminal($cfg) {
    $wtFile = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path $wtFile)) { Write-Warning 'Windows Terminal settings not found; hotkeys skipped.'; return }
    try { $wt = Get-Content $wtFile -Raw | ConvertFrom-Json }
    catch { Write-Warning "Could not parse Terminal settings (comments?). Hotkeys skipped: $($_.Exception.Message)"; return }
    $attach = Join-Path $script:DevHostsDir 'dev-attach.ps1'

    $actions = @($wt.actions | Where-Object { $_ -and "$($_.id)" -notlike 'User.devhost.*' })
    $keys = @($wt.keybindings | Where-Object { $_ -and "$($_.id)" -notlike 'User.devhost.*' })
    foreach ($h in $cfg.hosts) {
        if (-not $h.hotkey) { continue }
        $clash = $keys | Where-Object keys -eq $h.hotkey
        if ($clash) { Write-Warning "$($h.hotkey) is already used by $($clash.id); not binding $($h.name)."; continue }
        $sub = @()
        foreach ($step in (Get-DevLayout $h.sessions)) {
            $cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$attach`" $($h.name) $($step.session)"
            switch ($step.kind) {
                'tab'   { $sub += [ordered]@{ action = 'newTab'; commandline = $cmd; tabTitle = $step.session } }
                'split' { $sub += [ordered]@{ action = 'splitPane'; split = $step.dir; commandline = $cmd; tabTitle = $step.session } }
                'focus' { $sub += [ordered]@{ action = 'moveFocus'; direction = $step.dir } }
            }
        }
        $id = "User.devhost.$($h.name)"
        $actions += [pscustomobject][ordered]@{ command = [ordered]@{ action = 'multipleActions'; actions = $sub }; id = $id; name = "Open $($h.name) (tmux)" }
        $keys += [pscustomobject][ordered]@{ id = $id; keys = $h.hotkey }
    }
    Copy-Item $wtFile "$wtFile.devhost.bak" -Force
    $wt | Add-Member -NotePropertyName actions -NotePropertyValue $actions -Force
    $wt | Add-Member -NotePropertyName keybindings -NotePropertyValue $keys -Force
    [IO.File]::WriteAllText($wtFile, ($wt | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))   # Terminal wants UTF-8 without BOM
}

# Writes (or replaces) the managed "# >>> devhost NAME" block in ~/.ssh/config.
function Set-DevSshBlock([string]$Name, [string]$User, [string]$Port, [string]$Lan, [string]$Tail, [string]$KeyFile) {
    New-Item -ItemType Directory -Force -Path $script:SshDir | Out-Null
    $begin = "# >>> devhost $Name"; $end = "# <<< devhost $Name"
    $lines = if (Test-Path $script:SshConfig) { @(Get-Content $script:SshConfig) } else { @() }
    $out = New-Object System.Collections.Generic.List[string]; $skip = $false
    foreach ($l in $lines) { if ($l -eq $begin) { $skip = $true }; if (-not $skip) { $out.Add($l) }; if ($l -eq $end) { $skip = $false } }
    $keyRel = '~/.ssh/' + (Split-Path $KeyFile -Leaf)
    $block = @($begin, '# managed by `devhost add`; edits here get replaced')
    $both = @()
    if ($Lan)  { $block += "Host $Name-lan", "  HostName $Lan";   $both += "$Name-lan" }
    if ($Tail) { $block += "Host $Name-tail", "  HostName $Tail"; $both += "$Name-tail" }
    $block += "Host $($both -join ' ')", "  User $User", "  Port $Port", "  HostKeyAlias $Name", "  IdentityFile $keyRel", '  IdentitiesOnly yes',
              '  BatchMode yes', '  StrictHostKeyChecking accept-new', '  ConnectTimeout 6', '  ServerAliveInterval 15', '  ServerAliveCountMax 4', '  LogLevel ERROR', $end
    if ($out.Count -and $out[$out.Count - 1] -ne '') { $out.Add('') }
    foreach ($b in $block) { $out.Add($b) }
    [IO.File]::WriteAllLines($script:SshConfig, [string[]]$out, (New-Object Text.UTF8Encoding $false))
}

function Read-Default([string]$Prompt, [string]$Default) {
    $suffix = if ($Default) { " [$Default]" } else { '' }
    $v = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($v)) { $Default } else { $v.Trim() }
}

function Add-DevHost {
    $cfg = Get-DevHostConfig
    $ssh = Get-DevSsh
    Write-Host "`nNew SSH workspace host. Enter keeps the [default].`n" -ForegroundColor Cyan
    do { $name = (Read-Default 'Short name (e.g. workstation)' '').ToLowerInvariant() } until ($name -match '^[a-z0-9][a-z0-9_-]*$')
    $old = $cfg.hosts | Where-Object name -eq $name | Select-Object -First 1

    $routes = @(Get-DevRoutes $name)
    $writeSsh = $true
    if ($routes.Count) {
        Write-Host "~/.ssh/config already has: $($routes -join ', ')"
        $writeSsh = (Read-Default 'Re-enter the SSH details? (y/N)' 'n') -match '^[yY]'
    }
    if ($writeSsh) {
        $okAddr = '^[A-Za-z0-9._:-]*$'
        do { $user = Read-Default 'SSH user' $env:USERNAME.ToLowerInvariant() } until ($user -match '^[a-z_][a-z0-9_.-]*$')
        do { $lan  = Read-Default 'LAN address (IP or hostname, blank = none)' '' } until ($lan -match $okAddr)
        do { $tail = Read-Default 'Tailscale address (100.x.y.z or MagicDNS name, blank = none)' '' } until ($tail -match $okAddr)
        if (-not ($lan -or $tail)) { Write-Error 'Need at least one address.'; return }
        do { $port = Read-Default 'SSH port' '22' } until ($port -match '^\d{1,5}$')

        # One key per host, so a leaked key only opens one machine. No passphrase keeps the 4 panes from prompting.
        $key = Join-Path $script:SshDir "id_ed25519_$name"
        if (-not (Test-Path $key)) {
            Write-Host "Creating SSH key $key (press Enter twice for no passphrase)..."
            & (Join-Path (Split-Path $ssh) 'ssh-keygen.exe') -t ed25519 -f $key -C "$($env:USERNAME)@$($env:COMPUTERNAME) $name"
        }
        $first = if ($lan) { $lan } else { $tail }
        Write-Host "Copying your public key to $user@$first (enter your password for that machine once)..."
        Get-Content "$key.pub" -Raw | & $ssh -p $port -o HostKeyAlias=$name -o StrictHostKeyChecking=accept-new "$user@$first" 'umask 077; mkdir -p ~/.ssh; k=$(cat); grep -qxF "$k" ~/.ssh/authorized_keys 2>/dev/null || echo "$k" >> ~/.ssh/authorized_keys'
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Copying the key failed. Check the address/user; you can re-run devhost add.' }
        Set-DevSshBlock $name $user $port $lan $tail $key
    }

    Write-Host 'Testing routes...'
    Show-DevCheck $name 'auto'
    try {
        $route = Select-DevRoute $name 'auto' -NoCache
        & $ssh -n $route 'command -v tmux >/dev/null'
        if ($LASTEXITCODE -ne 0 -and (Read-Default 'tmux is not installed on the host. Install it now with sudo? (Y/n)' 'y') -match '^[yY]') {
            & $ssh -tt -o BatchMode=no $route 'sudo apt-get install -y tmux || sudo dnf install -y tmux || sudo pacman -S --noconfirm tmux || brew install tmux'
        }
    } catch { Write-Warning $_ }

    $defaultCmd = if ($old) { ($old.commands -join ',') } elseif (-not ($cfg.hosts | Where-Object { $_.commands -contains 'dev' })) { 'dev' } else { $name }
    while ($true) {
        $cmds = @((Read-Default 'Command(s) that open it, comma separated' $defaultCmd) -split '[,\s]+' | Where-Object { $_ })
        $bad = @()
        foreach ($c in $cmds) {
            if ($c -notmatch '^[A-Za-z][\w-]*$') { $bad += "$c (letters, digits, - and _ only)"; continue }
            $mine = $cfg.hosts | Where-Object { $_.name -ne $name -and $_.commands -contains $c }
            if ($mine) { $bad += "$c (used by $($mine.name))"; continue }
            $existing = Get-Command $c -ErrorAction SilentlyContinue
            if ($existing -and $existing.CommandType -ne 'Function') { $bad += "$c (already a $($existing.CommandType): $($existing.Source))" }
        }
        if ($cmds.Count -and -not $bad) { break }
        Write-Warning ("Can't use: " + ($bad -join '; '))
    }
    $defaultSessions = if ($old) { $old.sessions -join ',' } else { 'main,code,logs,misc' }
    $sessions = @((Read-Default 'tmux sessions, one pane each (1-4)' $defaultSessions) -split '[,\s]+' | Where-Object { $_ -match '^[\w.-]+$' } | Select-Object -First 4)
    if (-not $sessions) { $sessions = @('main') }
    $defaultKey = if ($old -and $old.hotkey) { $old.hotkey } else { '' }
    $hotkey = (Read-Default 'Windows Terminal hotkey, e.g. ctrl+alt+h (blank = none)' $defaultKey).ToLowerInvariant()

    $entry = [pscustomobject][ordered]@{ name = $name; commands = $cmds; sessions = $sessions; hotkey = $hotkey }
    $cfg.hosts = @($cfg.hosts | Where-Object name -ne $name) + $entry
    Save-DevHostConfig $cfg
    Update-DevHostTerminal $cfg
    Register-DevHostCommands
    Write-Host "`nDone. Type $($cmds -join ' or ')$(if ($hotkey) { " or press $hotkey in Windows Terminal" }) to open $name." -ForegroundColor Green
}

function devhost {
    param([Parameter(Position = 0)][ValidateSet('add', 'list', 'check', 'remove', 'help')][string]$Action = 'help',
          [Parameter(Position = 1)][string]$Name)
    switch ($Action) {
        'add'    { Add-DevHost }
        'list'   { (Get-DevHostConfig).hosts | Select-Object name, @{ n = 'commands'; e = { $_.commands -join ', ' } }, @{ n = 'panes'; e = { $_.sessions -join ', ' } }, hotkey | Format-Table -AutoSize }
        'check'  { foreach ($h in ((Get-DevHostConfig).hosts | Where-Object { -not $Name -or $_.name -eq $Name })) { Write-Host "-- $($h.name)"; Show-DevCheck $h.name 'auto' } }
        'remove' {
            $cfg = Get-DevHostConfig
            $h = $cfg.hosts | Where-Object name -eq $Name
            if (-not $h) { Write-Error "Unknown host '$Name'"; return }
            foreach ($c in $h.commands) { Remove-Item "function:global:$c" -ErrorAction SilentlyContinue }
            $cfg.hosts = @($cfg.hosts | Where-Object name -ne $Name)
            Save-DevHostConfig $cfg; Update-DevHostTerminal $cfg
            Write-Host "Removed $Name (its ~/.ssh/config entries are still there)."
        }
        default  { Get-Content $PSCommandPath -TotalCount 9 | ForEach-Object { $_ -replace '^# ?', '' } }
    }
}

Register-DevHostCommands
