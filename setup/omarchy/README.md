# Omarchy setup

Install Omarchy from its [official ISO and installation guide](https://learn.omacom.io/books/2/pages/50), then sign in to your new desktop. This repository's script adds optional tools to an existing installation. It needs internet access for packages and a user who can run `sudo`. It leaves disks and boot settings alone. For BitLocker, Fast Startup or Windows switching, see [dual boot](../dualboot/README.md).

From the root of an extracted repository or clone:

```sh
bash setup/omarchy/setup.sh --syncthing --dev-hosts --dry-run
bash setup/omarchy/setup.sh --syncthing --dev-hosts
```

Select either or both options. `--syncthing` installs Syncthing and enables its user service. `--dev-hosts` installs OpenSSH, tmux and local helper commands. Open a new terminal and run `devhost add` to set your own SSH host, login, routes and commands. The script asks before applying changes and can be rerun.


To undo, disable Syncthing with `systemctl --user disable --now syncthing.service`. Remove `~/.local/bin/devhost`, `~/.local/bin/dev-connect` and the aliases line in `~/.bashrc` to remove the wizard. Keep your SSH keys and user data unless you intentionally want to delete them. Remove unused packages through pacman.

For BadUSB, copy [omarchy-setup.txt](../../packages/badusb/omarchy-setup.txt) to the Flipper and select the Omarchy tools option. [Loading instructions](../../packages/badusb/README.md)
