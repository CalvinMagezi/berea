"""Verse text as the app shows it, and the words a narrator speaks for each of its tokens."""

import csv
import re
import sqlite3
from contextlib import closing

BSB_HEADER = "Verse\t"
BSB_LINE = re.compile(r"^(.+) (\d+):(\d+)\t(.*)$")
BOM = "\ufeff"

# The aligner's alphabet (wav2vec2-base-960h): capital letters and the apostrophe.
SPOKEN = re.compile(r"[A-Z']+")
APOSTROPHES = "\u2019'"
# Dashes and hyphens join two spoken words inside one whitespace token.
JOINERS = re.compile(r"[\u2014\u2013-]")
DIGITS = re.compile(r"\d[\d,]*")
LETTER = re.compile(r"[A-Za-z]")

ONES = (
    "ZERO ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN ELEVEN TWELVE THIRTEEN FOURTEEN "
    "FIFTEEN SIXTEEN SEVENTEEN EIGHTEEN NINETEEN"
).split()
TENS = "_ _ TWENTY THIRTY FORTY FIFTY SIXTY SEVENTY EIGHTY NINETY".split()
SCALES = ((1_000_000, "MILLION"), (1_000, "THOUSAND"), (100, "HUNDRED"))
TEEN_LIMIT = 20
TEN = 10


def bsb_verses(text: str) -> dict[tuple[str, int, int], str]:
    """Parses bereanbible.com bsb.txt exactly as the app's importer (parseBsbText) does."""
    text = text.removeprefix(BOM)
    lines = text.splitlines()
    header = next((i for i, l in enumerate(lines) if l.startswith(BSB_HEADER)), None)
    if header is None:
        raise ValueError('expected a "Verse<TAB>..." header row')
    verses = {}
    for line in lines[header + 1 :]:
        if not line.strip():
            continue
        m = BSB_LINE.match(line)
        if m is None:
            raise ValueError(f"not a verse line: {line!r}")
        verses[(m[1], int(m[2]), int(m[3]))] = m[4].strip()
    return verses


def book_numbers(verses: dict[tuple[str, int, int], str]) -> dict[str, int]:
    """bsb.txt lists books in canonical order, so the n-th name seen is book n."""
    numbers: dict[str, int] = {}
    for name, _, _ in verses:
        numbers.setdefault(name, len(numbers) + 1)
    return numbers


def csv_verses(path: str) -> dict[tuple[int, int, int], str]:
    """A `Book,Chapter,Verse,Text` Bible, books numbered by their order in the file."""
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))[1:]
    numbers: dict[str, int] = {}
    for row in rows:
        numbers.setdefault(row[0], len(numbers) + 1)
    return {(numbers[r[0]], int(r[1]), int(r[2])): r[3].strip() for r in rows}


def words_of(text: str) -> list[str]:
    """Every spoken word of a verse, in order."""
    return [w for token in tokens(text) for w in spoken_words(token)]


def db_chapter(db_path: str, book: int, chapter: int) -> list[tuple[int, str]]:
    """The BSB verses of one chapter from the app's database, in verse order."""
    with closing(sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)) as db:
        rows = db.execute(
            "SELECT verse, text FROM verses WHERE translation = 'BSB' AND book = ? AND chapter = ? "
            "ORDER BY verse",
            (book, chapter),
        ).fetchall()
    if not rows:
        raise ValueError(f"no BSB verses for book {book} chapter {chapter}")
    return rows


def chapter_count(db_path, book: int) -> int:
    with closing(sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)) as db:
        (count,) = db.execute(
            "SELECT MAX(chapter) FROM verses WHERE translation = 'BSB' AND book = ?", (book,)
        ).fetchone()
    if count is None:
        raise ValueError(f"no BSB chapters for book {book}")
    return count


def tokens(verse_text: str) -> list[str]:
    """The app's words: the verse text split on whitespace, which wordIndex counts."""
    return verse_text.split()


def number_words(n: int) -> list[str]:
    """American cardinal words without "and", the way BSB numbers are usually read."""
    if n < TEEN_LIMIT:
        return [ONES[n]]
    if n < 100:
        tens, ones = divmod(n, TEN)
        return [TENS[tens]] + ([ONES[ones]] if ones else [])
    for size, name in SCALES:
        if n >= size:
            head, rest = divmod(n, size)
            return number_words(head) + [name] + (number_words(rest) if rest else [])
    raise AssertionError("unreachable")


def spoken_words(token: str) -> list[str]:
    """The words a narrator says for one token, in the aligner's alphabet. May be empty."""
    words: list[str] = []
    for part in JOINERS.split(token):
        words += _part_words(part)
    return words


def _part_words(part: str) -> list[str]:
    digits = DIGITS.search(part)
    if digits:
        return number_words(int(digits[0].replace(",", "")))
    chars = []
    for i, c in enumerate(part):
        if c not in APOSTROPHES:
            chars.append(c)
        # An apostrophe between letters is spoken ("God's"); elsewhere it closes a quote.
        elif _between_letters(part, i):
            chars.append("'")
    return SPOKEN.findall("".join(chars).upper())


def _between_letters(s: str, i: int) -> bool:
    return 0 < i < len(s) - 1 and bool(LETTER.match(s[i - 1])) and bool(LETTER.match(s[i + 1]))
