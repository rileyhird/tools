# PhotoRec sorter

PhotoRec dumps recovered files into `recup_dir.1`, `recup_dir.2`, ... with generic names. These scripts turn that pile into something usable. Same behaviour on both systems.

| System | Script |
|--------|--------|
| **Linux** (also Mac) | [`linux/sort_photorec.py`](linux/sort_photorec.py) |
| **Windows** | [`windows/Sort-PhotoRec.ps1`](windows/Sort-PhotoRec.ps1) |

## Linux

```
python3 linux/sort_photorec.py /path/to/recup_dirs /path/to/sorted          # check only (default)
python3 linux/sort_photorec.py /path/to/recup_dirs /path/to/sorted --run    # really copy
```

Options: `--min-photo-kb`, `--min-doc-kb`, `--min-video-mb`, `--include-other`, `--move`, `--run`.
Optional: Pillow (`pip install pillow`) for sorting photos by date taken.

## Windows (PowerShell)

```
.\windows\Sort-PhotoRec.ps1 -Source D:\recup -Dest E:\sorted        # check only (default)
.\windows\Sort-PhotoRec.ps1 -Source D:\recup -Dest E:\sorted -Run   # really copy
```

Options: `-MinPhotoKB`, `-MinDocKB`, `-MinVideoMB`, `-IncludeOther`, `-Move`, `-Run`.
If Windows blocks the script, run it once with: `powershell -ExecutionPolicy Bypass -File .\windows\Sort-PhotoRec.ps1 -Source ... -Dest ...`
Works in the built-in Windows PowerShell 5.1 and in PowerShell 7. Photo dates use the built-in .NET image library, so nothing to install.

## What both do

- **Check only by default.** They list what they would keep and write nothing. Add `--run` (Linux) or `-Run` (Windows) to actually copy.
- Sort into `Photos/`, `Documents/`, `Videos/`, `Audio/`, `Archives/`.
- Keep only big files by default (photos 200 KB+, documents 10 KB+, videos 5 MB+); small ones are mostly thumbnails and junk.
- Skip exact duplicates (checked by content hash).
- Put photos in `YYYY-MM` folders by date taken, or `undated` if there's no date.
- Skip unknown file types unless told to keep them.
- Copy by default; only move when asked. Needs free space for the copies.
- Write `manifest.csv` listing every kept file and where it came from.

Tested on fake data only. The Windows script was tested with PowerShell 7 on Linux, not on an actual Windows machine.
