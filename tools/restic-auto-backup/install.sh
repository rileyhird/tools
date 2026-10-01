#!/usr/bin/env bash
# install.sh - set up automatic daily restic backups (Arch Linux, systemd).
# Run:  sudo ./install.sh
set -e
[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo:  sudo ./install.sh"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

if ! command -v restic >/dev/null 2>&1; then
  echo "restic isn't installed. Install it first:  sudo pacman -S restic"; exit 1
fi

DEFAULT_USER="${SUDO_USER:-}"
read -r -p "Which user's home folder should be backed up? [$DEFAULT_USER] " BACKUP_USER
BACKUP_USER="${BACKUP_USER:-$DEFAULT_USER}"
id "$BACKUP_USER" >/dev/null 2>&1 || { echo "No such user: $BACKUP_USER"; exit 1; }

echo
echo "Plug in your backup drive. Mounted drives on this computer:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | grep -v -E 'loop|zram' || true
echo
read -r -p "Where is the backup drive mounted? (e.g. /run/media/$BACKUP_USER/MyDrive) " BACKUP_MOUNT
BACKUP_MOUNT="${BACKUP_MOUNT%/}"
mountpoint -q "$BACKUP_MOUNT" || { echo "$BACKUP_MOUNT is not a mounted drive. Mount it and try again."; exit 1; }

REPO="$BACKUP_MOUNT/backup"
CONF_DIR=/etc/restic-auto-backup
mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"

if [ -d "$REPO" ] && [ -e "$REPO/config" ]; then
  echo "Found an existing restic backup at $REPO - I'll use it."
  read -r -s -p "Enter that backup's password: " PW; echo
else
  echo "No backup there yet - I'll create one."
  echo "Choose a password. KEEP IT SAFE: without it the backup can't be opened."
  read -r -s -p "New password: " PW; echo
  read -r -s -p "Again: " PW2; echo
  [ "$PW" = "$PW2" ] || { echo "Passwords didn't match."; exit 1; }
fi
printf '%s' "$PW" > "$CONF_DIR/password"; chmod 600 "$CONF_DIR/password"

if [ ! -e "$REPO/config" ]; then
  restic init --repo "$REPO" --password-file "$CONF_DIR/password"
else
  restic snapshots --repo "$REPO" --password-file "$CONF_DIR/password" >/dev/null \
    || { echo "That password didn't work."; rm -f "$CONF_DIR/password"; exit 1; }
fi

cat > "$CONF_DIR/config" <<CONF
BACKUP_USER="$BACKUP_USER"
BACKUP_MOUNT="$BACKUP_MOUNT"
REPO="$REPO"
PASSWORD_FILE="$CONF_DIR/password"
# Extra folders to skip, e.g. EXTRA_EXCLUDES=("/home/$BACKUP_USER/Videos")
EXTRA_EXCLUDES=()
CONF

install -m 755 "$HERE/backup.sh" /usr/local/bin/restic-auto-backup

cat > /etc/systemd/system/restic-auto-backup.service <<'UNIT'
[Unit]
Description=Automatic restic backup

[Service]
Type=oneshot
ExecStart=/usr/local/bin/restic-auto-backup
Nice=10
IOSchedulingClass=idle
UNIT

cat > /etc/systemd/system/restic-auto-backup.timer <<'UNIT'
[Unit]
Description=Check hourly whether the automatic restic backup is due

[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now restic-auto-backup.timer

echo
echo "All set. The computer will check every hour and back up about once a day,"
echo "but only when the backup drive is plugged in."
echo
echo "Run a backup right now:      sudo systemctl start restic-auto-backup.service"
echo "See what happened:           journalctl -u restic-auto-backup.service -e"
echo "List your backups:           sudo restic -r $REPO --password-file $CONF_DIR/password snapshots"
echo "Turn it off:                 sudo ./uninstall.sh"
