#!/usr/bin/env bash
# Start Arch Linux + Hyprland QEMU VM for the Hyprland bot
#
# IMPORTANT: Nested KVM on this shared box hits a kernel BUG
# (kvm_spurious_fault / kvm_arch_vcpu_create). Default ACCEL=tcg.
# To retry KVM later: ACCEL=kvm ./start.sh
#
# Ports (localhost only):
#   SSH:  127.0.0.1:2222 -> guest :22
#   VNC:  127.0.0.1:5901  (QEMU -vnc display :1)
#
# Credentials: credentials.txt (mode 600). arch-boxes default: arch / arch
#
# Idempotent: exits 0 if already running.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
DISK="$DIR/disk.qcow2"
PIDFILE="$DIR/qemu.pid"
LOG="$DIR/qemu.log"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
OVMF_VARS="$DIR/OVMF_VARS.fd"
MONITOR="$DIR/qemu-monitor.sock"
ACCEL="${ACCEL:-tcg}"

[[ -f "$DISK" ]] || { echo "Missing $DISK" >&2; exit 1; }
[[ -f "$OVMF_VARS" ]] || cp /usr/share/OVMF/OVMF_VARS_4M.fd "$OVMF_VARS"

if [[ -f "$PIDFILE" ]]; then
  oldpid="$(cat "$PIDFILE" || true)"
  if [[ -n "${oldpid:-}" ]] && kill -0 "$oldpid" 2>/dev/null; then
    echo "VM already running (pid $oldpid). SSH: ssh -p 2222 arch@127.0.0.1  VNC: 127.0.0.1:5901"
    exit 0
  fi
  rm -f "$PIDFILE"
fi
rm -f "$MONITOR"

if [[ "${RESET_OVMF_VARS:-0}" == "1" ]]; then
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$OVMF_VARS"
fi

ACCEL_ARGS=()
if [[ "$ACCEL" == "kvm" ]]; then
  if [[ ! -w /dev/kvm ]]; then
    sudo -n chmod 666 /dev/kvm 2>/dev/null || true
  fi
  MACHINE="q35,usb=off"
  ACCEL_ARGS=(-accel kvm)
  CPU_ARGS=(-cpu host)
  SMP=4
else
  # Multi-threaded TCG is much faster for boot on this host
  MACHINE="q35,usb=off"
  ACCEL_ARGS=(-accel tcg)
  CPU_ARGS=(-cpu max)
  SMP="${SMP:-2}"
fi

: > "$DIR/qemu.stdout"
: > "$DIR/qemu.stderr"
: > "$DIR/serial.log"

QEMU_BIN=$(command -v qemu-system-x86_64)

"$QEMU_BIN" \
  -name arch-hyprland \
  -machine "$MACHINE" \
  "${ACCEL_ARGS[@]}" \
  "${CPU_ARGS[@]}" \
  -smp "$SMP" \
  -m 3072 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive if=virtio,file="$DISK",format=qcow2,discard=unmap \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -device virtio-gpu-pci \
  -vnc 127.0.0.1:1 \
  -usb -device usb-tablet \
  -serial file:"$DIR/serial.log" \
  -monitor unix:"$MONITOR",server,nowait \
  -pidfile "$PIDFILE" \
  -D "$LOG" \
  >>"$DIR/qemu.stdout" 2>>"$DIR/qemu.stderr" &

ok=0
for i in $(seq 1 20); do
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    ok=1
    break
  fi
  sleep 1
done
if [[ "$ok" != "1" ]]; then
  # pidfile race: accept live process by name pattern via /proc
  for pid in /proc/[0-9]*; do
    cmdline=$(tr '\0' ' ' < "$pid/cmdline" 2>/dev/null || true)
    if [[ "$cmdline" == *"-name arch-hyprland"* ]]; then
      echo "${pid#/proc/}" > "$PIDFILE"
      ok=1
      break
    fi
  done
fi
if [[ "$ok" != "1" ]]; then
  echo "Failed to start VM (accel=$ACCEL). See $DIR/qemu.stderr and $DIR/qemu.log" >&2
  cat "$DIR/qemu.stderr" 2>/dev/null || true
  cat "$DIR/qemu.log" 2>/dev/null || true
  exit 1
fi
pid="$(cat "$PIDFILE")"
echo "Started pid=$pid accel=$ACCEL smp=$SMP"
echo "SSH:  ssh -p 2222 arch@127.0.0.1   (pass: arch — see credentials.txt)"
echo "VNC:  127.0.0.1:5901"
echo "Logs: $LOG  serial: $DIR/serial.log  stderr: $DIR/qemu.stderr"
