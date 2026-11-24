# BadUSB payloads

Copy the desired `.txt` files to the Flipper microSD's `badusb` folder using qFlipper. On the Flipper, open **Bad USB**, select a payload, and set the keyboard layout to match the target PC. Connect to a signed-in computer you administer. Keep the desktop and terminal ready and watch for prompts.

- [Windows setup](windows-setup.txt) opens visible PowerShell and verifies the pinned ZIP by SHA256. Answer the prompt to launch administrator setup, approve UAC yourself, review the setup prompt, and decide separately whether to restart. See [Windows setup](../../setup/windows/README.md) for manual use and options.
- [Omarchy setup](omarchy-setup.txt) types into an existing Bash terminal on the signed-in Omarchy desktop. Open and focus the terminal before pressing Run on the Flipper. The payload verifies the pinned tarball by SHA256, then lets you select the optional tools or the Omarchy side of the dual-boot switch setup. It needs `curl`, `sha256sum`, `tar` and internet access. Setup asks for confirmation and sudo as needed. See [Omarchy setup](../../setup/omarchy/README.md) and [dual boot](../../setup/dualboot/README.md) for manual commands.
- [MSConfig Safe Boot](msconfig-safe-boot.txt) is a legacy Windows 10 payload. It changes the next boot to Safe Mode. To undo it, open System Configuration, go to **Boot**, clear **Safe boot**, and restart normally.

Both setup payloads print a download or hash error and stop on failure. They extract to a fresh temporary folder. You can remove that folder after setup exits.

## Update the pins

1. Publish the reviewed setup changes first. Copy the full 40-character commit ID.
2. Download that exact commit from `https://codeload.github.com/ponderingBGI/flipper-collection/zip/<commit>` and `https://codeload.github.com/ponderingBGI/flipper-collection/tar.gz/<commit>`. Inspect the archive contents against the reviewed commit.
3. Compute SHA256 of the ZIP and tarball separately with `Get-FileHash -Algorithm SHA256` or `sha256sum`. Update the pin and matching archive hash in both payloads. Run with an intentionally wrong hash to verify that extraction and execution stop, then restore the verified hashes.
4. Test with the target keyboard layout on a machine you administer, commit the pin update, and replace the payload files on the Flipper. If the same archive URL ever serves different bytes, investigate and reverify the source before updating any hash.
