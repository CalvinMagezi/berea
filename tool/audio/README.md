# Narration word timings (build time only)

Python tooling that turns the CC0 Berean Standard Bible narration into per-book audio packs
with word-level timings, for the read-along player. Nothing here ships in the app; the app
only downloads the finished packs, pinned by SHA-256, when the user asks.

## Licences

| Thing | Licence | Where it ends up |
|-------|---------|------------------|
| BSB narration by Bob Souer ([bereanbible.com/audio](https://bereanbible.com/audio/)) | CC0 1.0 | Re-encoded inside the packs |
| BSB text (`bsb.txt`, pinned in `build_db.dart`) | Public domain | Words to align, never copied into a pack |
| Word timings made here | **CC0 1.0** (our work, dedicated to the public domain) | Inside the packs |
| `facebook/wav2vec2-base-960h`, revision `22aad52` | Apache-2.0 | Build time only |
| PyTorch 2.8.0 | BSD-3-Clause | Build time only |
| Transformers 4.56.2 (and tokenizers, huggingface-hub, safetensors) | Apache-2.0 | Build time only |
| NumPy | BSD-3-Clause | Build time only |
| pytest | MIT | Tests only |
| ffmpeg (the local Homebrew build is GPLv3) and macOS AudioToolbox | Tools run as programs | Build time only |

No MMS checkpoint is used (they are CC-BY-NC). The CTC forced aligner is our own (`ctc.py`),
so no aligner package is needed. Bible Hub's verse timing files have no licence: `report.py`
can fetch a few into `build/audio/biblehub/` as a cross-check, and they are never committed or
shipped.

## Run

Needs `uv`, `ffmpeg` on the path, macOS (the encoder is AudioToolbox), the built
`assets/berea.sqlite`, the pinned `packages/harness/.cache/bsb.txt` and the older BSB copy
`packages/harness/.cache/BSB-scrollmapper-e1b254c.csv` (`cd packages/harness && dart run
bin/build_db.dart` makes all three; the last is pinned by SHA-256 in both places). From the
repository root:

```
export UV_PROJECT_ENVIRONMENT=$PWD/build/audio/.venv
uv sync --directory tool/audio
build/audio/.venv/bin/python tool/audio/pilot.py 43 1-21    # John
build/audio/.venv/bin/python tool/audio/pilot.py 19 1-30    # Psalms 1-30
build/audio/.venv/bin/python tool/audio/pack.py 43          # build/audio-packs/souer-43.sqlite
build/audio/.venv/bin/python tool/audio/report.py 43 19 --fetch-biblehub
build/audio/.venv/bin/python tool/audio/revision.py packages/harness/.cache/BSB-scrollmapper-e1b254c.csv 43 19
build/audio/.venv/bin/python -m pytest tool/audio
```

`pilot.py` downloads each chapter (one at a time, two seconds apart, recorded with URL,
licence, SHA-256, size and duration in `build/audio/src/manifest.json`), aligns it, encodes
it, checks the encoded file and writes `build/audio/timings/<book>/<chapter>.json` and
`build/audio/qa/<book>/<chapter>.json`. The model is cached in `build/audio/hf`. Everything
under `build/` is gitignored.

## How it works

1. **Text.** The verses come from the app's database and must equal the pinned official
   `bsb.txt` exactly (the run stops otherwise). A verse's words are its text split on
   whitespace, which is what `wordIndex` counts. Souer read an older BSB revision (see
   below), so for each verse whose spoken words differ in the older copy, that copy is what
   pass 1 aligns (`--read-text ""` turns this off for a narrator who read the current text).
2. **Normalise** (`text.py`). Each whitespace token becomes zero or more spoken words in the
   model's alphabet (A to Z and the apostrophe): dashes and hyphens split words, digits become
   words ("153," is ONE HUNDRED FIFTY THREE), quotes and punctuation drop, and a curly
   apostrophe between letters is kept ("God's"). A token with no spoken word, such as a lone
   dash, still gets a timing: zero length where the previous word ended. Psalm superscriptions
   and "Selah" are part of the BSB verse text and the narrator reads them, so they are aligned
   like any other word.
3. **Emissions** (`ctc.py`). wav2vec2 runs over the chapter in 30 second windows that keep their
   middle 25 seconds, giving log-probabilities for every 20 ms frame. A wildcard column (log 1)
   is added for speech that is not in the text.
4. **Pass 1, verses over the chapter.** One forced alignment of the whole chapter's spoken
   words, with a wildcard at each end that absorbs the spoken intro ("John chapter three",
   "Psalm three") and any outro. This places every verse.
5. **Pass 2, words in each verse.** Each verse's official words are aligned again inside its
   pass 1 span plus up to 0.5 s each side (never past a neighbour's pass 1 edge), with
   wildcards at both ends. A verse read differently is held to exactly its spoken span with no
   wildcards, so its changed words spread over what was said and never spill into the next
   verse; inside such a verse the word times are approximate. A word starts at its first
   letter's frame and ends after its last letter's frame, so a player should highlight a word
   until the next one starts.
6. **Encode** (`encode.py`). AAC-LC, mono, 24 kHz, 32 kbps in `.m4a`, by AudioToolbox.
7. **Encoder delay.** The encoded file is decoded and cross-correlated with the exact audio
   that was aligned; the measured offset is added to every timing and the chapter fails if it
   is more than one frame (20 ms). Then the encoded file itself is aligned again and its word
   starts compared with the shipped timings.

### Why AAC-LC and not HE-AAC

HE-AAC is available here (`aac_at`, profile 4), but its SBR delay is decoder-specific.
Measured on John 3 against the aligned audio:

| Encoding | ffmpeg decoder | AudioToolbox decoder | `afconvert` | Edit list ignored |
|----------|----------------|----------------------|-------------|-------------------|
| HE-AAC 32 kbps | 69.7 ms | 0.0 ms | 47.9 ms | 117.6 ms |
| AAC-LC 32 kbps, 24 kHz | 0.0 ms | 0.0 ms | 0.0 ms | 88.0 ms |

No single offset makes HE-AAC timings right on every player; AAC-LC is exact on every decoder
that honours the MP4 edit list. ExoPlayer and AVPlayer are documented to honour it, but that
is not yet checked on a device: the read-along player (BEREA-005) should check one known word
on Android and iOS. The
pack records the priming a player that ignores the edit list would hear (`priming_ms`). The
cost is some treble at 32 kbps; the size is the same.

## Pack format

One SQLite file per book and narrator, `<narrator>-<book>.sqlite` (John: `souer-43.sqlite`),
published uncompressed (AAC does not gzip) on the GitHub release `audio-1`, so the app can use
`downloadPinned` with the URL, the SHA-256 and the size from `build/audio-packs/manifest.json`.

```
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE chapters(chapter INTEGER PRIMARY KEY, duration_ms INTEGER NOT NULL,
  audio BLOB NOT NULL, timings TEXT NOT NULL);
```

- `meta`: `format` (`1`), `pack` (`souer-43`), `book`, `narrator`, `release` (`audio-1`),
  `audio_licence`, `timings_licence`, `codec`, `aligner`, `priming_ms` (add it to every time only if
  the player ignores the edit list). Like the commentary packs, the app
  checks `format` and reads its id from `pack`.
- `chapters.audio`: the chapter's `.m4a` bytes; `duration_ms` is that file's duration.
- `chapters.timings`: JSON,
  `{"book":43,"chapter":3,"narrator":"souer","words":[[verse,wordIndex,startMs,endMs],...]}`,
  one entry for every whitespace-split word of every verse, in reading order, times in
  milliseconds from the start of that chapter's `.m4a`.

`manifest.json`:

```
{"release": "audio-1", "packs": [{"id": "souer-43", "file": "souer-43.sqlite", "book": 43,
  "narrator": "souer", "chapters": 21, "bytes": ..., "sha256": "..."}]}
```

`pack.py` checks every pack it writes: the meta stamp, one row per encoded chapter, and in each
chapter every verse's words numbered from 0 with none skipped and every time in order and
inside the audio.

## Which revision Souer read

The narration was recorded before the current official text (the openbible.com listing dates
the New Testament files 2022-09-18 and the Old Testament files 2023-08-25). `revision.py`
compares the pilot's verses where the current `bsb.txt` differs from the older copy Berea used
before 0.3.0: every verse whose wording differs was read in the older wording (for example
John 2:4 "Woman, why does this concern us?" and John 8:35 "A slave is not a permanent member of
the family"), and the rest differ only in punctuation. So the timings are made against the
current text the app shows, with each verse placed by what was actually said.

## QA

`report.py` gives, per book: verse word error rate (what the model hears in the verse's span
against the verse's words; names and spellings such as SELA count as errors, so it is an upper
bound), verses over 0.1, 0.25 and 0.5, the worst verses with what was heard, verse and word
counts against the database, word durations, long words and long pauses, the encoder offsets,
the encoded-file check and, with `--fetch-biblehub`, our verse starts against Bible Hub's.
`revision.py` scores every verse where the official text differs from the older BSB copy
against both readings, which tells which revision the narrator read.
