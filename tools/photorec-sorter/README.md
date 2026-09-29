# PhotoRec sorter

PhotoRec dumps recovered files into `recup_dir.1`, `recup_dir.2`, ... with generic names. `sort_photorec.py` turns that pile into something usable.

```
./sort_photorec.py /path/to/photorec/recup_dirs /path/to/sorted --dry-run   # preview first
./sort_photorec.py /path/to/photorec/recup_dirs /path/to/sorted
```

- Sorts into `Photos/`, `Documents/`, `Videos/`, `Audio/`, `Archives/`.
- Keeps only big files by default (photos 200 KB+, documents 10 KB+, videos 5 MB+) since small ones are mostly thumbnails and junk. Change with `--min-photo-kb`, `--min-doc-kb`, `--min-video-mb`.
- Skips exact duplicates (checked by content hash).
- Photos go into `YYYY-MM` folders by date taken if Pillow is installed, otherwise `undated`.
- Unknown file types are skipped unless you add `--include-other`.
- Copies by default. `--move` moves instead. Needs free space for the copies.
- Writes `manifest.csv` listing every kept file and where it came from.

Tested on fake data only so far.
