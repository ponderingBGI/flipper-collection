# windows-setup

One command (or one Flipper plug-in) that sets a fresh Windows 10/11 PC up the way I like it.

```powershell
irm https://raw.githubusercontent.com/PonderingAI/flipper-collection/main/windows-setup/go.ps1 | iex
```

Flipper: [`packages/badusb/windows-setup.txt`](../packages/badusb/windows-setup.txt). Its README covers the keyboard layout.

You can safely run it again. Each step checks first and skips work that's already done, so a second run only retries what failed. The log goes to `C:\Setup\windows-setup-*.log`.

## What it does

| Step | |
| --- | --- |
| **OneDrive** | Moves Desktop/Documents/Pictures back to `C:\Users\<you>` if OneDrive took them. Uninstalls OneDrive and blocks it by policy (sync client and folder backup). Removes it from Explorer and from new user accounts. Deletes the leftover `OneDrive` folder only if it's empty. |
| **Debloat** | Removes Clipchamp, Bing News/Weather, Solitaire, Teams consumer, Copilot, new Outlook, To Do and similar apps. Turns off ads, suggested and auto-installed apps, Bing in Start, Copilot, Recall and Widgets. |
| **Settings** | Dark mode, file extensions and hidden files visible, Explorer opens on This PC, no Widgets/Chat/Copilot buttons, long paths, en-US + de-CH keyboards, Romance Standard Time, High performance power plan |
| **Apps** | Installs UniGetUI first, then everything in [`apps.json`](apps.json) through it: winget, Microsoft Store, Chocolatey, npm, cargo and PowerShell modules, ~150 packages in groups. UniGetUI then starts in the tray at login and updates all of them automatically. Stability Matrix comes from its GitHub release (it updates itself). Licensed apps that no package manager has (Resolve Studio, Ableton, Topaz…) go on one page of download links. |
| **Dotfiles** | oh-my-posh theme and Nerd Fonts (Monofur, Go Mono). One PowerShell profile for both 5.1 and 7, with oh-my-posh, `devhost` and `cc`. Windows Terminal settings (Catppuccin Mocha). `.gitconfig` |
| **WSL** | Ubuntu 24.04 |
| **Screenshots** | Links `Pictures\Screenshots` to the Seafile backup library (`Backup_Laptop\images\Screenshots`) once SeaDrive is signed in |

At the end it lists anything that failed, plus what's left for you, and offers to reboot.

## devhost: SSH + tmux workspaces

`devhost add` is a wizard for a machine you SSH into. It:
- creates an SSH key in WSL if there isn't one, copies it to the machine (you type the password once) and writes `~/.ssh/config` entries for its LAN and Tailscale addresses
- checks both routes and installs tmux on the machine if it's missing
- asks which commands should open it (e.g. `dev`, or `hal` and `h`), which tmux sessions to open as panes (1–4, default `main,code,logs,misc` in a 2×2 grid) and an optional Windows Terminal hotkey (e.g. `ctrl+alt+h`)

Typing the command (or pressing the hotkey in Windows Terminal) picks LAN if it's reachable and Tailscale otherwise, then opens each pane attached to its tmux session. `dev -Check` shows the routes and how long each takes, `dev -Target Tail` forces Tailscale, `dev -Here` opens in the current Terminal window. Also: `devhost list`, `devhost check`, `devhost remove <name>`. Run `devhost add` with an existing name to change its commands, panes or hotkey.

The hosts live in `~\.config\dev-hosts\hosts.json`, not in this repo. The code is in [`dotfiles/dev-hosts`](dotfiles/dev-hosts).

## Options

Pass options through the one-liner, or download the repo and run `setup.ps1` directly:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/PonderingAI/flipper-collection/main/windows-setup/go.ps1))) -SkipApps

.\setup.ps1 -DryRun                    # show what would change, change nothing
.\setup.ps1 -Groups core,dev           # only these app groups
.\setup.ps1 -SkipApps                  # everything except app installs
```

To change which groups install by default, flip `"enabled"` in `apps.json`. Ids are winget by default; other sources use a prefix: `msstore:`, `choco:`, `npm:`, `cargo:`, `pwsh:`. The `rust-tools` group compiles from source and is the slowest. `nvidia` only installs on PCs with an NVIDIA GPU.

## Not covered (on purpose)

- **Sign-ins:** GitHub (`gh auth login`), Proton, Bitwarden, Syncthing pairing, Tailscale. No secrets live in this public repo.
- **Which SSH machines you use.** Run `devhost add` after the first reboot.
- **pip packages.** They belong to each project's environment.
- **Files:** they come back through Proton Drive and Syncthing.

Existing PowerShell profiles, Windows Terminal settings and `.gitconfig` are backed up to `*.bak` before they're overwritten.
