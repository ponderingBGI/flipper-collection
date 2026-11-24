# Windows setup

Use this on a signed-in Windows 10 or 11 PC with Windows PowerShell 5.1, administrator access and internet connectivity. The default installs Git, Windows Terminal and 7-Zip using UniGetUI with a winget fallback. The default leaves OneDrive, device encryption, Fast Startup and Windows settings alone. For dual boot preparation use the [separate guide](../dualboot/README.md).

## Run manually

1. Download and extract the repository, or use a local clone. Keep the full `setup/windows` directory together.
2. Open **Windows PowerShell** as administrator from the account you want to configure. Change to the repository root.
3. Preview the run, then apply it.

   ```powershell
   .\setup\windows\setup.ps1 -DryRun
   .\setup\windows\setup.ps1
   ```

   If local script policy blocks a downloaded ZIP that you have reviewed, unblock the extracted files or use a process-scoped policy for this run. Live setup asks before making changes and again before restarting. Logs are under `%SystemDrive%\Setup`.

## Run from Flipper

Copy [windows-setup.txt](../../packages/badusb/windows-setup.txt) to the Flipper microSD's `badusb` folder with qFlipper. Follow the [BadUSB instructions](../../packages/badusb/README.md). The launcher runs the default setup after verifying a pinned archive.

## Options and undo

| Option | What it changes | Undo |
|---|---|---|
| `-AppsConfig .\setup\windows\apps.json`, `-Groups core,dev`, `-SkipApps` | Select an app catalog, limit package groups, or skip installs. Copy and edit a JSON catalog for your machine. The larger catalog is optional. | Uninstall apps through UniGetUI or Settings. Remove the UniGetUI startup entry if unwanted. |
| `-RemoveOneDrive` | Copies known-folder contents locally, switches folder paths, and uninstalls and blocks OneDrive. Existing source files are retained. Download cloud-only files and review your backup first. | Remove the OneDrive policies set by the script, reinstall OneDrive and re-enable folder backup in its settings. Restore folder paths from your backup if needed. |
| `-Debloat` | Removes selected bundled apps, applies Windows policies and optionally blocks driver-delivered software from the catalog. Driver removal asks separately. | Restore policies and affected apps from backup or reinstall them. See [block-bloat.ps1](block-bloat.ps1) for device-ID policy and driver export location. |
| `-ApplySettings` | Applies Explorer, taskbar, dark mode, keyboard and power preferences. | Restore previous registry and power settings or use a verified system backup. |
| `-InstallDotfiles` | Installs the terminal and shell templates, SSH workstation wizard, theme and fonts. The Git template is used only where no Git config exists. | Restore the `.bak` copies for existing profiles and Terminal settings. Remove newly installed templates and fonts as needed. |
| `-InstallWsl` | Installs Ubuntu 24.04 via WSL. | Back up the distribution, then uninstall it and remove WSL if desired. |
| `-ScreenshotsTarget <directory>` | Makes a screenshot directory symlink to a directory you supply. Move an existing screenshot folder aside first. | Remove the symlink and restore the original folder. |

`-WhatIf` is an alias for `-DryRun`. A rerun reapplies selected settings and can retry incomplete installs. Review existing configuration before selecting dotfiles again.
