"""Which BSB revision did the narrator read? python revision.py 43 19

For every aligned verse whose official text differs from an older BSB copy (the scrollmapper
CSV Berea used before 0.3.0), scores what the model heard against both readings."""

import argparse
import json

import ctc
from paths import BSB_TXT, BUILD, READ_TEXT
from pilot import load_official, load_read_text
from text import book_numbers, words_of



def compare(book: int, old: dict, official: dict) -> list[dict]:
    """Scores over the verse and its neighbours, so a verse edge placed a word off cancels out."""
    rows = []
    for qa_path in sorted((BUILD / "qa" / f"{book:02d}").glob("*.json")):
        chapter = int(qa_path.stem)
        heard = {v["verse"]: v["heard"].split() for v in json.loads(qa_path.read_text())["verses"]}
        order = list(heard)
        for k, verse in enumerate(order):
            key = (book, chapter, verse)
            if old[key] == official[key]:
                continue
            window = order[max(0, k - 1) : k + 2]
            said = [w for v in window for w in heard[v]]
            rows.append({
                "ref": f"{book}:{chapter}:{verse}",
                "official_errors": _errors(official, book, chapter, window, said),
                "old_errors": _errors(old, book, chapter, window, said),
                "official": official[key],
                "old": old[key],
                "heard": " ".join(heard[verse]),
            })
    return rows


def _errors(text: dict, book: int, chapter: int, window: list[int], said: list[str]) -> int:
    expected = [w for v in window for w in words_of(text[(book, chapter, v)])]
    return ctc.edit_distance(expected, said)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old-csv", default=READ_TEXT)
    parser.add_argument("books", type=int, nargs="+")
    parser.add_argument("--bsb", default=BSB_TXT)
    args = parser.parse_args()
    official_by_name = load_official(args.bsb)
    numbers = book_numbers(official_by_name)
    official = {(numbers[b], c, v): t for (b, c, v), t in official_by_name.items()}
    old = load_read_text(args.old_csv)
    verdicts: dict[str, int] = {}
    for book in args.books:
        for row in compare(book, old, official):
            o, n = row["official_errors"], row["old_errors"]
            words_differ = words_of(row["official"]) != words_of(row["old"])
            verdict = "official" if o < n else "old" if n < o else "tie"
            kind = f"{verdict} ({'words' if words_differ else 'punctuation only'})"
            verdicts[kind] = verdicts.get(kind, 0) + 1
            print(json.dumps({"verdict": kind, **row}, ensure_ascii=False))
    # pilot.py aligns by the older words; any "official (words)" here says that was wrong.
    print(json.dumps({"summary": verdicts}))


if __name__ == "__main__":
    main()
