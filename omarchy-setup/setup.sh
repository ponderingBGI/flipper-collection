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
# restart into Windows once; power-on and restarts from Omarchy stay in Omarchy
if command -v gum >/dev/null 2>&1; then
  gum confirm --default=true "Restart into Windows now? Save your work first." || exit 0
else
  printf 'Restart into Windows now? Save your work first. [Y/n] '; read -r a
  case "$a" in n|N) exit 0;; esac
fi
sudo /usr/local/bin/reboot-to-windows
SH
chmod +x "$BIN/windows"

say "Launcher entry 'Windows' (SUPER+SPACE, type windows)"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/windows-reboot.desktop" <<DESK
[Desktop Entry]
Name=Windows
Comment=Restart into Windows
Exec=xdg-terminal-exec --app-id=dualboot.windows $BIN/windows
Icon=computer
Terminal=false
Type=Application
Categories=System;
DESK

say "Hotkey SUPER+ALT+W -> restart into Windows (asks first, small floating window)"
HB="$HOME/.config/hypr/bindings.conf"
if [ -f "$HB" ] && ! grep -q 'reboot into Windows' "$HB"; then
  printf '\n# reboot into Windows (asks first)\nbind = SUPER ALT, W, exec, xdg-terminal-exec --app-id=dualboot.windows %s/windows\n' "$BIN" >> "$HB"
fi
HW="$HOME/.config/hypr/windows.conf"; [ -f "$HW" ] || HW="$HOME/.config/hypr/hyprland.conf"
if [ -f "$HW" ] && ! grep -q 'dualboot.windows' "$HW"; then
  printf '\nwindowrule = float, class:dualboot.windows\nwindowrule = size 560 180, class:dualboot.windows\nwindowrule = center, class:dualboot.windows\n' >> "$HW"
fi

say "Keep Omarchy first in the boot order (Windows updates sometimes put themselves first)"
sudo install -m 755 /dev/stdin /usr/local/bin/keep-limine-first <<'SH'
#!/bin/sh
# Put the Limine/Omarchy entry back at the front of BootOrder if something moved it. Leaves BootNext alone.
l=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\? *\(Limine\|Omarchy\).*/\1/p' | head -1)
[ -n "$l" ] || exit 0
order=$(efibootmgr | sed -n 's/^BootOrder: //p')
case "$order" in "$l"*) exit 0;; esac
rest=$(echo "$order" | tr ',' '\n' | grep -vix "$l" | paste -sd, -)
efibootmgr -o "$l${rest:+,$rest}" >/dev/null && logger -t keep-limine-first "BootOrder fixed: $l first (was $order)"
SH
sudo tee /etc/systemd/system/keep-limine-first.service >/dev/null <<'UNIT'
[Unit]
Description=Keep Limine/Omarchy first in the UEFI boot order
[Service]
Type=oneshot
ExecStart=/usr/local/bin/keep-limine-first
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload; sudo systemctl enable --now keep-limine-first.service >/dev/null 2>&1 || true

say "Boot menu: 1 second, so Esc/arrows still reach Windows if a switch ever fails"
LC=$(ls /boot/limine.conf /boot/EFI/limine/limine.conf /boot/limine/limine.conf 2>/dev/null | head -1)
if [ -n "$LC" ]; then
  if grep -qE '^\s*timeout:' "$LC"; then sudo sed -i -E 's/^(\s*timeout:).*/\1 1/' "$LC"; else echo 'timeout: 1' | sudo tee -a "$LC" >/dev/null; fi
  grep -qi 'bootmgfw.efi\|windows' "$LC" || echo "    No Windows entry in $LC yet: run 'sudo limine-scan' once and add Windows Boot Manager"
fi

say "Windows C: at /mnt/windows, READ-ONLY (Windows hibernates when switching; writing to a hibernated NTFS would corrupt it)"
WIN=$(lsblk -bnro UUID,FSTYPE,SIZE | awk '$2=="ntfs"' | sort -k3 -n | tail -1 | cut -d' ' -f1)
if [ -n "$WIN" ] && ! grep -q "$WIN" /etc/fstab; then
  sudo mkdir -p /mnt/windows
  echo "UUID=$WIN /mnt/windows ntfs3 ro,uid=$(id -u),gid=$(id -g),windows_names,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=120 0 0" | sudo tee -a /etc/fstab >/dev/null
  sudo systemctl daemon-reload
  ln -sfn /mnt/windows/Users "$HOME/Windows"
  echo "    ~/Windows -> your Windows user folders"
elif [ -z "$WIN" ]; then echo "    no NTFS partition found"; else echo "    already in /etc/fstab"; fi

say "Zen: install it and bring over your Windows profile (tabs, workspaces, logins, extensions)"
command -v zen-browser >/dev/null 2>&1 || command -v zen >/dev/null 2>&1 || yay -S --needed --noconfirm zen-browser-bin >/dev/null 2>&1 || echo "    couldn't install zen-browser-bin from the AUR, install it by hand"
cat > "$BIN/zen-import" <<'SH'
#!/bin/bash
# Copy Zen's default profile from the Windows partition into ~/.zen. Close Zen on both sides first.
set -euo pipefail
ls /mnt/windows/Users >/dev/null 2>&1 || { echo "Windows partition not mounted at /mnt/windows"; exit 1; }
src=""
for u in /mnt/windows/Users/*/AppData/Roaming/zen; do [ -f "$u/profiles.ini" ] && src="$u" && break; done
[ -n "$src" ] || { echo "No Zen profile found on Windows"; exit 1; }
# the profile Windows Zen actually uses: [Install...] Default=, else the Default=1 profile
rel=$(awk -F= '/^\[Install/{i=1} i&&/^Default=/{print $2; exit}' "$src/profiles.ini" | tr -d '\r')
[ -n "$rel" ] || rel=$(awk -F= '/^Path=/{p=$2} /^Default=1/{print p; exit}' "$src/profiles.ini" | tr -d '\r')
name=$(basename "$rel")
pgrep -x zen >/dev/null 2>&1 || pgrep -f zen-browser >/dev/null 2>&1 && { echo "Close Zen first"; exit 1; }
dest="$HOME/.zen/$name"
[ -e "$dest" ] && mv "$dest" "$dest.before-import-$(date +%s)"
mkdir -p "$HOME/.zen"
echo "Copying $src/$rel ($(du -sh "$src/$rel" | cut -f1)) ..."
cp -a "$src/$rel" "$dest"
# Windows-only leftovers: Zen rebuilds these on first start
rm -f "$dest"/{parent.lock,lock,compatibility.ini,pluginreg.dat} 
rm -rf "$dest/startupCache"
[ -f "$HOME/.zen/profiles.ini" ] && cp "$HOME/.zen/profiles.ini" "$HOME/.zen/profiles.ini.bak"
cat > "$HOME/.zen/profiles.ini" <<INI
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=default
IsRelative=1
Path=$name
Default=1
INI
rm -f "$HOME/.zen/installs.ini"
echo "Done. Start Zen: your tabs, workspaces, logins and extensions are there."
SH
chmod +x "$BIN/zen-import"
if [ -d /mnt/windows/Users ] || ls /mnt/windows/Users >/dev/null 2>&1; then
  if [ ! -d "$HOME/.zen" ] || ! ls "$HOME"/.zen/*/places.sqlite >/dev/null 2>&1; then "$BIN/zen-import" || true; else echo "    ~/.zen already has a profile, run 'zen-import' to replace it"; fi
fi

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
  windows        restart into Windows once (SUPER+ALT+W, or 'Windows' in the launcher)
  ~/Windows      your Windows files (C:\Users)
  devhost add    set up Hal (SSH key, routes, tmux panes, your commands)
  bt-sync        share Bluetooth pairings with Windows
  zen-import     copy Zen's profile from Windows again (close Zen on both first)
  Syncthing      http://127.0.0.1:8384 - add this PC to your phone for the Obsidian vault
Open a new terminal to pick up the commands.
TXT
