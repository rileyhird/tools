#!/usr/bin/env python3
"""sort_photorec.py - sort PhotoRec's recup_dir.* output into tidy folders.

Sorts by file type (Photos, Documents, Videos, Audio, Archives, Other), keeps only
files above a size threshold (small files are usually thumbnails/junk), skips exact
duplicates, and for photos reads the date taken (EXIF) when Pillow is installed.
By default this only CHECKS: it shows what it would keep and writes nothing.
Add --run to really copy the files. Originals are COPIED; nothing is deleted unless you also pass --move.

Usage:
  ./sort_photorec.py SRC_DIR DEST_DIR [--min-photo-kb 200] [--min-doc-kb 10]
                     [--min-video-mb 5] [--move] [--run]
"""
import argparse, hashlib, os, shutil, sys, csv
from collections import defaultdict
from datetime import datetime

CATS = {
    "Photos":    {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tif", ".tiff", ".heic", ".webp", ".cr2", ".nef", ".arw", ".dng", ".raf", ".orf"},
    "Documents": {".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".odt", ".ods", ".odp", ".rtf", ".txt", ".csv", ".epub"},
    "Videos":    {".mp4", ".mov", ".avi", ".mkv", ".mpg", ".mpeg", ".wmv", ".3gp", ".m4v", ".flv"},
    "Audio":     {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".wma", ".aac"},
    "Archives":  {".zip", ".rar", ".7z", ".gz", ".tar", ".bz2"},
}

def category(ext):
    for c, exts in CATS.items():
        if ext in exts:
            return c
    return "Other"

def photo_date(path):
    try:
        from PIL import Image
        exif = Image.open(path)._getexif() or {}
        raw = exif.get(36867) or exif.get(306)  # DateTimeOriginal / DateTime
        if raw:
            return datetime.strptime(raw[:19], "%Y:%m:%d %H:%M:%S")
    except Exception:
        pass
    return None

def sha1(path, block=1 << 20):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        while chunk := f.read(block):
            h.update(chunk)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src"); ap.add_argument("dest")
    ap.add_argument("--min-photo-kb", type=int, default=200)
    ap.add_argument("--min-doc-kb", type=int, default=10)
    ap.add_argument("--min-video-mb", type=int, default=5)
    ap.add_argument("--include-other", action="store_true", help="also keep unrecognised file types")
    ap.add_argument("--move", action="store_true", help="move instead of copy")
    ap.add_argument("--run", action="store_true", help="actually copy the files (default is check only)")
    ap.add_argument("--dry-run", action="store_true", help=argparse.SUPPRESS)
    a = ap.parse_args()
    a.dry_run = not a.run

    if not os.path.isdir(a.src):
        sys.exit(f"Not a folder: {a.src}")
    mins = {"Photos": a.min_photo_kb * 1024, "Documents": a.min_doc_kb * 1024,
            "Videos": a.min_video_mb * 1024 * 1024, "Audio": 100 * 1024, "Archives": 10 * 1024}

    files = []
    for root, _, names in os.walk(a.src):
        for n in names:
            files.append(os.path.join(root, n))
    print(f"Found {len(files)} files in {a.src}")

    seen = {}                       # sha1 -> kept path
    stats = defaultdict(lambda: [0, 0])   # cat -> [kept, bytes]
    skipped = defaultdict(int)
    rows = []
    os.makedirs(a.dest, exist_ok=True)

    # Group by size first so we only hash files that could be duplicates.
    by_size = defaultdict(list)
    for p in files:
        try: by_size[os.path.getsize(p)].append(p)
        except OSError: skipped["unreadable"] += 1

    for size in sorted(by_size, reverse=True):      # biggest first: best copy wins
        for p in by_size[size]:
            ext = os.path.splitext(p)[1].lower()
            cat = category(ext)
            if cat == "Other" and not a.include_other:
                skipped["other type"] += 1; continue
            if size < mins.get(cat, 0):
                skipped[f"too small ({cat})"] += 1; continue
            try:
                digest = sha1(p)
            except OSError:
                skipped["unreadable"] += 1; continue
            if digest in seen:
                skipped["duplicate"] += 1; continue

            sub = cat
            if cat == "Photos":
                d = photo_date(p)
                sub = os.path.join(cat, f"{d.year}-{d.month:02d}" if d else "undated")
            elif cat in ("Documents", "Videos", "Audio", "Archives"):
                sub = os.path.join(cat, ext.lstrip(".") or "noext")
            else:
                sub = os.path.join("Other", ext.lstrip(".") or "noext")
            tdir = os.path.join(a.dest, sub)
            target = os.path.join(tdir, os.path.basename(p))
            n = 1
            while os.path.exists(target):
                b, e = os.path.splitext(os.path.basename(p)); target = os.path.join(tdir, f"{b}_{n}{e}"); n += 1
            if not a.dry_run:
                os.makedirs(tdir, exist_ok=True)
                (shutil.move if a.move else shutil.copy2)(p, target)
            seen[digest] = target
            stats[cat][0] += 1; stats[cat][1] += size
            rows.append([target, cat, size, digest, p])

    if not a.dry_run:
        with open(os.path.join(a.dest, "manifest.csv"), "w", newline="") as f:
            w = csv.writer(f); w.writerow(["file", "category", "bytes", "sha1", "original"]); w.writerows(rows)

    print("\n" + ("CHECK ONLY - nothing was copied. Add --run to do it for real.\n" if a.dry_run else "") + "Kept:")
    for c, (n, b) in sorted(stats.items()):
        print(f"  {c:<10} {n:>7} files  {b/1024/1024:>9.1f} MB")
    print("Skipped:")
    for k, v in sorted(skipped.items()):
        print(f"  {k:<22} {v}")
    if not a.dry_run:
        print(f"\nDone. Sorted files and manifest.csv are in {a.dest}")
        try:
            from PIL import Image  # noqa
        except ImportError:
            print("Tip: install Pillow (pip install pillow / pacman -S python-pillow) to sort photos by date taken.")

if __name__ == "__main__":
    main()
