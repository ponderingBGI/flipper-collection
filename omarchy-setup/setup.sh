#!/usr/bin/env bash
# Omarchy side of the Windows + Omarchy dual boot. Run once after installing Omarchy:
#   curl -fsSL https://raw.githubusercontent.com/PonderingAI/flipper-collection/main/omarchy-setup/setup.sh | bash
# Safe to run again.
set -euo pipefail
RAW=https://raw.githubusercontent.com/PonderingAI/flipper-collection/main
BIN="$HOME/.local/bin"
mkdir -p "$BIN" "$HOME/.config/dev-hosts"
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

say "Packages"
sudo pacman -S --needed --noconfirm efibootmgr ntfs-3g syncthing uv openssh tmux >/dev/null
systemctl --user enable --now syncthing.service >/dev/null 2>&1 || true

say "'windows' command: restart into Windows once"
sudo install -m 755 /dev/stdin /usr/local/bin/reboot-to-windows <<'SH'
#!/bin/sh
# one-time boot into Windows Boot Manager, then normal order again
n=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\? *Windows Boot Manager.*/\1/p' | head -1)
[ -n "$n" ] || { echo "No 'Windows Boot Manager' entry found (efibootmgr)"; exit 1; }
efibootmgr --bootnext "$n" >/dev/null && systemctl reboot
SH
echo "$USER ALL=(root) NOPASSWD: /usr/local/bin/reboot-to-windows" | sudo tee /etc/sudoers.d/reboot-to-windows >/dev/null
sudo chmod 440 /etc/sudoers.d/reboot-to-windows
cat > "$BIN/windows" <<'SH'
#!/bin/sh
printf 'Restart into Windows now? Save your work first. [Y/n] '; read -r a
case "$a" in n|N) exit 0;; esac
sudo /usr/local/bin/reboot-to-windows
SH
chmod +x "$BIN/windows"

say "Hotkey SUPER+ALT+W -> restart into Windows (asks first)"
HB="$HOME/.config/hypr/bindings.conf"
if [ -f "$HB" ] && ! grep -q 'reboot into Windows' "$HB"; then
  printf '\n# reboot into Windows (asks first)\nbind = SUPER ALT, W, exec, xdg-terminal-exec %s/windows\n' "$BIN" >> "$HB"
fi

say "Windows C: at /mnt/windows (mounted on first access)"
WIN=$(lsblk -bnro UUID,FSTYPE,SIZE | awk '$2=="ntfs"' | sort -k3 -n | tail -1 | cut -d' ' -f1)
if [ -n "$WIN" ] && ! grep -q "$WIN" /etc/fstab; then
  sudo mkdir -p /mnt/windows
  echo "UUID=$WIN /mnt/windows ntfs3 rw,uid=$(id -u),gid=$(id -g),windows_names,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=120 0 0" | sudo tee -a /etc/fstab >/dev/null
  sudo systemctl daemon-reload
  ln -sfn /mnt/windows/Users "$HOME/Windows"
  echo "    ~/Windows -> your Windows user folders"
elif [ -z "$WIN" ]; then echo "    no NTFS partition found"; else echo "    already in /etc/fstab"; fi

say "Bluetooth: 'bt-sync' copies pairings to Windows so devices work in both"
cat > "$BIN/bt-sync" <<'SH'
#!/bin/sh
# Pair the device in Windows first, then here, then run this (backs up the Windows registry first).
ls /mnt/windows/Windows >/dev/null 2>&1 || { echo "Windows partition not mounted at /mnt/windows"; exit 1; }
sudo uvx --from bt-dualboot bt-dualboot --win /mnt/windows --sync-all -b
SH
chmod +x "$BIN/bt-sync"

say "devhost (same as on Windows: devhost add / list / check, then your own commands)"
curl -fsSL "$RAW/windows-setup/dotfiles/dev-hosts/dev-connect" -o "$BIN/dev-connect" && chmod +x "$BIN/dev-connect"
curl -fsSL "$RAW/omarchy-setup/devhost" -o "$BIN/devhost" && chmod +x "$BIN/devhost"
grep -q 'dev-hosts/aliases.sh' "$HOME/.bashrc" 2>/dev/null || \
  printf '\n# devhost commands (dev etc.)\n[ -f ~/.config/dev-hosts/aliases.sh ] && . ~/.config/dev-hosts/aliases.sh\n' >> "$HOME/.bashrc"
touch "$HOME/.config/dev-hosts/aliases.sh"

say "Done"
cat <<TXT
  windows        restart into Windows once (or SUPER+ALT+W)
  ~/Windows      your Windows files (C:\Users)
  devhost add    set up Hal (SSH key, routes, tmux panes, your commands)
  bt-sync        share Bluetooth pairings with Windows
  Syncthing      http://127.0.0.1:8384 - add this PC to your phone for the Obsidian vault
Open a new terminal to pick up the commands.
TXT
