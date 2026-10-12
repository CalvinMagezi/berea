import hashlib
import json
import sqlite3
import subprocess
from contextlib import closing

import pytest

import pack

BOOK = 43
TONE_SECONDS = "1"
# A one-chapter book: verse 1 has two words, verse 2 one.
VERSES = [(1, "In the"), (2, "beginning")]
WORDS = [[1, 0, 100, 300], [1, 1, 300, 300], [2, 0, 400, 900]]


@pytest.fixture
def db(tmp_path):
    path = tmp_path / "berea.sqlite"
    with closing(sqlite3.connect(path)) as con:
        con.execute("CREATE TABLE verses(translation, book, chapter, verse, text)")
        con.executemany(
            "INSERT INTO verses VALUES ('BSB', ?, 1, ?, ?)", [(BOOK, v, t) for v, t in VERSES]
        )
        con.commit()
    return path


@pytest.fixture
def build(tmp_path):
    """One encoded chapter with its timings and QA, as pilot.py leaves them."""
    for kind in ("m4a", "timings", "qa"):
        (tmp_path / kind / f"{BOOK:02d}").mkdir(parents=True)
    m4a = tmp_path / "m4a" / f"{BOOK:02d}" / "001.m4a"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=duration=" + TONE_SECONDS,
         "-c:a", "aac", "-ac", "1", str(m4a)],
        check=True,
    )
    write_timings(tmp_path, WORDS)
    qa = {"raw_lag_ms": 88.0, "m4a_sha256": hashlib.sha256(m4a.read_bytes()).hexdigest()}
    (tmp_path / "qa" / f"{BOOK:02d}" / "001.json").write_text(json.dumps(qa))
    return tmp_path


def write_timings(build, words):
    timings = {"book": BOOK, "chapter": 1, "narrator": "souer", "words": words}
    (build / "timings" / f"{BOOK:02d}" / "001.json").write_text(json.dumps(timings))


def test_pack_round_trip(build, db, tmp_path):
    entry = pack.build_pack(BOOK, "souer", build, tmp_path / "out", db)
    path = tmp_path / "out" / entry["file"]
    assert entry["id"] == "souer-43" and entry["bytes"] == path.stat().st_size
    with closing(sqlite3.connect(path)) as con:
        meta = dict(con.execute("SELECT key, value FROM meta"))
        timings = con.execute("SELECT timings FROM chapters WHERE chapter = 1").fetchone()[0]
    assert meta["format"] == pack.PACK_FORMAT and meta["release"] == "audio-1"
    assert meta["priming_ms"] == "88.0"
    assert json.loads(timings)["words"][2] == [2, 0, 400, 900]


def test_pack_refuses_a_verse_missing_its_last_word(build, db, tmp_path):
    write_timings(build, WORDS[:1] + WORDS[2:])
    with pytest.raises(ValueError):
        pack.build_pack(BOOK, "souer", build, tmp_path / "out", db)


def test_pack_refuses_audio_the_timings_were_not_made_for(build, db, tmp_path):
    (build / "m4a" / f"{BOOK:02d}" / "001.m4a").write_bytes(b"other audio")
    with pytest.raises(ValueError):
        pack.build_pack(BOOK, "souer", build, tmp_path / "out", db)


def test_pack_refuses_a_missing_chapter(build, db, tmp_path):
    with closing(sqlite3.connect(db)) as con:
        con.execute("INSERT INTO verses VALUES ('BSB', ?, 2, 1, 'And')", (BOOK,))
        con.commit()
    with pytest.raises(ValueError):
        pack.build_pack(BOOK, "souer", build, tmp_path / "out", db)


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
    timings = {"book": BOOK, "chapter": 1, "words": words}
    with pytest.raises(ValueError):
        pack._check_chapter("p", BOOK, 1, 1000, b"audio", timings)
