"""Two-pass alignment of one narrated chapter: verses over the chapter, then words in each verse."""

from dataclasses import dataclass

import numpy as np

import ctc
from text import spoken_words, tokens

# Pass 2 looks this far past each pass 1 verse edge, with wildcards to absorb the neighbours.
VERSE_MARGIN_FRAMES = 25
# A word whose two passes disagree by more than this is counted in the QA report.
PASS_AGREEMENT_FRAMES = 2


@dataclass
class Unit:
    """One spoken word: verse, index of its whitespace token in the verse, letters."""

    verse: int
    token: int
    word: str
    start: int = -1
    end: int = -1


def units_of(verses: list[tuple[int, str]]) -> list[Unit]:
    return [
        Unit(verse, i, word)
        for verse, text in verses
        for i, token in enumerate(tokens(text))
        for word in spoken_words(token)
    ]


def targets_of(
    units: list[Unit], vocab: ctc.Vocab, wildcards: bool = True
) -> tuple[list[int], list[tuple[int, int]]]:
    """The words joined by separators, between optional wildcards; each word's slice of them."""
    targets = [vocab.star] if wildcards else []
    slices = []
    for i, unit in enumerate(units):
        if i:
            targets.append(vocab.separator)
        ids = vocab.word_ids(unit.word)
        slices.append((len(targets), len(targets) + len(ids)))
        targets += ids
    if wildcards:
        targets.append(vocab.star)
    return targets, slices


def place(
    units: list[Unit], logp: np.ndarray, vocab: ctc.Vocab, offset: int = 0, wildcards: bool = True
) -> None:
    """Sets each unit's first frame and its end frame (exclusive) from one forced alignment."""
    targets, slices = targets_of(units, vocab, wildcards)
    spans = ctc.viterbi(logp, targets)
    for unit, (lo, hi) in zip(units, slices):
        unit.start = offset + spans[lo][0]
        unit.end = offset + spans[hi - 1][1] + 1


def align_chapter(
    logp: np.ndarray,
    verses: list[tuple[int, str]],
    vocab: ctc.Vocab,
    read: dict[int, str] | None = None,
) -> dict:
    """Word timings in frames for every token of every verse, and the QA numbers behind them.

    [read] holds the text the narrator actually read for verses where it differs from [verses];
    pass 1 places verses by what was spoken, pass 2 times the app's words inside them."""
    read = read or {}
    spoken = units_of([(v, read.get(v, t)) for v, t in verses])
    if not spoken:
        raise ValueError("the chapter has no spoken words")
    place(spoken, logp, vocab)
    edges = {v: (us[0].start, us[-1].end) for v, us in _group(spoken).items()}
    units = units_of(verses)
    by_verse = _group(units)
    order = list(by_verse)
    for k, verse in enumerate(order):
        _place_verse(by_verse[verse], logp, vocab, edges, order, k, verse in read)
    _keep_in_order(units)
    moved = sum(
        abs(by_verse[v][0].start - s) > PASS_AGREEMENT_FRAMES
        or abs(by_verse[v][-1].end - e) > PASS_AGREEMENT_FRAMES
        for v, (s, e) in edges.items()
    )
    return {
        "words": _token_times(verses, units),
        "verses": [_verse_qa(v, us, logp, vocab) for v, us in by_verse.items()],
        "moved_between_passes": moved,
        "read_differently": sorted(read),
        "units": len(units),
    }


def _place_verse(units, logp, vocab, edges, order, k, overridden) -> None:
    """Pass 2 for one verse, never reaching past its neighbours' pass 1 edges. A verse read
    differently from its text is held to exactly its spoken span with no wildcards, so its
    words spread over what was said instead of being squeezed aside."""
    start, end = edges[order[k]]
    if overridden:
        place(units, logp[start:end], vocab, offset=start, wildcards=False)
        return
    previous_end = edges[order[k - 1]][1] if k else 0
    next_start = edges[order[k + 1]][0] if k + 1 < len(order) else len(logp)
    lo = max(previous_end, start - VERSE_MARGIN_FRAMES)
    hi = min(next_start, end + VERSE_MARGIN_FRAMES)
    place(units, logp[lo:hi], vocab, offset=lo)


def _group(units: list[Unit]) -> dict[int, list[Unit]]:
    groups: dict[int, list[Unit]] = {}
    for unit in units:
        groups.setdefault(unit.verse, []).append(unit)
    return groups


def _keep_in_order(units: list[Unit]) -> None:
    """Verses aligned apart may overlap at their edges; a word never starts before the last ends."""
    previous_end = 0
    for unit in units:
        unit.start = max(unit.start, previous_end)
        unit.end = max(unit.end, unit.start + 1)
        previous_end = unit.end


def _token_times(verses: list[tuple[int, str]], units: list[Unit]) -> list[list[int]]:
    """[verse, wordIndex, startMs, endMs] for every token. A silent token (a lone dash) gets a
    zero-length time where the previous word ended."""
    spans: dict[tuple[int, int], tuple[int, int]] = {}
    for unit in units:
        key = (unit.verse, unit.token)
        start, end = spans.get(key, (unit.start, unit.end))
        spans[key] = (min(start, unit.start), max(end, unit.end))
    words = []
    cursor = units[0].start
    for verse, text in verses:
        for i in range(len(tokens(text))):
            start, end = spans.get((verse, i), (cursor, cursor))
            cursor = end
            words.append([verse, i, start * ctc.MS_PER_FRAME, end * ctc.MS_PER_FRAME])
    return words


def _verse_qa(verse: int, units: list[Unit], logp: np.ndarray, vocab: ctc.Vocab) -> dict:
    heard = ctc.greedy_words(logp[units[0].start : units[-1].end], vocab)
    expected = [u.word for u in units]
    errors = ctc.edit_distance(expected, heard)
    return {
        "verse": verse,
        "start_ms": units[0].start * ctc.MS_PER_FRAME,
        "end_ms": units[-1].end * ctc.MS_PER_FRAME,
        "wer": errors / len(expected),
        "heard": " ".join(heard),
        "durations_ms": [(u.end - u.start) * ctc.MS_PER_FRAME for u in units],
    }
