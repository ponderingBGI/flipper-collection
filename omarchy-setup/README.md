# omarchy-setup

Omarchy side of my Windows + Omarchy dual boot on one disk. Run once after installing Omarchy:

```bash
curl -fsSL https://raw.githubusercontent.com/PonderingAI/flipper-collection/main/omarchy-setup/setup.sh | bash
```

| | |
|---|---|
| `windows` / SUPER+ALT+W | restart into Windows once (asks first, no password) |
| `~/Windows` | Windows `C:\Users`, mounted read-write on first access (ntfs3) |
| `devhost add` | same SSH + tmux workspace wizard as on Windows: key, LAN/Tailscale routes, tmux check, your own commands (`dev`). Each tmux session opens in its own terminal and Hyprland tiles them |
| `bt-sync` | copies Bluetooth pairings into Windows ([bt-dualboot](https://github.com/x2es/bt-dualboot)) so headphones/keyboards work in both. Pair in Windows, then in Omarchy, then run it |
| Syncthing | runs as a user service; add this PC on your phone for the Obsidian vault |

On Windows the matching command is `omarchy` (from windows-setup). Before installing, run `windows-setup/prepare-omarchy.ps1` as admin: it turns off Fast Startup (so `/mnt/windows` is safe to write), keeps the clock in UTC, shrinks C: and turns off device encryption.

Windows can't read Omarchy's partition (it's LUKS-encrypted), so shared files go through `~/Windows`, git/Hal, Seafile or Syncthing.
