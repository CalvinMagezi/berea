"""Builds one book's audio pack for the app: python pack.py 43 (after pilot.py for the book)."""

import argparse
import hashlib
import json
import sqlite3
from pathlib import Path

import ctc
import encode
import fetch

RELEASE = "audio-1"
PACK_FORMAT = "1"
PACKS = Path("build/audio-packs")
SCHEMA = """
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  CREATE TABLE chapters(chapter INTEGER PRIMARY KEY, duration_ms INTEGER NOT NULL,
    audio BLOB NOT NULL, timings TEXT NOT NULL);
"""
TIMINGS_LICENCE = (
    "CC0 1.0. Word timings made by the Berea project and dedicated to the public domain"
)


def pack_id(narrator: str, book: int) -> str:
    return f"{narrator}-{book:02d}"


def build_pack(book: int, narrator: str, build: Path, out_dir: Path) -> dict:
    """Writes <narrator>-<book>.sqlite from every encoded chapter and returns its manifest entry."""
    chapters = sorted((build / "m4a" / f"{book:02d}").glob("*.m4a"))
    if not chapters:
        raise ValueError(f"no encoded chapters for book {book}; run pilot.py first")
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{pack_id(narrator, book)}.sqlite"
    path.unlink(missing_ok=True)
    with sqlite3.connect(path) as db:
        db.executescript(SCHEMA)
        meta = {**_meta(book, narrator), "priming_ms": _priming_ms(book, chapters, build)}
        db.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
        for m4a in chapters:
            db.execute("INSERT INTO chapters VALUES (?, ?, ?, ?)", _chapter_row(book, m4a, build))
    _compact(path)
    check_pack(path, book, len(chapters))
    return {
        "id": pack_id(narrator, book),
        "file": path.name,
        "book": book,
        "narrator": narrator,
        "chapters": len(chapters),
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def _meta(book: int, narrator: str) -> dict[str, str]:
    return {
        "format": PACK_FORMAT,
        "pack": pack_id(narrator, book),
        "book": str(book),
        "narrator": narrator,
        "release": RELEASE,
        "audio_licence": fetch.AUDIO_LICENCE,
        "timings_licence": TIMINGS_LICENCE,
        "codec": encode.ENCODER_LABEL,
        "aligner": f"{ctc.MODEL}@{ctc.MODEL_REVISION}",
    }


def _priming_ms(book: int, chapters: list[Path], build: Path) -> str:
    """The encoder priming a player that ignores the MP4 edit list would hear; one per pack."""
    lags = {
        json.loads((build / "qa" / f"{book:02d}" / f"{m4a.stem}.json").read_text())["raw_lag_ms"]
        for m4a in chapters
    }
    if len(lags) != 1:
        raise ValueError(f"book {book}: encoder priming differs between chapters: {sorted(lags)}")
    return str(lags.pop())


def _chapter_row(book: int, m4a: Path, build: Path) -> tuple[int, int, bytes, str]:
    chapter = int(m4a.stem)
    timings = (build / "timings" / f"{book:02d}" / f"{chapter:03d}.json").read_text()
    return chapter, encode.duration_ms(str(m4a)), m4a.read_bytes(), timings


def _compact(path: Path) -> None:
    """One self-contained file with no journal, so its hash is the hash of what the app opens."""
    db = sqlite3.connect(path)
    try:
        db.execute("PRAGMA journal_mode = DELETE")
        db.execute("VACUUM")
    finally:
        db.close()


def check_pack(path: Path, book: int, chapter_count: int) -> None:
    """Every chapter has audio and timings in the documented shape, in order, for this book."""
    with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as db:
        meta = dict(db.execute("SELECT key, value FROM meta"))
        rows = db.execute("SELECT chapter, duration_ms, audio, timings FROM chapters").fetchall()
    if meta.get("format") != PACK_FORMAT or meta.get("book") != str(book):
        raise ValueError(f"{path}: wrong format or book in meta")
    if len(rows) != chapter_count:
        raise ValueError(f"{path}: {len(rows)} chapters, expected {chapter_count}")
    for chapter, duration_ms, audio, timings in rows:
        _check_chapter(path, book, chapter, duration_ms, audio, json.loads(timings))


def _check_chapter(path, book, chapter, duration_ms, audio, timings) -> None:
    where = f"{path} chapter {chapter}"
    if not audio or timings["book"] != book or timings["chapter"] != chapter:
        raise ValueError(f"{where}: missing audio or timings for another chapter")
    previous = (0, -1)
    previous_end = 0
    for verse, index, start, end in timings["words"]:
        # Each verse counts its words from 0 with none skipped, so wordIndex finds every word.
        expected = (previous[0], previous[1] + 1) if verse == previous[0] else (verse, 0)
        if (verse, index) != expected or verse < previous[0]:
            raise ValueError(f"{where}: word {verse}:{index} follows {previous[0]}:{previous[1]}")
        if not previous_end <= start <= end <= duration_ms:
            raise ValueError(f"{where}: {verse}:{index} at {start}-{end} ms is out of order")
        previous, previous_end = (verse, index), end


def write_manifest(entry: dict, out_dir: Path) -> None:
    """Merges one pack into manifest.json, the list the app's pins are copied from."""
    path = out_dir / "manifest.json"
    manifest = json.loads(path.read_text()) if path.exists() else {"release": RELEASE, "packs": []}
    manifest["packs"] = [p for p in manifest["packs"] if p["id"] != entry["id"]] + [entry]
    manifest["packs"].sort(key=lambda p: p["id"])
    path.write_text(json.dumps(manifest, indent=1) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("book", type=int)
    parser.add_argument("--narrator", default="souer")
    args = parser.parse_args()
    entry = build_pack(args.book, args.narrator, Path("build/audio"), PACKS)
    write_manifest(entry, PACKS)
    print(json.dumps(entry, indent=1))


if __name__ == "__main__":
    main()
