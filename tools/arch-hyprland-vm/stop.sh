#!/usr/bin/env bash
# Stop Arch Hyprland VM gracefully via QEMU monitor, then SIGTERM/SIGKILL.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$DIR/qemu.pid"
MONITOR="$DIR/qemu-monitor.sock"

if [[ ! -f "$PIDFILE" ]]; then
  echo "No pidfile; trying pkill fallback"
  pkill -f 'qemu-system-x86_64 -name arch-hyprland' 2>/dev/null || true
  exit 0
fi
pid="$(cat "$PIDFILE")"
if ! kill -0 "$pid" 2>/dev/null; then
  echo "Stale pidfile (pid $pid not running); cleaning up"
  rm -f "$PIDFILE" "$MONITOR"
  exit 0
fi

echo "Sending system_powerdown to QEMU monitor..."
if [[ -S "$MONITOR" ]]; then
  printf 'system_powerdown\n' | socat - UNIX-CONNECT:"$MONITOR" 2>/dev/null || true
fi

for i in $(seq 1 30); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "VM stopped cleanly"
    rm -f "$PIDFILE" "$MONITOR"
    exit 0
  fi
  sleep 1
done

echo "Force terminating pid $pid"
kill "$pid" 2>/dev/null || true
sleep 2
kill -9 "$pid" 2>/dev/null || true
rm -f "$PIDFILE" "$MONITOR"
echo "VM killed"
