# Windows sees the drive, but there's no drive letter or I can't open it

Use this after copying data to a new drive (for example with `recover.sh` / `ddrescue`, or a clone tool) when Windows knows the drive is there but you can't get into it.

**Golden rule: do NOT format, "Initialize", or "Clean" the drive until you've tried everything below. Those wipe the copied data.**

## Step 1: Look at what Windows sees
1. Press `Win + X` and pick **Disk Management**.
2. Find the new drive (bottom half of the window, named "Disk 1", "Disk 2", etc. Match it by size).
3. Note what it says. Then jump to the matching case below.

## Case A: Disk says "Offline"
Common after a clone, because the copy has the same disk ID as the old drive ("signature collision").
1. Unplug the old/original drive if it's still connected.
2. Right-click the disk name (the grey box on the left, "Disk 1") and choose **Online**.
3. If that fails, fix the ID with diskpart (see the diskpart section below): `uniqueid disk id=12345678`.

## Case B: Partition is there but has no drive letter
1. Right-click the partition (the blue bar) and choose **Change Drive Letter and Paths**.
2. Click **Add**, pick a letter (like `E:`), and click OK.

## Case C: Says "RAW", or Windows asks you to format it
1. Do NOT click Format.
2. Open Command Prompt as Administrator and run `chkdsk E: /f` (use the right letter).
3. If it still says RAW, the partition table or file system was damaged. Use TestDisk (`testdisk`, from https://www.cgsecurity.org/) and choose **Analyse** then **Quick Search** to find the lost partition and write it back. On Linux the `extract.sh` script in `tools/drive-recovery` does this too.

## Case D: Drive opens but says "Access denied"
Windows permissions from the old computer came along with the files. Open Command Prompt as Administrator and run (change `E:` to the drive letter):
```
takeown /f E:\ /r /d y
icacls E:\ /grant Administrators:F /t
```
This can take a while on lots of files.

## Case E: Shows as "Unallocated" or "Not Initialized"
Stop here and don't initialize. This means the partition info is missing. Use TestDisk (Case C) to find the partition again, or run `extract.sh` / PhotoRec from `tools/drive-recovery` on Linux and sort the result with `tools/photorec-sorter`.

## diskpart, the command-line way
Open Command Prompt as Administrator, then type `diskpart` and press Enter.
```
list disk
select disk 1          (use YOUR disk number, check the size!)
detail disk            (shows Read-only / Offline / ID)
online disk            (if offline)
attributes disk clear readonly
uniqueid disk id=12345678   (only if signature collision, pick any new 8-digit hex)
list volume
select volume 3        (the volume with no letter)
assign letter=E
exit
```
Double-check the disk number by size before each command. `select disk` picking the wrong disk is the main risk.

## Still stuck?
Note the exact status in Disk Management (or the output of `list disk` and `detail disk`) and ask for help. Nothing above changes the file data itself.
