#!/usr/bin/env bash
# backup.sh - automatic restic backup. Run by the systemd timer (see install.sh).
# Safe to run by hand too:  sudo /usr/local/bin/restic-auto-backup
#
# What it does each time it runs:
#   1. Skips quietly if the backup drive isn't plugged in / mounted.
#   2. Skips if the last backup is newer than MIN_HOURS (default 11, so about every 12 hours), so it
#      runs about twice a day even though the timer fires every hour.
#   3. Backs up your home folder (minus cache, trash, games) and /etc.
#   4. Cleans up old snapshots (keeps 7 daily, 4 weekly, 6 monthly).
#   5. Shows a desktop popup when a backup starts, finishes, or fails (needs notify-send, from libnotify).
#      It stays quiet when it skips. Set NOTIFY=0 in the config to turn the popups off.
set -u

CONF="${RESTIC_AUTO_CONF:-/etc/restic-auto-backup/config}"
[ -f "$CONF" ] || { echo "Config not found: $CONF (run install.sh first)"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
# Expected in the config: BACKUP_USER, BACKUP_MOUNT, REPO, PASSWORD_FILE
RESTIC="${RESTIC_BIN:-restic}"
MIN_HOURS="${MIN_HOURS:-11}"
HOME_DIR="$(getent passwd "$BACKUP_USER" | cut -d: -f6)"

# systemd runs us with no HOME set, and restic needs somewhere for its cache.
export HOME="${HOME:-/root}"
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/var/cache/restic}"
mkdir -p "$RESTIC_CACHE_DIR"

export RESTIC_REPOSITORY="$REPO"
export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"

log() { echo "[restic-auto-backup] $*"; }

# Desktop popup for the logged-in user. Never stops the backup if it can't be shown.
# Usage: notify "Title" "Message" [normal|critical]
notify() {
  [ "${NOTIFY:-1}" = "1" ] || return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  local uid; uid="$(id -u "$BACKUP_USER" 2>/dev/null)" || return 0
  [ -S "/run/user/$uid/bus" ] || return 0   # nobody logged in
  runuser -u "$BACKUP_USER" -- env "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus" \
    notify-send -a "Backup" -u "${3:-normal}" "$1" "$2" >/dev/null 2>&1 || true
}

# 1. Is the drive there?
if ! mountpoint -q "$BACKUP_MOUNT"; then
  log "Backup drive not mounted at $BACKUP_MOUNT - skipping (will try again later)."
  exit 0
fi
if [ ! -d "$REPO" ]; then
  log "Backup repository not found at $REPO - skipping."
  exit 0
fi

# 2. Was there a recent backup?
last="$($RESTIC snapshots --latest 1 --json 2>/dev/null | python3 -c '
import sys, json, re, datetime
try:
    snaps = json.load(sys.stdin)
    best = None
    for x in snaps:
        # restic times look like 2026-09-30T21:20:51.123456789-04:00 (or ...Z)
        m = re.match(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?(Z|[+-]\d\d:\d\d)?$", x["time"])
        t = datetime.datetime.fromisoformat(m.group(1) + ("+00:00" if m.group(2) in (None, "Z") else m.group(2)))
        best = t if best is None or t > best else best
    print(int((datetime.datetime.now(datetime.timezone.utc) - best).total_seconds() // 3600))
except Exception:
    print(-1)
')"
if [ "${last:--1}" -ge 0 ] && [ "$last" -lt "$MIN_HOURS" ]; then
  log "Last backup was $last hour(s) ago - nothing to do."
  exit 0
fi

# 3. Back up
log "Starting backup..."
notify "Backup started" "Please keep the backup drive plugged in until it says it's finished."
if command -v pacman >/dev/null 2>&1; then
  pacman -Qqe > "$HOME_DIR/pkglist.txt" 2>/dev/null && chown "$BACKUP_USER" "$HOME_DIR/pkglist.txt"
fi

EXCLUDES=(--exclude "$HOME_DIR/.cache" --exclude "$HOME_DIR/.local/share/Trash"
          --exclude "$HOME_DIR/.local/share/Steam" --exclude "$HOME_DIR/.steam"
          --exclude "$HOME_DIR/Games")
# Extra folders to skip can go in the config as: EXTRA_EXCLUDES=("/home/me/Videos")
for e in "${EXTRA_EXCLUDES[@]:-}"; do [ -n "$e" ] && EXCLUDES+=(--exclude "$e"); done

$RESTIC backup "$HOME_DIR" /etc "${EXCLUDES[@]}" --tag auto
rc=$?
# exit code 3 = some files couldn't be read (e.g. changed while running). The backup still exists.
if [ "$rc" -eq 3 ]; then
  log "Backup finished, but a few files couldn't be read."
elif [ "$rc" -ne 0 ]; then
  log "Backup FAILED (restic exit code $rc)."
  notify "Backup FAILED" "Something went wrong. Run: journalctl -u restic-auto-backup.service -e" critical
  exit "$rc"
fi

# 4. Tidy up old snapshots
log "Cleaning up old snapshots..."
$RESTIC forget --tag auto --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune \
  || log "Cleanup had a problem (the backup itself is fine)."

log "Done."
if [ "$rc" -eq 3 ]; then
  notify "Backup finished" "Done, but a few files couldn't be read (that's usually fine). You can unplug the drive."
else
  notify "Backup finished" "All done. You can unplug the backup drive."
fi
