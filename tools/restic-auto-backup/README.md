# Automatic restic backups (Arch Linux)

Sets up a systemd timer that backs up your home folder and `/etc` to an external drive with restic, by itself. It checks every hour, backs up about every 12 hours, and quietly skips if the backup drive isn't plugged in.

If you already have a restic backup on the drive, the installer will reuse it.

## Set it up

1. Install restic: `sudo pacman -S restic`
2. Plug in the backup drive (ext4, btrfs or exfat, not FAT32).
3. In a terminal, go to this folder and run: `sudo ./install.sh`
   (If it says permission denied, run `chmod +x install.sh backup.sh uninstall.sh` first.)
4. Answer the questions: your user name, where the drive is mounted (usually under `/run/media/<you>/`), and a backup password. **Keep that password somewhere safe.** Without it the backup can't be opened.

## What gets backed up

- Your whole home folder, except `~/.cache`, the trash, Steam (`~/.local/share/Steam`, `~/.steam`) and `~/Games`.
- `/etc` (system settings).
- Your list of installed packages (`~/pkglist.txt`, refreshed each time).

To skip more folders, edit `/etc/restic-auto-backup/config` and fill in `EXTRA_EXCLUDES`.

Old backups are cleaned up automatically: it keeps 7 daily, 4 weekly and 6 monthly snapshots.

## Popups

You get a desktop popup when a backup starts, when it finishes (so you know it's safe to unplug the drive), and if it fails. It stays quiet when there's nothing to do. This needs `notify-send` (package `libnotify`) and a notification app such as dunst or mako. To turn popups off, add the line `NOTIFY=0` to `/etc/restic-auto-backup/config`.

## Everyday commands

| What | Command |
|------|---------|
| Back up right now | `sudo systemctl start restic-auto-backup.service` |
| See what happened | `journalctl -u restic-auto-backup.service -e` |
| Is the timer running | `systemctl list-timers restic-auto-backup.timer` |
| List your backups | `sudo restic -r /path/to/drive/backup --password-file /etc/restic-auto-backup/password snapshots` |
| Turn it off | `sudo ./uninstall.sh` (your backups on the drive are not touched) |

## Getting files back

Replace `/path/to/drive/backup` with your backup folder (for example `/run/media/riley/Backup/backup`). The password file means it won't ask you for the password.

- Everything, into a safe temp folder: `sudo restic -r /path/to/drive/backup --password-file /etc/restic-auto-backup/password restore latest --target ~/restored`
- One folder only: add `--include /home/<user>/Documents`
- List what's in the latest backup: `sudo restic -r /path/to/drive/backup --password-file /etc/restic-auto-backup/password ls latest`
- Browse it like a drive: `mkdir ~/mnt && sudo restic -r /path/to/drive/backup --password-file /etc/restic-auto-backup/password mount ~/mnt`, then look in `~/mnt/snapshots/latest` (Ctrl+C to stop)
- Full restore onto a fresh install: `--target /`

More in the [restic documentation](https://restic.readthedocs.io).

## Good to know

- The password is stored in `/etc/restic-auto-backup/password`, readable only by root. That's what lets the backup run without asking you.
- A backup on a drive that stays plugged in next to the computer won't survive a fire, theft or power surge. Keep a second copy somewhere else if the data matters.
- Tested: the backup script (backs up, skips when a recent backup exists, skips when the drive is missing, excludes cache) on a test setup using real restic. **Not yet tested:** `install.sh` and the systemd timer on a real Arch machine.
