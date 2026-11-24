# Make room for Omarchy

Start with Disk Management or [prepare-omarchy.ps1](../prepare-omarchy.ps1). Leave the space unallocated. If Windows refuses to shrink C: far enough, run `shrink-diag.ps1` as administrator. It queries DiskPart and writes results, pagefile details and the last event 259 to the selected `-OutputDirectory`.

`shrink-loop.ps1 -ReclaimGB 100 -DryRun` describes the advanced operation. A live run asks before deleting restore points and temporary files and attempting to relocate blocking files and shrink C:. Use it only with a verified backup. Re-enable System Protection afterwards if you used it. Check the result in Disk Management before running any shrink command again. Windows can stop at the pagefile or NTFS metadata. Disabling paging may make a low-memory machine unstable.

## GParted Live fallback

1. Back up Windows and verify C: is fully decrypted. Complete a normal shutdown with Fast Startup off.
2. Boot a [GParted Live USB](https://gparted.org/livecd.php). Use the fallback graphics option if the default display fails.
3. Identify the Windows disk and its NTFS OS partition by size and layout. Keep the start of the partition in place and shrink from the end. Review the pending operation, then apply it and leave the new space unallocated.
4. If GParted reports NTFS metadata errors, return to Windows, run `chkdsk C: /f` as administrator and complete the requested restart before retrying. Return to Windows after resizing and verify it boots before installing Omarchy.
