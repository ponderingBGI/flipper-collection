# devhost: open a tmux workspace on a remote machine over SSH, from any PowerShell or a Windows Terminal hotkey.
#
#   devhost add            wizard: SSH key, ~/.ssh/config, tmux check, command names, Terminal hotkey
#   devhost list           show configured hosts
#   devhost check [name]   probe LAN / Tailscale routes
#   devhost remove name    forget a host (leaves ~/.ssh/config alone)
#   <command> [-Target Lan|Tail] [-Check] [-Here]    e.g. `dev` opens Hal in a new window with 4 tmux panes
#
# Config: ~\.config\dev-hosts\hosts.json   SSH runs inside WSL (ControlMaster keeps panes on one connection).
# Works in Windows PowerShell 5.1 and PowerShell 7.

$script:DevHostsDir = Join-Path $HOME '.config\dev-hosts'
$script:DevHostsFile = Join-Path $script:DevHostsDir 'hosts.json'
$script:DevConnectInstalled = $false

function Get-DevHostConfig {
    if (Test-Path $script:DevHostsFile) {
        $cfg = Get-Content $script:DevHostsFile -Raw | ConvertFrom-Json
    } else {
        $cfg = [pscustomobject]@{ distro = 'Ubuntu-24.04'; helper = ''; hosts = @() }
    }
    if (-not $cfg.hosts) { $cfg.hosts = @() }
    $cfg.hosts = @($cfg.hosts)
    $cfg
}

function Save-DevHostConfig($cfg) {
    New-Item -ItemType Directory -Force -Path $script:DevHostsDir | Out-Null
    $cfg | ConvertTo-Json -Depth 6 | Set-Content $script:DevHostsFile -Encoding UTF8
}

function Invoke-DevWsl {
    param([string]$Distro, [string[]]$Arguments)
    & wsl.exe -d $Distro -e @Arguments   # -e: run directly, no extra shell expanding our $vars
}

# Copies dev-connect into WSL (~/.local/bin) when missing or changed. Returns its absolute Linux path.
function Install-DevConnect($cfg) {
    $src = Join-Path $script:DevHostsDir 'dev-connect'
    if (-not (Test-Path $src)) { throw "Missing $src (re-run windows-setup, or copy it from the flipper-collection repo)." }
    $distros = (wsl.exe -l -q 2>$null) -replace "`0", '' | Where-Object { $_.Trim() }
    if ($distros -notcontains $cfg.distro) { throw "WSL distro '$($cfg.distro)' is not installed. Run: wsl --install -d $($cfg.distro)" }
    if ($script:DevConnectInstalled -and $cfg.helper) { return $cfg.helper }

    # Windows PowerShell mangles double quotes in native arguments, so the path travels via WSLENV (/p = translate path)
    $env:DEVCONNECT_SRC = (Resolve-Path $src).Path
    $env:WSLENV = (@($env:WSLENV -split ':' | Where-Object { $_ -and $_ -notlike 'DEVCONNECT_SRC*' }) + 'DEVCONNECT_SRC/p') -join ':'
    $sh = "d=`$HOME/.local/bin; mkdir -p `$d && tr -d '\r' < `$DEVCONNECT_SRC > `$d/dev-connect.new && chmod 755 `$d/dev-connect.new && " +
          "{ cmp -s `$d/dev-connect.new `$d/dev-connect && rm `$d/dev-connect.new || mv `$d/dev-connect.new `$d/dev-connect; } && printf %s `$d/dev-connect"
    $helper = (Invoke-DevWsl $cfg.distro @('sh', '-c', $sh) | Out-String).Trim()
    if (-not $helper) { throw 'Could not install dev-connect into WSL.' }
    $script:DevConnectInstalled = $true
    if ($cfg.helper -ne $helper) { $cfg.helper = $helper; Save-DevHostConfig $cfg }
    $helper
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
    $helper = Install-DevConnect $cfg
    $mode = $Target.ToLowerInvariant()

    if ($Check) { Invoke-DevWsl $cfg.distro @($helper, 'check', $Name, $mode); return }

    $route = (Invoke-DevWsl $cfg.distro @($helper, 'select', $Name, $mode) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $route) { Write-Error "Could not reach $Name. Try: $($h.commands[0]) -Check"; return }

    $wtArgs = @('--window', $(if ($Here) { '0' } else { 'new' }))
    foreach ($step in (Get-DevLayout $h.sessions)) {
        if ($wtArgs.Count -gt 2) { $wtArgs += ';' }
        switch ($step.kind) {
            'tab'   { $wtArgs += @('new-tab', '--title', $step.session) }
            'split' { $wtArgs += @('split-pane', $(if ($step.dir -eq 'right') { '-V' } else { '-H' }), '--title', $step.session) }
            'focus' { $wtArgs += @('move-focus', $step.dir) }
        }
        if ($step.kind -ne 'focus') { $wtArgs += @('wsl.exe', '-d', $cfg.distro, '--', $helper, 'pane', $route, $step.session) }
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

# Writes one Windows Terminal action + keybinding per host that has a hotkey. Old devhost entries are replaced.
function Update-DevHostTerminal($cfg) {
    $wtFile = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path $wtFile)) { Write-Warning 'Windows Terminal settings not found; hotkeys skipped.'; return }
    try { $wt = Get-Content $wtFile -Raw | ConvertFrom-Json }
    catch { Write-Warning "Could not parse Terminal settings (comments?). Hotkeys skipped: $($_.Exception.Message)"; return }

    $actions = @($wt.actions | Where-Object { $_ -and "$($_.id)" -notlike 'User.devhost.*' })
    $keys = @($wt.keybindings | Where-Object { $_ -and "$($_.id)" -notlike 'User.devhost.*' })
    foreach ($h in $cfg.hosts) {
        if (-not $h.hotkey) { continue }
        $clash = $keys | Where-Object keys -eq $h.hotkey
        if ($clash) { Write-Warning "$($h.hotkey) is already used by $($clash.id); not binding $($h.name)."; continue }
        $sub = @()
        foreach ($step in (Get-DevLayout $h.sessions)) {
            $cmd = "wsl.exe -d $($cfg.distro) -- $($cfg.helper) attach $($h.name) $($step.session)"
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

function Read-Default([string]$Prompt, [string]$Default) {
    $suffix = if ($Default) { " [$Default]" } else { '' }
    $v = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($v)) { $Default } else { $v.Trim() }
}

function Add-DevHost {
    $cfg = Get-DevHostConfig
    Write-Host "`nNew SSH workspace host. Enter keeps the [default].`n" -ForegroundColor Cyan

    do { $name = (Read-Default 'Short name (e.g. hal)' '').ToLowerInvariant() } until ($name -match '^[a-z0-9][a-z0-9_-]*$')
    $old = $cfg.hosts | Where-Object name -eq $name | Select-Object -First 1

    $helper = Install-DevConnect $cfg
    $routes = @(Invoke-DevWsl $cfg.distro @($helper, 'routes', $name))
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

        # Key: one ed25519 key inside WSL. No passphrase keeps the 4 panes from prompting (BatchMode).
        Invoke-DevWsl $cfg.distro @('sh', '-c', 'test -f ~/.ssh/id_ed25519') | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Creating an SSH key in WSL (just press Enter for no passphrase)...'
            $comment = ("$($env:USERNAME)@$($env:COMPUTERNAME)" -replace '[^\w@.-]', '')
            Invoke-DevWsl $cfg.distro @('sh', '-c', 'mkdir -p $HOME/.ssh && chmod 700 $HOME/.ssh && ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519 -C $1', 'sh', $comment)
        }

        $first = if ($lan) { $lan } else { $tail }
        Write-Host "Copying your public key to $user@$first (enter your password for that machine once)..."
        Invoke-DevWsl $cfg.distro @('sh', '-c', 'ssh-copy-id -i $HOME/.ssh/id_ed25519.pub -p $1 -o HostKeyAlias=$2 -o StrictHostKeyChecking=accept-new $3',
            'sh', $port, $name, "$user@$first")
        if ($LASTEXITCODE -ne 0) { Write-Warning 'ssh-copy-id failed. Check the address/user; you can re-run devhost add.' }

        Invoke-DevWsl $cfg.distro @($helper, 'add-host', $name, $user, $port, $(if ($lan) { $lan } else { '-' }), $(if ($tail) { $tail } else { '-' }))   # '-' = none (empty args get dropped)
    }

    Write-Host 'Testing routes...'
    Invoke-DevWsl $cfg.distro @($helper, 'check', $name, 'auto')
    Invoke-DevWsl $cfg.distro @($helper, 'has-tmux', $name) | Out-Null
    if ($LASTEXITCODE -eq 1) {
        if ((Read-Default 'tmux is not installed on the host. Install it now with sudo? (Y/n)' 'y') -match '^[yY]') {
            $route = (Invoke-DevWsl $cfg.distro @($helper, 'select', $name, 'auto') | Out-String).Trim()
            Invoke-DevWsl $cfg.distro @('ssh', '-tt', '-o', 'BatchMode=no', $route,
                'sudo apt-get install -y tmux || sudo dnf install -y tmux || sudo pacman -S --noconfirm tmux || brew install tmux')
        }
    }

    # Commands and hotkey
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
        'check'  {
            $cfg = Get-DevHostConfig; $helper = Install-DevConnect $cfg
            foreach ($h in ($cfg.hosts | Where-Object { -not $Name -or $_.name -eq $Name })) { Write-Host "-- $($h.name)"; Invoke-DevWsl $cfg.distro @($helper, 'check', $h.name, 'auto') }
        }
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
