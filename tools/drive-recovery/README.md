# Drive recovery

Two scripts for recovering data from a failing drive. Work from an image of the drive, not the drive itself. Works on Ubuntu/Debian (apt) and Arch (pacman).

## 1. Image the failing drive: `recover.sh`

```
chmod +x recover.sh extract.sh
sudo ./recover.sh
```

- Checks tool versions (dd, ddrescue, lsblk, smartctl, testdisk, photorec, fsck, ntfsfix) and offers to install what's missing.
- Asks which drive is failing and where to save the image. The save location must be on a different, healthy drive with more free space than the whole failing drive.
- Runs ddrescue: a fast pass, then 3 retries on bad areas. The `.map` file lets you stop and resume.

Arch users can install everything first with:
`sudo pacman -S --needed ddrescue smartmontools testdisk ntfs-3g`

## 2. Get files off the image: `extract.sh`

```
sudo ./extract.sh /path/to/drive.img /path/to/rescued
```

Tries in order, asking before each step:
1. Mount each partition read-only and copy files (rsync, logs unreadable files).
2. TestDisk: find lost partitions, browse and copy files.
3. PhotoRec: carve files by content. Names and folders are lost.

## Notes

- Never write to the failing drive. Never run recovery tools on it directly if it clicks or throws read errors.
  
