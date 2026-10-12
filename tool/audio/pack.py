"""Builds one book's audio pack for the app: python pack.py 43 (after pilot.py for the book)."""

import argparse
import hashlib
import json
import sqlite3
from pathlib import Path

import ctc
import encode
import fetch
from paths import BUILD, DB, PACKS
from report import timing_problems
from text import chapter_count

RELEASE = "audio-1"
PACK_FORMAT = "1"
SCHEMA = """
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  CREATE TABLE chapters(chapter INTEGER PRIMARY KEY, duration_ms INTEGER NOT NULL,
    audio BLOB NOT NULL, timings TEXT NOT NULL);
"""
# Chapter files only (001.m4a), never a pending encode left by a failed run.
CHAPTER_FILES = "[0-9][0-9][0-9].m4a"
TIMINGS_LICENCE = (
    "CC0 1.0. Word timings made by the Berea project and dedicated to the public domain"
)


def pack_id(narrator: str, book: int) -> str:
    return f"{narrator}-{book:02d}"


def build_pack(book: int, narrator: str, build: Path, out_dir: Path, db: Path) -> dict:
    """Writes <narrator>-<book>.sqlite from every encoded chapter and returns its manifest entry.
    Refuses a book with any chapter missing."""
    chapters = sorted((build / "m4a" / f"{book:02d}").glob(CHAPTER_FILES))
    expected = list(range(1, chapter_count(db, book) + 1))
    if [int(m4a.stem) for m4a in chapters] != expected:
        raise ValueError(f"book {book}: encoded chapters are not 1-{expected[-1]}; run pilot.py")
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{pack_id(narrator, book)}.sqlite"
    path.unlink(missing_ok=True)
    con = sqlite3.connect(path)
    try:
        con.executescript(SCHEMA)
        meta = {**_meta(book, narrator), "priming_ms": _priming_ms(book, chapters, build)}
        con.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
        for m4a in chapters:
            con.execute("INSERT INTO chapters VALUES (?, ?, ?, ?)", _chapter_row(book, m4a, build))
        con.commit()
    finally:
        con.close()
    _compact(path)
    check_pack(path, book, db)
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
    """One chapter's row, refused unless its audio is the file its timings were checked on."""
    chapter = int(m4a.stem)
    qa = json.loads((build / "qa" / f"{book:02d}" / f"{chapter:03d}.json").read_text())
    audio = m4a.read_bytes()
    if hashlib.sha256(audio).hexdigest() != qa.get("m4a_sha256"):
        raise ValueError(f"{m4a}: not the audio its timings were made for; rerun pilot.py")
    timings = (build / "timings" / f"{book:02d}" / f"{chapter:03d}.json").read_text()
    return chapter, encode.duration_ms(str(m4a)), audio, timings


def _compact(path: Path) -> None:
    """One self-contained file with no journal, so its hash is the hash of what the app opens."""
    db = sqlite3.connect(path)
    try:
        db.execute("PRAGMA journal_mode = DELETE")
        db.execute("VACUUM")
    finally:
        db.close()


def check_pack(path: Path, book: int, db: Path) -> None:
    """Every chapter of the book is there, with audio, and timings in the documented shape that
    time each whitespace word of each verse the app shows exactly once, in order."""
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        meta = dict(con.execute("SELECT key, value FROM meta"))
        rows = con.execute(
            "SELECT chapter, duration_ms, audio, timings FROM chapters ORDER BY chapter"
        ).fetchall()
    finally:
        con.close()
    if meta.get("format") != PACK_FORMAT or meta.get("book") != str(book):
        raise ValueError(f"{path}: wrong format or book in meta")
    if [r[0] for r in rows] != list(range(1, chapter_count(db, book) + 1)):
        raise ValueError(f"{path}: chapters missing for book {book}")
    for chapter, duration_ms, audio, timings in rows:
        words = json.loads(timings)
        _check_chapter(path, book, chapter, duration_ms, audio, words)
        problems = timing_problems(book, chapter, words["words"], db)
        if problems:
            raise ValueError(f"{path}: {problems[0]}")


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
    parser.add_argument("--db", default=DB, type=Path)
    args = parser.parse_args()
    entry = build_pack(args.book, args.narrator, BUILD, PACKS, args.db)
    write_manifest(entry, PACKS)
    print(json.dumps(entry, indent=1))


if __name__ == "__main__":
    main()
