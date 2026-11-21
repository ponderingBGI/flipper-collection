# Used by the Windows Terminal hotkey panes: dev-attach.ps1 NAME SESSION
# Picks the reachable route (LAN first, then Tailscale; cached 2 min), then runs ssh -> tmux in this pane.
param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Session)
. (Join-Path $PSScriptRoot 'DevHosts.ps1')
try {
    $route = Select-DevRoute $Name 'auto'
    $cmd = Get-DevPaneCommand $route $Session
    & $cmd[0] $cmd[1..($cmd.Count - 1)]
} catch {
    Write-Host $_ -ForegroundColor Red
    Read-Host 'Press Enter to close'
}
