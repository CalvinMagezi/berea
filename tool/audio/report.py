"""QA numbers for aligned chapters: python report.py 43 19 [--fetch-biblehub]."""

import argparse
import json
import statistics
import time

import fetch
from paths import BUILD, DB
from text import db_chapter, tokens

WER_THRESHOLDS = (0.1, 0.25, 0.5)
WORST_SHOWN = 8
# A word longer than this, or a pause inside a verse longer than this, is worth a listen.
LONG_WORD_MS = 2000
LONG_PAUSE_MS = 3000
PERCENTILES = 100
P90, P99 = 90, 99
MS_PER_SECOND = 1000
MS_PER_HOUR = 3_600_000
# Bible Hub's verse timings have no licence: a cross-check kept under build/, never shipped.
BIBLEHUB = "https://biblehub.com/audio/player/timing_souer/{slug}_{chapter}.json"
BIBLEHUB_SLUGS = {19: "psalms", 43: "john"}
PAUSE_SECONDS = 1.0


def load(book: int, kind: str) -> dict[int, dict]:
    return {
        int(p.stem): json.loads(p.read_text())
        for p in sorted((BUILD / kind / f"{book:02d}").glob("*.json"))
    }


def spread(values: list[float]) -> dict:
    cuts = statistics.quantiles(values, n=PERCENTILES)
    return {
        "n": len(values),
        "mean": round(statistics.fmean(values), 3),
        "median": round(statistics.median(values), 3),
        "p90": round(cuts[P90 - 1], 3),
        "p99": round(cuts[P99 - 1], 3),
        "max": round(max(values), 3),
    }


def count_problems(book: int, chapter: int, timings: dict, qa: dict, db: str) -> list[str]:
    """Every verse in the app has every word timed, and the chapter has every verse. A verse
    the BSB leaves empty (John 5:4) has no words to time."""
    verses = db_chapter(db, book, chapter)
    spoken = [v for v, text in verses if tokens(text)]
    problems = timing_problems(book, chapter, timings["words"], db)
    if qa["verse_count"] != len(verses) or [v["verse"] for v in qa["verses"]] != spoken:
        problems.append(f"{book}:{chapter} verses {len(qa['verses'])} != {len(spoken)}")
    return problems


def timing_problems(book: int, chapter: int, words: list[list[int]], db: str) -> list[str]:
    """Each verse has exactly one timing per whitespace word, and no verse the app lacks."""
    timed: dict[int, int] = {}
    for verse, _, _, _ in words:
        timed[verse] = timed.get(verse, 0) + 1
    expected = {verse: len(tokens(text)) for verse, text in db_chapter(db, book, chapter)}
    return [
        f"{book}:{chapter}:{verse} has {timed.get(verse, 0)} timed words, expected {count}"
        for verse, count in {**{v: 0 for v in timed}, **expected}.items()
        if timed.get(verse, 0) != count
    ]


def duration_flags(timings: dict) -> dict:
    words = timings["words"]
    long_words = [w for w in words if w[3] - w[2] > LONG_WORD_MS]
    pauses = [
        b for a, b in zip(words, words[1:]) if a[0] == b[0] and b[2] - a[3] > LONG_PAUSE_MS
    ]
    return {"long_words": long_words, "long_pauses": pauses}


def touching_verses(qa: dict) -> list[int]:
    """Verses that start on the frame the previous one ended: a sign one spilled into the next."""
    pairs = zip(qa["verses"], qa["verses"][1:])
    return [b["verse"] for a, b in pairs if b["start_ms"] <= a["end_ms"]]


def biblehub_deltas(book: int, chapter: int, qa: dict, download: bool) -> list[float]:
    """Seconds from each Bible Hub verse start to our pause before that verse (0 inside it).
    Their start may sit anywhere in the pause; ours is the first word's onset."""
    path = BUILD / "biblehub" / f"{book:02d}-{chapter:03d}.json"
    if not path.exists() and download and book in BIBLEHUB_SLUGS:
        time.sleep(PAUSE_SECONDS)
        url = BIBLEHUB.format(slug=BIBLEHUB_SLUGS[book], chapter=chapter)
        path.parent.mkdir(parents=True, exist_ok=True)
        with fetch.get(url) as r:
            path.write_bytes(r.read())
    if not path.exists():
        return []
    theirs = {v["v"]: v["start"] for v in json.loads(path.read_text())["verses"]}
    deltas = []
    previous_end = 0.0
    for v in qa["verses"]:
        start, end = v["start_ms"] / MS_PER_SECOND, v["end_ms"] / MS_PER_SECOND
        if v["verse"] in theirs:
            t = theirs[v["verse"]]
            deltas.append(max(previous_end - t, t - start, 0.0))
        previous_end = end
    return deltas


def book_report(book: int, args) -> dict:
    timings, qas = load(book, "timings"), load(book, "qa")
    verses, problems, durations, deltas, flags, touching = [], [], [], [], [], []
    for chapter, qa in qas.items():
        verses += [{**v, "chapter": chapter} for v in qa["verses"]]
        problems += count_problems(book, chapter, timings[chapter], qa, args.db)
        durations += [d for v in qa["verses"] for d in v["durations_ms"]]
        deltas += biblehub_deltas(book, chapter, qa, args.fetch_biblehub)
        flags.append(duration_flags(timings[chapter]))
        touching += [f"{chapter}:{v}" for v in touching_verses(qa)]
    wers = [v["wer"] for v in verses]
    worst = sorted(verses, key=lambda v: -v["wer"])[:WORST_SHOWN]
    return {
        "book": book,
        "chapters": len(qas),
        "verses": len(verses),
        "count_problems": problems,
        "verse_wer": spread(wers),
        "verses_over": {str(t): sum(w > t for w in wers) for t in WER_THRESHOLDS},
        "worst": [(v["chapter"], v["verse"], round(v["wer"], 2), v["heard"]) for v in worst],
        "word_ms": spread(durations),
        "long_words": sum(len(f["long_words"]) for f in flags),
        "long_pauses": sum(len(f["long_pauses"]) for f in flags),
        "moved_between_passes": sum(q["moved_between_passes"] for q in qas.values()),
        "read_differently": [f"{c}:{v}" for c, q in qas.items() for v in q["read_differently"]],
        "touching_verses": touching,
        "lag_ms": sorted({q["lag_ms"] for q in qas.values()}),
        "raw_lag_ms": sorted({q["raw_lag_ms"] for q in qas.values()}),
        "encoded_check_median_ms": spread([q["encoded_check"]["median_ms"] for q in qas.values()]),
        "encoded_check_max_ms": max(q["encoded_check"]["max_ms"] for q in qas.values()),
        "encoded_check_max_ms_as_written": max(
            q["encoded_check"]["max_ms_as_written"] for q in qas.values()
        ),
        "biblehub_start_delta_s": spread([abs(d) for d in deltas]) if deltas else None,
        "audio_hours": sum(q["audio_ms"] for q in qas.values()) / MS_PER_HOUR,
        "align_seconds": sum(q["align_seconds"] for q in qas.values()),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("books", type=int, nargs="+")
    parser.add_argument("--db", default=DB)
    parser.add_argument("--fetch-biblehub", action="store_true")
    args = parser.parse_args()
    for book in args.books:
        print(json.dumps(book_report(book, args), indent=1))


if __name__ == "__main__":
    main()
