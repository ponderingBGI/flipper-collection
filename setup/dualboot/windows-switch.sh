#!/usr/bin/env sh
set -eu
mode=hibernate
case "${1:-}" in
    '') ;;
    --restart) mode=reboot ;;
    --dry-run) printf 'Would set Windows Boot Manager as the next boot and hibernate Omarchy.\n'; exit 0 ;;
    *) printf 'Usage: windows [--restart|--dry-run]\n' >&2; exit 2 ;;
esac
entries=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\? *Windows Boot Manager.*/\1/p')
case "$entries" in
    ???? ) ;;
    *) printf 'Expected exactly one Windows Boot Manager entry. Check efibootmgr.\n' >&2; exit 1 ;;
esac
printf 'Switch to Windows (%s)? Save your work and eject shared USB disks first. [y/N] ' "$mode"
read -r answer
case "$answer" in y|Y|yes|YES) ;; *) exit 0 ;; esac
sudo efibootmgr --bootnext "$entries"
if ! systemctl "$mode"; then
    sudo efibootmgr --delete-bootnext
    exit 1
fi
