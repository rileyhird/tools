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

Options: `--min-photo-kb`, `--min-doc-kb`, `--min-video-mb`, `--include-other`, `--move`, `--run`, `--first N`, `--from M`, `--to N`.
Optional: Pillow (`pip install pillow`) for sorting photos by date taken.

## Windows: step by step (first time)

1. Download `windows/Sort-PhotoRec.ps1` from this page (open the file, then use the download button) and keep it in your Downloads folder.
2. Open the Downloads folder in File Explorer. Click the address bar at the top, type `powershell`, and press Enter. A blue PowerShell window opens in that folder.
3. Find your **source** folder: the one that holds all the `recup_dir.1`, `recup_dir.2`, ... folders (not one of the numbered folders itself). Open it in File Explorer, click the address bar, and copy the path, for example `D:\`.
4. Pick a **destination** folder for the sorted files, for example `C:\sorted`. It needs free space, because the script copies.
5. **Check first** (this copies nothing). Put your real paths in; keep the quotes if the path has spaces:
   ```
   powershell -ExecutionPolicy Bypass -File .\Sort-PhotoRec.ps1 -Source "D:\" -Dest C:\sorted
   ```
6. If the summary looks right, run it for real by adding `-Run`:
   ```
   powershell -ExecutionPolicy Bypass -File .\Sort-PhotoRec.ps1 -Source "D:\" -Dest C:\sorted -Run
   ```
7. **Lots of recup_dir folders?** Do them in batches, using the same destination each time. The script remembers earlier batches and skips duplicates:
   ```
   ... -Source "D:\" -Dest C:\sorted -From 1 -To 250 -Run
   ... -Source "D:\" -Dest C:\sorted -From 251 -To 500 -Run
   ```
8. It prints a progress line every 200 files. Big drives can take a long time. `Ctrl+C` stops it safely; your originals are never changed unless you use `-Move`.
9. If Windows says the file is blocked: right-click the file, choose Properties, tick **Unblock**, and click OK.

## Windows (PowerShell) - options

```
.\windows\Sort-PhotoRec.ps1 -Source D:\recup -Dest E:\sorted        # check only (default)
.\windows\Sort-PhotoRec.ps1 -Source D:\recup -Dest E:\sorted -Run   # really copy
```

Options: `-MinPhotoKB`, `-MinDocKB`, `-MinVideoMB`, `-IncludeOther`, `-Move`, `-Run`, `-First N`, `-From M`, `-To N`.
If Windows blocks the script, run it once with: `powershell -ExecutionPolicy Bypass -File .\windows\Sort-PhotoRec.ps1 -Source ... -Dest ...`
Works in the built-in Windows PowerShell 5.1 and in PowerShell 7. Photo dates use the built-in .NET image library, so nothing to install.

## Doing it in batches (lots of recup_dir folders)

Use `-From` and `-To` (Linux: `--from` and `--to`) to handle a range of `recup_dir.N` folders at a time, e.g. `-From 1 -To 250`, then `-From 251 -To 500`, and so on. `-First 250` is shorthand for `-From 1 -To 250`. Keep the same destination folder for every batch: the script reads the `manifest.csv` from earlier batches and skips duplicates of files already kept, then adds the new files to the manifest.

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
