# Windows + Omarchy dual boot

Use a UEFI/GPT PC with Windows already installed, an Omarchy installer USB, administrator access on Windows and sudo on Omarchy. Back up your files, save the Windows recovery key outside the PC and have recovery media available. Check your firmware and Secure Boot requirements against the Omarchy installer guide. Disconnect disks you do not intend to use.

## 1. Prepare Windows

From an administrator Windows PowerShell at the repository root:

```powershell
.\setup\dualboot\prepare-omarchy.ps1 -OmarchyGB 100 -DryRun
.\setup\dualboot\prepare-omarchy.ps1 -OmarchyGB 100
```

Choose a space budget in GiB. The script asks separately before resizing C:, turning off Fast Startup while enabling full hibernation, changing the hardware clock convention to UTC, and turning off BitLocker. Use `-KeepEncryption` to skip the decryption step if handling it yourself. The shared-disk installer requires the Windows partition to be fully decrypted. Verify with `manage-bde -status C:` and confirm the unallocated extent in Disk Management. See the [shrink and GParted guide](shrink/README.md) if Windows cannot make room.

## 2. Install Omarchy

Shut down Windows normally. Boot the Omarchy installer USB, select the verified disk and choose **Free space install**. Review the destination before confirming. Once installed, use `sudo limine-scan` if you want Windows Boot Manager in the Limine menu. Verify both operating systems boot from the firmware menu before installing the switch helpers. [Omarchy dual-boot manual](https://learn.omacom.io/2/the-omarchy-manual/120/dual-boot-install)

## 3. Install and use the switch helpers

- **Windows**. Run `.\setup\dualboot\windows\install-dualboot.ps1 -DryRun` and then rerun without the flag in an administrator Windows PowerShell. This installs tasks, copies helpers to Program Files and adds the Omarchy shortcut and Ctrl+Alt+O. For the shell command, dot-source `$HOME\.config\dualboot\DualBoot.ps1` then run `omarchy`. Confirm the prompt. Windows sets the one-time firmware boot target and hibernates.
- **Omarchy**. Run `bash setup/dualboot/setup-omarchy.sh --dry-run` and then rerun without the flag. It installs the `windows` command and launcher entry. Enable and test local hibernation first in Omarchy's system settings. Run `~/.local/bin/windows`, confirm, and enter your sudo password to set the one-time firmware target. The default hibernates Omarchy. Use `windows --restart` explicitly for a normal reboot when you do not need the session. [Omarchy system sleep](https://learn.omacom.io/2/the-omarchy-manual/103/system-sleep)
- When hibernation powers the computer off, press the power button to boot the other OS. Use its switch command or the firmware menu to return and resume. One-time boot behavior depends on firmware. Save open work and eject shared USB drives manually before switching.

To read Windows files in Omarchy, identify the Windows NTFS volume with `lsblk -f`, then run the Omarchy switch installer with `--windows-uuid=<UUID>`. It adds a read-only automount at `/mnt/windows`. Never write to a disk shared with a hibernated system. The old optional Zen and Bluetooth integration source is retained in [legacy-integrations.txt](legacy-integrations.txt) for review. Bluetooth registry sync requires a fully shut-down Windows system and a writable mount, so it is outside this read-only workflow.

Run the disk and boot commands manually so you can review the target at each step. The Flipper [Windows setup payload](../../packages/badusb/README.md) is available for the separate Windows app setup.

## Undo

Remove both `DualBoot-*` tasks using Task Scheduler, remove the Omarchy shortcuts and remove `DualBoot` under Program Files and `~/.config/dualboot` on Windows. Set the preferred default in firmware. On Omarchy remove `~/.local/bin/windows` and `~/.local/share/applications/windows-reboot.desktop`. If you configured the mount, stop `mnt-windows.automount` and `mnt-windows.mount`, remove the matching fstab entry and run `sudo systemctl daemon-reload`. Restore clock, hibernation, Fast Startup and encryption preferences separately. Removing Omarchy partitions and extending C: is a separate disk operation. Verify partition identities and backups before changing the layout again.
