#!/usr/bin/env bash
# uninstall.sh - turn off automatic backups. Your existing backups on the drive are NOT touched.
set -e
[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo:  sudo ./uninstall.sh"; exit 1; }
systemctl disable --now restic-auto-backup.timer 2>/dev/null || true
rm -f /etc/systemd/system/restic-auto-backup.service /etc/systemd/system/restic-auto-backup.timer
rm -f /usr/local/bin/restic-auto-backup
systemctl daemon-reload
echo "Automatic backups are off. Your backups on the drive are untouched."
echo "The saved password and settings are still in /etc/restic-auto-backup (delete that folder if you want)."
