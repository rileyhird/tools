# Arch test checklist: Samsung AMD black-screen boot

**For:** Riley (hand-off via Chief of Staff)  
**From:** Lab  
**Date:** 2026-09-07  
**Source:** Research brief + recovery playbook (`/workspace/research/samsung-amd-black-screen-brief.md`, `amdgpu-black-screen-recovery-playbook.md`)  
**Constraint:** Bot machines have no AMD GPU — run this on the Samsung laptop only. Copy-paste; do not expect us to execute these steps remotely.

**Given:** amdgpu in stack; radeon “fights better”; only `nomodeset` currently yields a usable boot. Goal: escape permanent `nomodeset` with the smallest working set of params.

---

## 0. Before you start (once, under `nomodeset` or SSH)

Capture baselines so later passes are comparable:

```bash
uname -r
cat /proc/cmdline
sudo dmidecode -s system-product-name
lspci -nnk | grep -A3 -E 'VGA|Display'
lsmod | grep -E 'radeon|amdgpu'
dmesg | grep -iE 'amdgpu|radeon|firmware|psp|ucode|brightness|_BQC|VGACON' | tee ~/amd-baseline-dmesg.txt
```

**Flashlight / HDMI triage (do this once):**

| Result | Likely class | Branch |
|--------|--------------|--------|
| Flashlight shows faint desktop, or SSH works while panel looks black | Backlight / brightness curve (not full KMS death) | Prefer steps H / I / C2 / `abmlevel=0` early |
| External HDMI also dead; all TTYs black | True modeset / KMS failure | Stick to A→G order; use Live USB if stuck |
| dmesg mentions `No _BQC method` | Samsung ACPI quirk → backlight-class “black” | Treat as backlight path, not GPU modeset |

Fill a row in the **pass/fail log** (§5) for every reboot.

**Safety:** One change set per reboot. Do not stack winners until you have isolated the minimum. Prefer GRUB temporary edit (`e`) until a combo is proven.

---

## 1. Ordered GRUB experiments (one change set per reboot)

At GRUB: highlight the normal Arch entry → **`e`** → edit the `linux` line → **Ctrl+X** or **F10**.

Start from a line that still has your current emergency bits if needed, but **remove permanent `nomodeset`** for each of these trials (unless the step says otherwise). After each boot, record PASS/FAIL in §5.

| Step | Edit on `linux` line | Pass criteria | Fail → next |
|------|----------------------|---------------|-------------|
| **A** | Remove `quiet` and `splash` only | You can see kernel/firmware errors or a clean boot to GUI/TTY | Note last visible line; continue |
| **B** | Drop `nomodeset`; append `amdgpu.runpm=0` | GUI or usable TTY without nomodeset | Continue |
| **C** | `amdgpu.dcdebugmask=0x10` (try `0x12` if still blank) | Stable panel / no freeze at KMS | Continue |
| **C2** | `amdgpu.dcdebugmask=0x40000` (or `0x40410`) | Panel brightens; dmesg no longer “stuck” near-black from custom brightness curve (~6.14–6.16+) | Continue — *prioritize if flashlight showed faint UI* |
| **C3** | `amdgpu.abmlevel=0` | Panel not washed-out / not stuck dim | Continue — backlight-class branch |
| **D** | `amdgpu.sg_display=0` | Display comes up (APU SG bugs) | Continue |
| **E** | `amd_iommu=off` | TTY **and** GUI both return | Continue (note VFIO cost) |
| **F** | `amdgpu.dc=0` | Legacy DCE path works | Last-resort display; expect feature loss |
| **G** | `amdgpu.dpm=0` alone, then `amdgpu.dpm=0 amdgpu.aspm=0` | Survives GPU bring-up | Continue |
| **H** | `acpi_backlight=native` (or remove any `acpi_backlight=vendor`) | Backlight controllable; panel not stuck at 0 | Samsung `_BQC` / wrong backlight path |
| **I** | `systemd.restore_state=0` | Brightness not restored to ~0 | Continue |
| **J** | `initcall_blacklist=simpledrm_platform_driver_init` | Avoids simpledrm↔amdgpu race (esp. with splash) | End of param ladder |

**Backlight shortcut:** If step 0 showed faint desktop / `_BQC` / SSH-alive panel-black, run **A → H → I → C2 → C3** before burning time on F/G.

**After a winner:** peel stacked flags down to the minimum that still PASSes, then persist:

```bash
sudo nano /etc/default/grub
# GRUB_CMDLINE_LINUX_DEFAULT="…winning params only…"
# GRUB_TIMEOUT=10
# comment out GRUB_TIMEOUT_STYLE=hidden if present
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

If you also use `/etc/modprobe.d/`, rebuild initramfs (§3).

**Risks:** `amd_iommu=off` hurts VFIO; `amdgpu.dc=0` is a feature regression; permanent `nomodeset` breaks acceleration/Wayland — emergency only.

---

## 2. SI/CIK: force `radeon` vs `amdgpu` (Arch + mkinitcpio)

**Only if** the GPU is Southern Islands / Sea Islands (GCN1/GCN2). GCN3+ / Vega / RDNA **cannot** use `radeon`.

### 2a. Identify (boot with `nomodeset` if needed)

```bash
lspci -nnk | grep -A3 -E 'VGA|Display'
```

SI/CIK candidate when: `Kernel driver in use: amdgpu` **and** `Kernel modules:` lists **both** `radeon,amdgpu` (or vice versa). Riley’s “radeon fights better” fits this class.

### 2b. Temporary GRUB trial (one reboot)

Drop `nomodeset`; append:

```text
radeon.si_support=1 radeon.cik_support=1 amdgpu.si_support=0 amdgpu.cik_support=0
```

PASS = usable display on `radeon`. FAIL / wrong generation = skip to firmware/kernel (§3); do not blacklist amdgpu on GCN3+.

### 2c. Persist with modprobe + mkinitcpio

```bash
sudo tee /etc/modprobe.d/prefer-radeon.conf <<'EOF'
options radeon si_support=1 cik_support=1
options amdgpu si_support=0 cik_support=0
blacklist amdgpu
install amdgpu /bin/false
EOF
```

Ensure mkinitcpio will honor modprobe.d — `/etc/mkinitcpio.conf` HOOKS must include `modconf` (default Arch preset does):

```bash
grep -E '^HOOKS=' /etc/mkinitcpio.conf
# HOOKS=(base udev … modconf … filesystems …)
```

Optional: early-load radeon:

```bash
# MODULES=(radeon)   # in /etc/mkinitcpio.conf — only after SI/CIK confirmed
```

Rebuild and refresh GRUB:

```bash
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

Also keep the `*_support=` tokens in `GRUB_CMDLINE_LINUX_DEFAULT` until you confirm modprobe alone is enough.

### 2d. Revert (back to amdgpu)

```bash
sudo rm -f /etc/modprobe.d/prefer-radeon.conf
# Remove *_support= and blacklist lines from GRUB_CMDLINE_LINUX_DEFAULT
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

**Trade-offs if radeon wins:** no RADV/Vulkan; weaker Wayland/VRR/HDR. On kernels ≥6.19 amdgpu is default for SI/CIK dGPUs — forcing radeon is an intentional rollback.

---

## 3. Firmware / kernel sync and rollback (pacman + mkinitcpio)

### 3a. Sync firmware to current kernel

```bash
sudo pacman -Syu linux-firmware linux-firmware-amdgpu
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

After boot:

```bash
dmesg | grep -iE 'amdgpu|firmware|psp|ucode|MES' | head -80
# Look for firmware load failures (-2 / -19 / -22 class errors)
```

### 3b. Keep / install a known-good kernel (LTS)

```bash
sudo pacman -S linux-lts linux-lts-headers
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

At next boot: GRUB → pick **linux-lts**. Leave current `linux` installed so you can A/B.

### 3c. Downgrade a bad firmware package (from pacman cache or Archive)

If black screen started right after a `linux-firmware-amdgpu` bump:

```bash
ls /var/cache/pacman/pkg/linux-firmware-amdgpu-*.pkg.tar.zst
# sudo pacman -U /var/cache/pacman/pkg/linux-firmware-amdgpu-<OLDER>.pkg.tar.zst
# Or fetch older from https://archive.archlinux.org/packages/l/linux-firmware-amdgpu/
sudo mkinitcpio -P
sudo reboot
```

Same pattern for `linux` / `linux-lts` package downgrades if a kernel bump is the trigger.

### 3d. Rule of thumb

| Trigger | First move |
|---------|------------|
| Black after **kernel** bump | Boot previous / `linux-lts` from GRUB |
| Black after **firmware** bump | Downgrade `linux-firmware-amdgpu`, then `mkinitcpio -P` |
| Black after both | Live USB → arch-chroot (§4), align versions |

---

## 4. Arch recovery playbook (arch-chroot from Live USB)

Use when GRUB edits fail, TTYs are dead, and SSH was never enabled.

### 4a. Boot Arch ISO → find partitions

```bash
lsblk -f
# Note: root (ext4/btrfs/xfs), EFI (vfat), optional separate /boot
```

### 4b. Mount + arch-chroot

```bash
# Adjust device names
mount /dev/nvme0n1pX /mnt                 # root
# If separate /boot:
# mount /dev/nvme0n1pZ /mnt/boot
mount /dev/nvme0n1pY /mnt/boot/efi        # ESP — or /mnt/efi per your layout
# Btrfs Ubuntu-style layouts only: mount -o subvol=@ /dev/... /mnt

arch-chroot /mnt
```

### 4c. Inside chroot — emergency GRUB params

```bash
nano /etc/default/grub
```

Examples (pick **one** emergency line first):

```bash
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"
# or: GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=off"
# or winning set from §1, e.g.:
# GRUB_CMDLINE_LINUX_DEFAULT="amdgpu.runpm=0 amdgpu.dcdebugmask=0x10"
GRUB_TIMEOUT=10
# Comment out: GRUB_TIMEOUT_STYLE=hidden
```

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

### 4d. Inside chroot — modprobe / early amdgpu (optional)

```bash
cat >/etc/modprobe.d/amdgpu.conf <<'EOF'
# options amdgpu dc=0
options amdgpu sg_display=0
EOF

# Early load (edit /etc/mkinitcpio.conf):
# MODULES=(amdgpu)
# Confirm HOOKS includes modconf
```

SI/CIK prefer-radeon file from §2c can be written here too.

### 4e. Rebuild initramfs + exit

```bash
mkinitcpio -P
# optional firmware refresh if network works in chroot:
# pacman -Syu linux-firmware linux-firmware-amdgpu
exit
umount -R /mnt
reboot
```

### 4f. After recovery (do once)

```bash
sudo pacman -S openssh
sudo systemctl enable --now sshd
```

Keep at least one known-good kernel installed. Prefer targeted `amdgpu.*` params over permanent `nomodeset`.

---

## 5. Pass/fail log template

Copy into `~/amd-black-screen-log.md` (or paper). One row per reboot.

| # | Date/time | Kernel (`uname -r`) | Change set (exact cmdline delta) | Flashlight? | HDMI? | TTY? | GUI? | Driver (`lsmod` / lspci) | Notes / dmesg snippet | PASS/FAIL |
|---|-----------|---------------------|----------------------------------|-------------|-------|------|-----|--------------------------|-----------------------|-----------|
| 0 | | | baseline (`nomodeset`) | | | | | | | |
| A | | | remove quiet splash | | | | | | | |
| B | | | `amdgpu.runpm=0` | | | | | | | |
| C | | | `dcdebugmask=0x10` | | | | | | | |
| C2 | | | `dcdebugmask=0x40000` | | | | | | | |
| C3 | | | `abmlevel=0` | | | | | | | |
| D | | | `sg_display=0` | | | | | | | |
| E | | | `amd_iommu=off` | | | | | | | |
| F | | | `amdgpu.dc=0` | | | | | | | |
| G | | | `dpm=0` / `aspm=0` | | | | | | | |
| H | | | `acpi_backlight=native` | | | | | | | |
| I | | | `systemd.restore_state=0` | | | | | | | |
| J | | | simpledrm blacklist | | | | | | | |
| R1 | | | SI/CIK `*_support=` force radeon | | | | | | | |
| FW | | | firmware sync / downgrade | | | | | | | |
| LTS | | | boot `linux-lts` | | | | | | | |

**PASS definition:** usable local display (GUI preferred) **without** `nomodeset`, or clear diagnostic progress you can act on (visible panic, confirmed backlight-only).

**When done:** send Lab / Chief of Staff the filled log + `lspci -nnk` VGA block + winning `GRUB_CMDLINE_LINUX_DEFAULT`. Escalate to Riley only for BIOS flash / Secure Boot experiments / anything that risks bricking.

---

## Quick order reminder

1. Baseline + flashlight / `_BQC` triage  
2. GRUB ladder A→J (backlight shortcut if dim)  
3. Persist minimum winner via `grub-mkconfig`  
4. If SI/CIK → force radeon + `mkinitcpio -P`  
5. Else → firmware sync / `linux-lts` / Archive downgrade  
6. If stuck → Arch ISO → `arch-chroot` → edit + `mkinitcpio -P`  
7. Enable `sshd` for next incident  

*End of checklist.*
