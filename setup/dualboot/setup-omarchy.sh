#!/usr/bin/env bash
set -euo pipefail

dry=false
win_uuid=''
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry=true ;;
        --windows-uuid=*) win_uuid=${arg#*=} ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
bin="$HOME/.local/bin"
printf '==> Install Windows switch command and launcher\n'
if [ -n "$win_uuid" ]; then printf '==> Mount NTFS UUID %s read-only at /mnt/windows\n' "$win_uuid"; fi
if "$dry"; then exit 0; fi
[ -d /sys/firmware/efi ] || { echo 'Boot Omarchy in UEFI mode first.' >&2; exit 1; }
if [ -n "$win_uuid" ]; then
    [[ "$win_uuid" =~ ^[0-9A-Fa-f]{16}$ ]] || { echo 'Expected an NTFS UUID from lsblk -f.' >&2; exit 1; }
    device=$(readlink -e "/dev/disk/by-uuid/$win_uuid")
    [ "$(lsblk -dnro FSTYPE "$device")" = ntfs ] || { echo 'Selected UUID is not NTFS.' >&2; exit 1; }
fi
read -r -p 'Apply these changes? [y/N] ' answer
case "$answer" in y|Y|yes|YES) ;; *) exit 0 ;; esac

sudo pacman -S --needed efibootmgr
mkdir -p "$bin" "$HOME/.local/share/applications"
install -m 755 "$root/windows-switch.sh" "$bin/windows"
cat > "$HOME/.local/share/applications/windows-reboot.desktop" <<DESK
[Desktop Entry]
Name=Windows
Comment=Hibernate Omarchy and boot Windows
Exec="$bin/windows"
Icon=computer
Terminal=true
Type=Application
Categories=System;
DESK

if [ -n "$win_uuid" ]; then
    entry="UUID=$win_uuid /mnt/windows ntfs3 ro,uid=$(id -u),gid=$(id -g),windows_names,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=120 0 0"
    if ! grep -Fxq "$entry" /etc/fstab; then
        if findmnt --fstab --mountpoint /mnt/windows >/dev/null || findmnt --fstab --source "UUID=$win_uuid" >/dev/null; then
            printf 'Resolve the existing Windows mount in /etc/fstab before rerunning.\n' >&2
            exit 1
        fi
        sudo mkdir -p /mnt/windows
        sudo cp -n /etc/fstab /etc/fstab.before-flipper-dualboot
        printf '\n%s\n' "$entry" | sudo tee -a /etc/fstab >/dev/null
        sudo systemctl daemon-reload
        sudo systemctl start mnt-windows.automount
    fi
fi
printf 'Run %s/windows or open Windows from the application launcher.\n' "$bin"
