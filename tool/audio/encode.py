"""Decoding for the aligner, HE-AAC encoding for the app, and the encoder delay between them."""

import subprocess

import numpy as np

import ctc

# AAC-LC, not HE-AAC: HE-AAC's SBR delay differs by decoder (measured 0, 48 and 70 ms on one
# file), while every decoder that honours the edit list plays LC with zero offset. AudioToolbox
# (macOS only) because it beats ffmpeg's own AAC encoder at this bitrate.
AAC_LC_PROFILE = "1"
ENCODER = [
    "-c:a", "aac_at", "-profile:a", AAC_LC_PROFILE, "-b:a", "32k", "-ac", "1", "-ar", "24000"
]
ENCODER_LABEL = "AAC-LC (AudioToolbox aac_at), mono, 24 kHz, 32 kbps CBR, .m4a"
# An encoded file may be later than its source by at most this much after the edit list.
MAX_RESIDUAL_LAG_MS = ctc.MS_PER_FRAME
# The delay is searched within this window and measured over this much audio.
MAX_LAG_SAMPLES = ctc.SAMPLE_RATE // 2
LAG_PROBE_SAMPLES = 60 * ctc.SAMPLE_RATE
MS_PER_SECOND = 1000


def decode(path: str, ignore_editlist: bool = False) -> np.ndarray:
    """Mono float PCM at the aligner's rate, exactly as the aligner and the check both see it."""
    flags = ["-ignore_editlist", "1"] if ignore_editlist else []
    out = subprocess.run(
        ["ffmpeg", "-v", "error", *flags, "-i", path, "-ac", "1", "-ar", str(ctc.SAMPLE_RATE),
         "-f", "f32le", "-"],
        capture_output=True,
        check=True,
    ).stdout
    return np.frombuffer(out, np.float32)


def encode(source: str, dest: str) -> None:
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", source, *ENCODER, "-movflags", "+faststart", dest],
        check=True,
    )


def lag_ms(reference: np.ndarray, encoded: np.ndarray) -> float:
    """How much later the encoded audio plays the same sound, from the cross-correlation peak."""
    a = reference[:LAG_PROBE_SAMPLES]
    b = encoded[:LAG_PROBE_SAMPLES]
    size = 1 << int(np.ceil(np.log2(len(a) + len(b))))
    corr = np.fft.irfft(np.fft.rfft(b, size) * np.conj(np.fft.rfft(a, size)), size)
    # Index k holds lag k; negative lags wrap to the end of the array.
    lags = np.concatenate([np.arange(MAX_LAG_SAMPLES + 1), np.arange(-MAX_LAG_SAMPLES, 0)])
    window = np.concatenate([corr[: MAX_LAG_SAMPLES + 1], corr[-MAX_LAG_SAMPLES:]])
    return float(lags[window.argmax()]) * MS_PER_SECOND / ctc.SAMPLE_RATE


def duration_ms(path: str) -> int:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
        capture_output=True,
        check=True,
        text=True,
    ).stdout
    return round(float(out) * MS_PER_SECOND)
