# windows-setup/tools

Small Windows tools written while setting up TARS (Nov 2026).

## netwatch/
Network watch built on the **built-in Windows 11 Sysmon** (optional features `Sysmon` + `Sysmon-Service`, not the Sysinternals download, which conflicts with it).
- `sysmon-netwatch.xml`: Sysmon config that logs network connections (event 3) and DNS queries (event 22).
- `netwatch.ps1`: reads those events, compares them with a baseline (`C:\ProgramData\netwatch\baseline.json`, not in git because it lists real destinations) and reports new programs/destinations. Needs admin or SYSTEM to read the Sysmon log.
- `netwatch-daily.ps1`: wrapper for the daily scheduled task (`\netwatch\netwatch daily report`, SYSTEM), writes to `C:\ProgramData\netwatch\reports`.
The first baseline is never trusted blindly: review it once, since it was built on a machine that had been infected.

## t7-to-proton/
`t7copy.ps1` copies a planned list of files (plan.csv: Src, Dst, Size) from an external drive into the Proton Drive folder in rounds (`-RoundGB`, default 60; `-KeepFreeGB`, default 40), checks every copy by SHA-256, then waits until Proton has uploaded the round (the file can be made online-only with `attrib +U -P`) before starting the next. It never touches the source and resumes safely (partial copies from an interrupted run are replaced, finished ones are re-verified by hash).

## shrink-for-dualboot/
How C: was shrunk for the Omarchy dual boot, and what we learned:
- `shrink-diag.ps1`: runs `diskpart shrink querymax` and prints the last unmovable file (Application log, event 259).
- `shrink-loop.ps1`: deletes temp files that block the shrink, relocates blocking user files (copy, verify hash, replace), deletes restore points, then shrinks as far as Windows allows. It stops at the page file and NTFS metadata.
- **Lesson:** Windows' own shrink can't move `$MFT`. Past that point, use **GParted Live** from a USB stick (boot mode: Forcevideo → `fbdev` on this laptop's GPU). If GParted reports "extra cluster in $Bitmap", run `chkdsk C: /f` in Windows first.
- Don't switch the page file off to shrink: with 16 GB RAM, Windows runs out of memory and apps crash. Keep it at 8 GB initial, 32 GB max.
