# Bad USB scripts

## windows-setup.txt

Turns a fresh Windows PC into my setup: plug in, run, walk away.

It opens an elevated PowerShell and runs [`windows-setup/go.ps1`](../../windows-setup), which downloads this repo and runs `setup.ps1`. Everything it does is described in the [windows-setup README](../../windows-setup/README.md).

**Before you run it**
- Be signed in at the desktop and online.
- Set the Flipper's keyboard layout (Bad USB → ⚙ → Keyboard layout) to the PC's layout. A US install needs `en-US`, a Swiss one `de-CH`. With the wrong layout, `|` and `:` type as other characters and the command fails.
- The account must be an admin. If it's a standard user, UAC asks for an admin password and the Flipper can't type it, so type it yourself.

If nothing happens, open PowerShell and paste the command from the windows-setup README.

## msconfig-safe-boot.txt

### What it does

This Bad USB script enables Safe Boot mode in Windows through msconfig. After running it, the computer will boot into Safe Mode on the next restart.

### Origin Story

I made this script years ago after a scammer tried to activate this mode in a Scammer Payback video from Pierogi.

### Tested on

Windows 10 2020

### Warning

My stupid old me did it on my main machine and was able to disable it and nothing seamed to be broken but dont take that as a guaratie. it might very well break something.

### Usage

Put this on your Flipper Zero in the badusb folder and run it when connected to a Windows machine.
