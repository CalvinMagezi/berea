"""Aligns, encodes and checks narrated chapters: python pilot.py 43 1-21 (book, chapters)."""

import argparse
import hashlib
import json
import statistics
import time
from functools import cache
from pathlib import Path

import align
import ctc
import encode
import fetch
from paths import BSB_TXT, BUILD, DB, READ_TEXT
from text import book_numbers, bsb_verses, csv_verses, db_chapter, words_of

NARRATOR = "souer"
# Word starts found again in the encoded file may differ from the timings by at most this.
MAX_ENCODED_DRIFT_MS = 2 * ctc.MS_PER_FRAME
# The older BSB copy Berea used before 0.3.0, pinned as in build_db.dart. Souer's recording
# follows it, not the current bsb.txt (see revision.py), so verses are placed by its words.
READ_TEXT_SHA256 = "bdedd6c2de31b1c729a5952a2cdc383b1f1396d1e9941d0b2cda2b997e22a8fb"


def chapter_range(spec: str) -> range:
    first, _, last = spec.partition("-")
    return range(int(first), int(last or first) + 1)


def official_text(db: str, bsb_txt: str, book: int, chapter: int) -> list[tuple[int, str]]:
    """The app's verses, refused unless they are exactly the pinned official bsb.txt."""
    verses = db_chapter(db, book, chapter)
    official = load_official(bsb_txt)
    name = {n: b for b, n in book_numbers(official).items()}[book]
    expected = [(v, t) for (b, c, v), t in official.items() if b == name and c == chapter]
    if verses != expected:
        raise ValueError(f"book {book} chapter {chapter}: the database is not the official bsb.txt")
    return verses


@cache
def load_official(bsb_txt: str) -> dict[tuple[str, int, int], str]:
    return bsb_verses(Path(bsb_txt).read_text(encoding="utf-8"))


@cache
def load_read_text(path: str) -> dict[tuple[int, int, int], str]:
    data = Path(path).read_bytes()
    if hashlib.sha256(data).hexdigest() != READ_TEXT_SHA256:
        raise ValueError(f"{path} does not match its pinned SHA-256")
    return csv_verses(path)


def read_differently(path: str, book: int, chapter: int, verses) -> dict[int, str]:
    """The verses whose spoken words differ in the text the narrator read; none without one."""
    if not path:
        return {}
    read = load_read_text(path)
    return {
        v: read[(book, chapter, v)]
        for v, text in verses
        if words_of(read[(book, chapter, v)]) != words_of(text)
    }


def shift(words: list[list[int]], ms: int) -> list[list[int]]:
    return [[v, i, s + ms, e + ms] for v, i, s, e in words]


def verify_encoded(m4a: str, verses, read, words, model) -> dict:
    """Re-aligns the encoded file itself; its word starts must land where the timings say."""
    processor, net, vocab = model
    logp = ctc.emissions(processor, net, encode.decode(m4a))
    again = align.align_chapter(logp, verses, vocab, read)
    deltas = [(a[0], abs(a[2] - b[2])) for a, b in zip(words, again["words"])]
    as_written = [d for verse, d in deltas if verse not in read] or [0]
    return {
        "median_ms": statistics.median(d for _, d in deltas),
        "max_ms": max(d for _, d in deltas),
        # Times inside a verse read differently are approximate, so they are kept apart.
        "max_ms_as_written": max(as_written),
    }


def run_chapter(book: int, chapter: int, args, model) -> dict:
    processor, net, vocab = model
    verses = official_text(args.db, args.bsb, book, chapter)
    read = read_differently(args.read_text, book, chapter, verses)
    mp3 = fetch.fetch_chapter(NARRATOR, book, chapter, BUILD / "src")
    started = time.monotonic()
    pcm = encode.decode(str(mp3))
    result = align.align_chapter(ctc.emissions(processor, net, pcm), verses, vocab, read)
    aligned = time.monotonic()
    m4a = BUILD / "m4a" / f"{book:02d}" / f"{chapter:03d}.m4a"
    m4a.parent.mkdir(parents=True, exist_ok=True)
    # Encoded beside the final name, so a chapter that fails a check never leaves new audio
    # next to old timings.
    pending = m4a.with_name(f"{m4a.stem}.pending.m4a")
    encode.encode(str(mp3), str(pending))
    lag = encode.lag_ms(pcm, encode.decode(str(pending)))
    if abs(lag) > encode.MAX_RESIDUAL_LAG_MS:
        raise ValueError(f"{m4a}: encoded audio is {lag} ms off its source after the edit list")
    words = shift(result["words"], round(lag))
    check = verify_encoded(str(pending), verses, read, words, model)
    if max(check["median_ms"], check["max_ms_as_written"]) > MAX_ENCODED_DRIFT_MS:
        raise ValueError(f"{m4a}: the encoded file does not match its timings: {check}")
    timings = {"book": book, "chapter": chapter, "narrator": NARRATOR, "words": words}
    qa = {
        **{k: result[k] for k in ("verses", "moved_between_passes", "read_differently", "units")},
        "audio_ms": len(pcm) * encode.MS_PER_SECOND // ctc.SAMPLE_RATE,
        "align_seconds": aligned - started,
        "lag_ms": lag,
        "raw_lag_ms": encode.lag_ms(pcm, encode.decode(str(pending), ignore_editlist=True)),
        "encoded_check": check,
        "verse_count": len(verses),
        "m4a_sha256": hashlib.sha256(pending.read_bytes()).hexdigest(),
    }
    for kind, data in (("timings", timings), ("qa", qa)):
        out = BUILD / kind / f"{book:02d}" / f"{chapter:03d}.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(data, separators=(",", ":")))
    pending.rename(m4a)
    return qa


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("book", type=int)
    parser.add_argument("chapters", type=chapter_range)
    parser.add_argument("--db", default=DB)
    parser.add_argument("--bsb", default=BSB_TXT)
    parser.add_argument("--read-text", default=READ_TEXT, help='text read aloud; "" for none')
    args = parser.parse_args()
    model = ctc.load_model()
    for chapter in args.chapters:
        qa = run_chapter(args.book, chapter, args, model)
        worst = max(v["wer"] for v in qa["verses"])
        print(
            f"{args.book}:{chapter} {qa['audio_ms'] / encode.MS_PER_SECOND:.0f}s audio, aligned in "
            f"{qa['align_seconds']:.1f}s, lag {qa['lag_ms']} ms, worst verse WER {worst:.2f}, "
            f"encoded check median {qa['encoded_check']['median_ms']} ms",
            flush=True,
        )


if __name__ == "__main__":
    main()
