# Arch Linux + Hyprland QEMU VM

Work directory for the Hyprland bot on the shared box.

## Image

- Official **arch-boxes** basic qcow2 (x86_64), SHA256 verified
- Source: `https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-basic.qcow2`
- Local copies: `Arch-Linux-x86_64-basic.qcow2` (pristine), `disk.qcow2` (working)
- Virtual size: **40 GiB** (already sized; no resize needed)
- Firmware: OVMF UEFI (`OVMF_CODE_4M.fd` + local `OVMF_VARS.fd`)

## Start / stop

```bash
cd /workspace/vms/arch-hyprland
./start.sh          # idempotent; default ACCEL=tcg
./stop.sh           # ACPI powerdown via monitor, then SIGTERM/KILL
```

### Acceleration

**Nested KVM is broken on this shared box** (kernel BUG `kvm_spurious_fault` in
`kvm_arch_vcpu_create`). `/dev/kvm` exists but creating vCPUs oopses the host KVM.

Default is **TCG** with multi-thread:

```bash
ACCEL=tcg ./start.sh          # default
ACCEL=kvm ./start.sh          # retry when nested KVM is fixed
SMP=4 ACCEL=tcg ./start.sh    # SMP override (TCG default 4)
```

Guest RAM: **3072 MB**. vCPUs: 4 (TCG) / 4 (KVM if used).

### Display / GPU

- Device: **virtio-gpu-pci** only (not amdgpu; not a Samsung black-screen repro)
- Display: QEMU VNC on `127.0.0.1:5901`
- Hyprland wrapper defaults to **`WLR_RENDERER=pixman`** (reliable under virtio-gpu + QEMU VNC).
  GLES/GL may start but VNC screendumps often stay black; processes still run.
  `vulkan-virtio` is installed if you want to experiment with `WLR_RENDERER=vulkan`.

## Guest Hyprland setup

Once SSH works:

```bash
sshpass -p arch ssh -p 2222 arch@127.0.0.1
# then as root/sudo:
sudo bash -s < guest-setup.sh
# or copy then run:
scp -P 2222 guest-setup.sh arch@127.0.0.1:
ssh -p 2222 arch@127.0.0.1 'sudo bash guest-setup.sh'
```

`guest-setup.sh` installs: hyprland, xdg-desktop-portal-hyprland, waybar, kitty,
foot, swaybg, grim, slurp, wl-clipboard, noto-fonts, qt5/6-wayland, mesa,
vulkan-virtio (if available), seatd; configures tty1 autologin + Hyprland
autostart with pixman fallback.

## Known limits

1. **Nested KVM broken** — must use TCG (slow first boot; ldconfig can take 10–20+ min).
2. Host RAM tight (~4G available); guest capped at 3072 MB.
3. Host cannot mount guest btrfs/vfat offline (no fs modules / no modprobe in this container).
4. First arch-boxes boot runs "Rebuild Dynamic Linker Cache" which is very slow under TCG.
5. Do not claim this reproduces Samsung amdgpu black-screen issues.

## Files

| Path | Purpose |
|------|---------|
| `start.sh` / `stop.sh` | Lifecycle |
| `credentials.txt` | Secrets (600) |
| `disk.qcow2` | Working disk |
| `guest-setup.sh` | In-guest Hyprland install |
| `wait-ssh.sh` | Poll until SSH is up |
| `STATUS.md` | Current verification state |
| `screen*.png` | Boot screendumps (when captured) |
