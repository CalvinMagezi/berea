import numpy as np
import pytest

import align
import ctc
import encode

CHARS = ["<pad>", "|", "'"] + [chr(c) for c in range(ord("A"), ord("Z") + 1)]
VOCAB = ctc.Vocab({c: i for i, c in enumerate(CHARS)})
CONFIDENT = np.log(0.97)
UNSURE = np.log(0.03 / (len(CHARS) - 1))


def emissions_for(frames: list[str]) -> np.ndarray:
    """Synthetic log-probabilities: each frame is sure of one symbol ("" is a blank)."""
    logp = np.full((len(frames), len(CHARS) + 1), UNSURE, np.float32)
    for t, symbol in enumerate(frames):
        logp[t, VOCAB.char_to_id.get(symbol, ctc.BLANK)] = CONFIDENT
    logp[:, VOCAB.star] = 0.0
    return logp


def speak(*words: str, gap: int = 2) -> list[str]:
    frames = []
    for word in words:
        for c in word:
            frames += [c, ""]
        frames += ["|"] + [""] * gap
    return frames


def test_viterbi_finds_each_spike():
    logp = emissions_for(["", "A", "", "", "B", "B", ""])
    assert ctc.viterbi(logp, VOCAB.word_ids("AB")) == [(1, 1), (4, 5)]


def test_viterbi_needs_a_blank_between_repeated_letters():
    logp = emissions_for(["L", "", "L"])
    assert ctc.viterbi(logp, VOCAB.word_ids("LL")) == [(0, 0), (2, 2)]


def test_chapter_alignment_skips_a_spoken_intro_and_times_every_token():
    intro = speak("JOHN", "CHAPTER", "ONE")
    verse_1 = speak("IN", "THE", "BEGINNING")
    verse_2 = speak("WENT", "NOT")
    logp = emissions_for(intro + verse_1 + verse_2)
    verses = [(1, "In the beginning\u2014"), (2, "went\u2014not \u2014")]
    words = align.align_chapter(logp, verses, VOCAB)["words"]
    assert [(v, i) for v, i, _, _ in words] == [(1, 0), (1, 1), (1, 2), (2, 0), (2, 1)]
    first_frame = len(intro)
    assert words[0][2] == first_frame * ctc.MS_PER_FRAME
    starts = [s for _, _, s, _ in words]
    assert starts == sorted(starts)
    # A dash on its own is silent: zero length, where the word before it ended.
    assert words[4][2] == words[4][3] == words[3][3]


def test_verse_qa_reports_word_errors_against_what_was_heard():
    logp = emissions_for(speak("IN", "THE", "BEGINNING"))
    qa = align.align_chapter(logp, [(1, "In the beginning")], VOCAB)["verses"][0]
    assert qa["wer"] == 0
    assert qa["heard"] == "IN THE BEGINNING"


def test_a_verse_read_differently_never_moves_the_next_verse():
    """John 12:17 was read in an older word order; 12:18 must still start on its first word."""
    intro = speak("JOHN", "CHAPTER", "TWELVE")
    read_text = "Meanwhile many people continued to testify that they had been there"
    read_1 = speak(*read_text.upper().split())
    verse_2 = speak("THAT", "IS", "WHY")
    logp = emissions_for(intro + read_1 + verse_2)
    official_1 = "Meanwhile many people who had been there continued to testify."
    verses = [(1, official_1), (2, "That is why")]
    verse_2_start = (len(intro) + len(read_1)) * ctc.MS_PER_FRAME
    plain = align.align_chapter(logp, verses, VOCAB)["words"]
    assert next(w for w in plain if w[0] == 2)[2] < verse_2_start, "the case must show the spill"
    result = align.align_chapter(logp, verses, VOCAB, read={1: read_text})
    words = result["words"]
    assert next(w for w in words if w[0] == 2)[2] == verse_2_start
    first_verse = [w for w in words if w[0] == 1]
    assert len(first_verse) == 10
    # The reordered words spread over what was said instead of collapsing to single frames.
    assert first_verse[-1][3] - first_verse[0][2] > len(read_1) // 2 * ctc.MS_PER_FRAME
    assert result["read_differently"] == [1]


def test_edit_distance_counts_word_changes():
    assert ctc.edit_distance("A B C".split(), "A X C D".split()) == 2


def test_lag_finds_a_known_delay():
    rng = np.random.default_rng(1)
    source = rng.standard_normal(ctc.SAMPLE_RATE * 2).astype(np.float32)
    delay = 37
    late = np.concatenate([np.zeros(delay, np.float32), source])
    assert encode.lag_ms(source, late) == pytest.approx(delay * 1000 / ctc.SAMPLE_RATE)
