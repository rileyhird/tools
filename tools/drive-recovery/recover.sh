#!/usr/bin/env bash
# recover.sh - check recovery tools, then image a failing drive with ddrescue
# and pull files from the IMAGE (never the original drive).
# Usage: sudo ./recover.sh
set -uo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; RST=$'\e[0m'
say()  { echo "${GRN}==>${RST} $*"; }
warn() { echo "${YLW}!! ${RST} $*"; }
die()  { echo "${RED}XX ${RST} $*"; exit 1; }
ask()  { read -rp "$1 [y/N] " a; [[ $a =~ ^[Yy]$ ]]; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

# ---------- 1. Tool check ----------
# name | Debian/Ubuntu pkg | Arch pkg | version command
TOOLS=(
  "dd|coreutils|coreutils|dd --version"
  "ddrescue|gddrescue|ddrescue|ddrescue --version"
  "lsblk|util-linux|util-linux|lsblk --version"
  "smartctl|smartmontools|smartmontools|smartctl --version"
  "testdisk|testdisk|testdisk|testdisk /version"
  "photorec|testdisk|testdisk|photorec /version"
  "fsck|util-linux|util-linux|fsck --version"
  "ntfsfix|ntfs-3g|ntfs-3g|ntfsfix --version"
)
if command -v pacman >/dev/null; then DISTRO=arch
elif command -v apt-get >/dev/null; then DISTRO=debian
else DISTRO=other; fi

say "Checking tools"
MISSING=()
for t in "${TOOLS[@]}"; do
  IFS='|' read -r name debpkg archpkg vcmd <<<"$t"
  [[ $DISTRO == arch ]] && pkg=$archpkg || pkg=$debpkg
  if command -v "$name" >/dev/null 2>&1; then
    ver=$($vcmd 2>&1 | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "?")
    printf "  %-10s %s\n" "$name" "${GRN}$ver${RST}"
  else
    printf "  %-10s %s\n" "$name" "${RED}missing${RST} (pkg: $pkg)"
    MISSING+=("$pkg")
  fi
done

if ((${#MISSING[@]})); then
  PKGS=$(printf "%s\n" "${MISSING[@]}" | sort -u | tr '\n' ' ')
  warn "Missing packages: $PKGS"
  case $DISTRO in
    arch)
      # All of these are in the official repos, so pacman is enough (yay isn't needed,
      # and yay must not run as root anyway).
      ask "Install them with pacman?" && { pacman -S --needed --noconfirm $PKGS || die "Install failed"; } ;;
    debian)
      ask "Install them with apt-get?" && { apt-get update && apt-get install -y $PKGS || die "Install failed"; } ;;
    *) warn "Unknown package manager. Install these yourself: $PKGS" ;;
  esac
fi
command -v ddrescue >/dev/null || die "ddrescue is required. Install it (Arch: ddrescue, Ubuntu: gddrescue) and re-run."

# ---------- 2. Pick the source drive ----------
say "Drives on this machine:"
lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN,TYPE | grep -v loop
echo
read -rp "Source (failing) drive, e.g. sdb: " SRC
[[ -n $SRC ]] || die "No drive entered."
SRC="/dev/${SRC#/dev/}"
[[ -b $SRC ]] || die "$SRC is not a block device"

ROOTDEV=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null)
[[ "/dev/$ROOTDEV" == "$SRC" ]] && die "$SRC is the drive this system is running from. Refusing."

if lsblk -no MOUNTPOINT "$SRC" | grep -q .; then
  warn "$SRC has mounted partitions:"; lsblk "$SRC"
  ask "Unmount them now? (recommended)" && umount "${SRC}"?* 2>/dev/null
fi

# ---------- 3. SMART health (read-only) ----------
if command -v smartctl >/dev/null; then
  say "SMART health for $SRC"
  smartctl -H -A "$SRC" | grep -Ei 'overall|result|Reallocated|Pending|Uncorrect|Power_On' || true
fi

# ---------- 4. Destination ----------
SRC_BYTES=$(blockdev --getsize64 "$SRC")
echo
read -rp "Folder to save the image in (on a DIFFERENT, healthy drive): " DEST
mkdir -p "$DEST" || die "Can't create $DEST"
DEST_DEV=$(df --output=source "$DEST" | tail -1)
[[ $DEST_DEV == $SRC* ]] && die "Destination is on the source drive. Pick another drive."
FREE=$(df --output=avail -B1 "$DEST" | tail -1)
(( FREE > SRC_BYTES )) || die "Not enough space: need $((SRC_BYTES/1024**3)) GiB, have $((FREE/1024**3)) GiB"

NAME=$(basename "$SRC")_$(date +%Y%m%d)
IMG="$DEST/$NAME.img"; MAP="$DEST/$NAME.map"
say "Image: $IMG"
say "Map:   $MAP (lets you stop and resume safely)"
ask "Start imaging $SRC -> $IMG? The source is only read." || exit 0

# ---------- 5. ddrescue: fast pass, then retry bad areas ----------
say "Pass 1: grab the easy data, skip bad areas"
ddrescue -d -n "$SRC" "$IMG" "$MAP"
say "Pass 2: retry bad areas 3 times"
ddrescue -d -r3 "$SRC" "$IMG" "$MAP"

say "Done imaging. Summary:"
tail -n 5 "$MAP"

# ---------- 6. Next steps on the IMAGE ----------
echo
say "Next, work only on the image:"
echo "  Mount read-only:   sudo losetup -Pf --show -r $IMG   then mount /dev/loopXp1 /mnt -o ro"
echo "  Find partitions:   sudo testdisk $IMG"
echo "  Carve lost files:  sudo photorec $IMG"
