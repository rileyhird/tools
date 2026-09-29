#!/usr/bin/env bash
# extract.sh - get files out of a drive image, trying in order:
#   1) mount each partition read-only and copy files
#   2) testdisk (find lost partitions / copy files interactively)
#   3) photorec (carve files by content, no names/folders)
# Usage: sudo ./extract.sh /path/to/drive.img /path/to/output_folder
set -uo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; RST=$'\e[0m'
say()  { echo "${GRN}==>${RST} $*"; }
warn() { echo "${YLW}!! ${RST} $*"; }
die()  { echo "${RED}XX ${RST} $*"; exit 1; }
ask()  { read -rp "$1 [y/N] " a; [[ $a =~ ^[Yy]$ ]]; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0 IMAGE OUTPUT_DIR"
[[ $# -eq 2 ]] || die "Usage: sudo $0 IMAGE OUTPUT_DIR"
IMG=$1; OUT=$2
[[ -f $IMG ]] || die "Image not found: $IMG"
mkdir -p "$OUT" || die "Can't create $OUT"

LOOP=""; MNT=""
cleanup() {
  [[ -n $MNT ]] && mountpoint -q "$MNT" && umount "$MNT"
  [[ -n $MNT ]] && rmdir "$MNT" 2>/dev/null
  [[ -n $LOOP ]] && losetup -d "$LOOP" 2>/dev/null
}
trap cleanup EXIT

# ---------- Method 1: mount read-only ----------
say "Method 1: mount partitions read-only"
LOOP=$(losetup -Pf --show -r "$IMG") || die "losetup failed"
sleep 1
lsblk -o NAME,SIZE,FSTYPE,LABEL "$LOOP"

PARTS=$(lsblk -lnpo NAME,TYPE "$LOOP" | awk '$2=="part"{print $1}')
[[ -z $PARTS ]] && PARTS=$LOOP   # image may be a single partition with no table

COPIED=0
MNT=$(mktemp -d /mnt/recover.XXXX)
for p in $PARTS; do
  fs=$(blkid -o value -s TYPE "$p" 2>/dev/null)
  size=$(lsblk -dno SIZE "$p")
  echo
  if mount -o ro "$p" "$MNT" 2>/dev/null || { [[ $fs == ext* ]] && mount -o ro,noload "$p" "$MNT" 2>/dev/null; }; then
    say "Mounted $p ($fs, $size)"
    ls "$MNT" | head -20
    if ask "Copy everything from $p to $OUT/$(basename "$p")?"; then
      dest="$OUT/$(basename "$p")"; mkdir -p "$dest"
      # rsync keeps going past unreadable files and logs them
      if command -v rsync >/dev/null; then
        rsync -a --info=progress2 "$MNT"/ "$dest"/ 2> "$dest.errors.log"
      else
        cp -a "$MNT"/. "$dest"/ 2> "$dest.errors.log"
      fi
      say "Copied. Unreadable files (if any) listed in $dest.errors.log"
      COPIED=1
    fi
    umount "$MNT"
  else
    warn "Couldn't mount $p (${fs:-unknown filesystem}, $size)"
  fi
done
rmdir "$MNT"; MNT=""
losetup -d "$LOOP"; LOOP=""

if (( COPIED )) && ! ask "Files copied. Still try TestDisk / PhotoRec for anything missing?"; then
  say "Done. Your files are in $OUT"; exit 0
fi

# ---------- Method 2: testdisk ----------
if command -v testdisk >/dev/null; then
  echo
  say "Method 2: TestDisk"
  echo "  In TestDisk: pick the image > partition type (usually Intel/EFI GPT) > Analyse > Quick Search."
  echo "  Highlight a partition and press P to browse files, then C to copy them to: $OUT"
  if ask "Open TestDisk now?"; then
    ( cd "$OUT" && testdisk /log "$IMG" )
    if ! ask "Still try PhotoRec (recovers files without names)?"; then
      say "Done. Check $OUT"; exit 0
    fi
  fi
else
  warn "testdisk not installed, skipping (install the testdisk package)"
fi

# ---------- Method 3: photorec ----------
if command -v photorec >/dev/null; then
  echo
  say "Method 3: PhotoRec (file carving)"
  warn "Files come back with generic names like f1234567.jpg, sorted into recup_dir.N folders."
  warn "This can produce a LOT of files. Make sure $OUT has plenty of space."
  if ask "Run PhotoRec on the whole image?"; then
    photorec /log /d "$OUT/photorec/recup_dir" /cmd "$IMG" search
    say "PhotoRec finished. Results in $OUT/photorec/"
  fi
else
  warn "photorec not installed, skipping (install the testdisk package)"
fi

say "All done. Check $OUT"
