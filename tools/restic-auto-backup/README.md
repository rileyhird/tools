# Automatic restic backups (Arch Linux)

Sets up a systemd timer that backs up your home folder and `/etc` to an external drive with restic, by itself. It checks every hour, backs up about every 12 hours, and quietly skips if the backup drive isn't plugged in.

This is the automatic version of the manual steps in the `arch-backup-restore-with-restic` guide in the [tech-solutions](https://github.com/rileyhird/tech-solutions) repo. If you already made a backup that way, the installer will reuse it.

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

## Everyday commands

| What | Command |
|------|---------|
| Back up right now | `sudo systemctl start restic-auto-backup.service` |
| See what happened | `journalctl -u restic-auto-backup.service -e` |
| Is the timer running | `systemctl list-timers restic-auto-backup.timer` |
| List your backups | `sudo restic -r /path/to/drive/backup --password-file /etc/restic-auto-backup/password snapshots` |
| Turn it off | `sudo ./uninstall.sh` (your backups on the drive are not touched) |

To get files back, use the restore commands in the tech-solutions guide, adding `--password-file /etc/restic-auto-backup/password` after the repo path so it doesn't ask for the password.

## Good to know

- The password is stored in `/etc/restic-auto-backup/password`, readable only by root. That's what lets the backup run without asking you.
- A backup on a drive that stays plugged in next to the computer won't survive a fire, theft or power surge. Keep a second copy somewhere else if the data matters.
- Tested: the backup script (backs up, skips when a recent backup exists, skips when the drive is missing, excludes cache) on a test setup using real restic. **Not yet tested:** `install.sh` and the systemd timer on a real Arch machine.
