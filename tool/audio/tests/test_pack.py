import json
import sqlite3
import subprocess

import pytest

import pack

BOOK = 43
CHAPTER = 3
TONE_SECONDS = "1"


@pytest.fixture
def build(tmp_path):
    """One encoded chapter with its timings and QA, as pilot.py leaves them."""
    for kind in ("m4a", "timings", "qa"):
        (tmp_path / kind / f"{BOOK:02d}").mkdir(parents=True)
    m4a = tmp_path / "m4a" / f"{BOOK:02d}" / f"{CHAPTER:03d}.m4a"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=" + TONE_SECONDS,
         "-c:a", "aac", "-ac", "1", str(m4a)],
        check=True,
    )
    words = [[1, 0, 100, 300], [1, 1, 300, 300], [2, 0, 400, 900]]
    timings = {"book": BOOK, "chapter": CHAPTER, "narrator": "souer", "words": words}
    (tmp_path / "timings" / f"{BOOK:02d}" / f"{CHAPTER:03d}.json").write_text(json.dumps(timings))
    (tmp_path / "qa" / f"{BOOK:02d}" / f"{CHAPTER:03d}.json").write_text('{"raw_lag_ms": 88.0}')
    return tmp_path


def test_pack_round_trip(build, tmp_path):
    entry = pack.build_pack(BOOK, "souer", build, tmp_path / "out")
    path = tmp_path / "out" / entry["file"]
    assert entry["id"] == "souer-43" and entry["bytes"] == path.stat().st_size
    with sqlite3.connect(path) as db:
        meta = dict(db.execute("SELECT key, value FROM meta"))
        timings = db.execute("SELECT timings FROM chapters WHERE chapter = 3").fetchone()[0]
    assert meta["format"] == pack.PACK_FORMAT and meta["release"] == "audio-1"
    assert meta["priming_ms"] == "88.0"
    assert json.loads(timings)["words"][2] == [2, 0, 400, 900]


@pytest.mark.parametrize(
    "words",
    [
        [[1, 0, 100, 300], [1, 2, 300, 400]],  # a skipped wordIndex
        [[1, 0, 100, 300], [1, 1, 250, 400]],  # starts before the last word ended
        [[2, 0, 100, 300], [1, 0, 300, 400]],  # verses out of order
        [[1, 0, 100, 5000]],  # past the end of the audio
    ],
)
def test_check_refuses_broken_timings(words):
    timings = {"book": BOOK, "chapter": CHAPTER, "words": words}
    with pytest.raises(ValueError):
        pack._check_chapter("p", BOOK, CHAPTER, 1000, b"audio", timings)
