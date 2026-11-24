#!/usr/bin/env bash
set -euo pipefail

dry=false
sync=false
dev=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry=true ;;
        --syncthing) sync=true ;;
        --dev-hosts) dev=true ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done
if ! "$sync" && ! "$dev"; then
    printf 'Select --syncthing, --dev-hosts, or both. Use --dry-run to preview.\n'
    exit 0
fi
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
bin="$HOME/.local/bin"
if "$sync"; then printf '==> Install Syncthing and enable its user service\n'; fi
if "$dev"; then printf '==> Install OpenSSH, tmux and the optional devhost wizard\n'; fi
if "$dry"; then exit 0; fi
read -r -p 'Apply these changes? [y/N] ' answer
case "$answer" in y|Y|yes|YES) ;; *) exit 0 ;; esac

if "$sync"; then
    sudo pacman -S --needed syncthing
    systemctl --user enable --now syncthing.service
fi
if "$dev"; then
    sudo pacman -S --needed openssh tmux
    mkdir -p "$bin" "$HOME/.config/dev-hosts"
    install -m 755 "$root/devhost" "$root/dev-connect" "$bin"
    grep -Fq 'dev-hosts/aliases.sh' "$HOME/.bashrc" 2>/dev/null ||
        printf '\n[ -f ~/.config/dev-hosts/aliases.sh ] && . ~/.config/dev-hosts/aliases.sh\n' >> "$HOME/.bashrc"
    touch "$HOME/.config/dev-hosts/aliases.sh"
    printf 'Open a new terminal, then run devhost add.\n'
fi
