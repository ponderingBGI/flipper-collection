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
| **Apps** | Repairs or bootstraps winget, then installs [`apps.json`](apps.json): 119 apps in groups `core`, `privacy-sync`, `dev`, `creative`, `comms`, `hardware`, `games` |
| **Dotfiles** | oh-my-posh theme and Nerd Fonts (Monofur, Go Mono). One PowerShell profile for both 5.1 and 7, with oh-my-posh, `dev` and `cc`. Windows Terminal settings (Catppuccin Mocha). `.gitconfig` |
| **WSL** | Ubuntu 24.04 |

At the end it lists anything that failed, plus what's left for you, and offers to reboot.

## Options

Download the repo and run `setup.ps1` directly:

```powershell
.\setup.ps1 -DryRun                    # show what would change, change nothing
.\setup.ps1 -Groups core,dev           # only these app groups
.\setup.ps1 -SkipApps                  # everything except app installs
```

To change which groups install by default, flip `"enabled"` in `apps.json`. Microsoft Store apps use the `msstore:<id>` form.

## Not covered (on purpose)

- **Sign-ins:** GitHub (`gh auth login`), Proton, Bitwarden, Syncthing pairing, Tailscale. No secrets live in this public repo.
- **The `dev-hal` helper inside WSL.** The `dev` command expects it at `~/.local/bin/dev-hal`.
- **Files:** they come back through Proton Drive and Syncthing.

Existing PowerShell profiles, Windows Terminal settings and `.gitconfig` are backed up to `*.bak` before they're overwritten.
