"""CTC emissions from wav2vec2-base-960h and a forced aligner with a wildcard token."""

import os

import numpy as np

MODEL = "facebook/wav2vec2-base-960h"
MODEL_CACHE = "build/audio/hf"
# Pinned so a rebuilt timing set comes from the same weights (Apache-2.0).
MODEL_REVISION = "22aad52d435eb6dbaf354bdad9b0da84ce7d6156"
SAMPLE_RATE = 16_000
# wav2vec2's feature encoder emits one frame per 320 samples: 20 ms.
SAMPLES_PER_FRAME = 320
MS_PER_FRAME = 1000 * SAMPLES_PER_FRAME // SAMPLE_RATE
# Long audio is run in windows; each keeps only its centre so every frame has context.
HOP_FRAMES = 1250
CONTEXT_FRAMES = 125
WORD_SEPARATOR = "|"
BLANK = 0
# Viterbi back pointers: stay on a state, step one state, or skip a blank.
STEPS = 3


class Vocab:
    def __init__(self, char_to_id: dict[str, int]):
        self.char_to_id = char_to_id
        self.id_to_char = {i: c for c, i in char_to_id.items()}
        self.separator = char_to_id[WORD_SEPARATOR]
        # The wildcard is one extra column after the model's own.
        self.star = len(char_to_id)

    def word_ids(self, word: str) -> list[int]:
        return [self.char_to_id[c] for c in word]


def load_model():
    # The model download stays under the gitignored build folder unless the caller says otherwise.
    os.environ.setdefault("HF_HOME", MODEL_CACHE)
    from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

    processor = Wav2Vec2Processor.from_pretrained(MODEL, revision=MODEL_REVISION)
    model = Wav2Vec2ForCTC.from_pretrained(MODEL, revision=MODEL_REVISION, use_safetensors=True)
    return processor, model.eval(), Vocab(processor.tokenizer.get_vocab())


def emissions(processor, model, pcm: np.ndarray) -> np.ndarray:
    """Log-probabilities per 20 ms frame plus a zero wildcard column: (frames, classes + 1)."""
    import torch

    hop = HOP_FRAMES * SAMPLES_PER_FRAME
    context = CONTEXT_FRAMES * SAMPLES_PER_FRAME
    kept = []
    for start in range(0, len(pcm), hop):
        lo = max(0, start - context)
        window = pcm[lo : start + hop + context]
        with torch.inference_mode():
            inputs = processor(window, sampling_rate=SAMPLE_RATE, return_tensors="pt").input_values
            logits = model(inputs).logits[0]
        logp = torch.log_softmax(logits, dim=-1).numpy()
        skip = (start - lo) // SAMPLES_PER_FRAME
        kept.append(logp[skip : skip + HOP_FRAMES])
    logp = np.concatenate(kept)
    # Log 1 for the wildcard: it may absorb any frame for free, but only where it is placed.
    return np.hstack([logp, np.zeros((len(logp), 1), np.float32)])


def viterbi(logp: np.ndarray, targets: list[int]) -> list[tuple[int, int]]:
    """Best CTC path of [targets] through [logp]; the first and last frame of each target.

    A wildcard at either end is optional: speech may start on the first frame."""
    ext = np.full(2 * len(targets) + 1, BLANK)
    ext[1::2] = targets
    states, frames = len(ext), len(logp)
    if frames < len(targets):
        raise ValueError(f"{len(targets)} tokens cannot fit in {frames} frames")
    can_skip = np.zeros(states, bool)
    can_skip[2:] = (ext[2:] != BLANK) & (ext[2:] != ext[:-2])
    # ponytail: back pointers cost frames x states bytes (Psalm 119 peaked at 2.8 GB); band it
    # if a longer chapter or a smaller machine needs it.
    back = np.zeros((frames, states), np.uint8)
    alpha = np.full(states, -np.inf, np.float32)
    star = logp.shape[1] - 1
    first = 4 if targets[0] == star else 2
    alpha[:first] = logp[0, ext[:first]]
    for t in range(1, frames):
        options = np.full((STEPS, states), -np.inf, np.float32)
        options[0] = alpha
        options[1, 1:] = alpha[:-1]
        options[2, 2:] = np.where(can_skip[2:], alpha[:-2], -np.inf)
        choice = options.argmax(0)
        back[t] = choice
        alpha = options[choice, np.arange(states)] + logp[t, ext]
    last = 4 if targets[-1] == star else 2
    state = int(states - last + alpha[-last:].argmax())
    if not np.isfinite(alpha[state]):
        raise ValueError("no CTC path fits these tokens in this audio")
    path = np.empty(frames, np.int64)
    for t in range(frames - 1, -1, -1):
        path[t] = state
        state -= int(back[t, state])
    return _token_spans(path, len(targets))


def _token_spans(path: np.ndarray, count: int) -> list[tuple[int, int]]:
    spans = [(-1, -1)] * count
    for t, state in enumerate(path):
        if state % 2 == 0:
            continue
        k = state // 2
        first = spans[k][0] if spans[k][0] >= 0 else t
        spans[k] = (first, t)
    return spans


def greedy_words(logp: np.ndarray, vocab: Vocab) -> list[str]:
    """What the model hears in these frames, ignoring the wildcard column."""
    best = logp[:, : vocab.star].argmax(1)
    chars = [
        vocab.id_to_char[i]
        for j, i in enumerate(best)
        if i != BLANK and (j == 0 or i != best[j - 1])
    ]
    text = "".join(c if c in "'" or c.isalpha() else WORD_SEPARATOR for c in chars)
    return [w for w in text.split(WORD_SEPARATOR) if w]


def edit_distance(a: list[str], b: list[str]) -> int:
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        prev, row[0] = row[0], i
        for j, y in enumerate(b, 1):
            prev, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, prev + (x != y))
    return row[-1]
