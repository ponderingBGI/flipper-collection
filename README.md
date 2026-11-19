# Flipper Collection

Personal Flipper Zero scripts and apps - quick & dirty solutions I built for myself. Use, modify, or improve as you like.

## Apps
- apps/mouse-jiggler: Mouse and keyboard Jiggler
  - See: apps/mouse-jiggler/README.md

## Bad USB Scripts
- MSConfig Safe Boot Enable
  - See: packages/badusb/msconfig-safe-boot.txt and packages/badusb/README.md
  - Script discovered in a Pierogi Scammer Payback video
  - Tested and verified working on Windows 10
- **windows-setup**: plug in a fresh Windows PC and get my whole setup (no OneDrive, debloated, apps, oh-my-posh, terminal, WSL)
  - See: packages/badusb/windows-setup.txt and windows-setup/README.md

## Downloads
- Packaged apps ready to drag onto your Flipper: downloads/

## Packages (auto-updated on main)
- Apps (Tools): packages/apps/Tools/
- Sub-GHz: packages/subghz/
- BadUSB: packages/badusb/
- NFC: packages/nfc/

See DEVELOPMENT.md for the build/test workflow.
Pipeline is provided via `make test`.
