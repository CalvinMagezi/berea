# Changelog

## Unreleased

Corrections
- 0.3.0 said the new BSB text matches the narrated BSB audio. It does not quite: the Souer
  narration (2022-2023) follows the earlier wording in the few verses that changed, for example
  John 1:9 and Psalm 18:40. Read-along timings for those verses are approximate.

Audio
- A build-time pipeline (tool/audio/) aligns the CC0 BSB narration word by word and packs each
  book as a downloadable SQLite file. Timings are dedicated to the public domain. The John pilot
  is the first pack.

## 0.3.0

Grounding
- On-device answers run on the CPU. Gemma 4 E2B on some phone GPUs corrupts digits (LiteRT-LM
  #2202, still open), and a wrong verse number that still exists would pass the reference check.
  Answers are slower on phones with a capable GPU until a fix is confirmed on a real device.
- A real reference one slip away from a verse the model was shown (John 3:18 when it was shown
  John 3:16, or Isaiah 35:5 for 53:5) is kept but marked "Check the verse number".

Bible
- The Berean Standard Bible now comes from the official text at bereanbible.com, pinned by
  SHA-256, instead of an older third-party copy. 1,474 verses read differently, for example
  "every winged bird" in Genesis 1:21 and "the Spirit of adoption to sonship" in Romans 8:15.
  KJV and WEB are unchanged.

Commentary
- Optional public domain commentary packs: Matthew Henry (concise and complete), Jamieson,
  Fausset and Brown, the Treasury of Scripture Knowledge, Aquinas's Catena Aurea, Calvin, Adam
  Clarke, Keil and Delitzsch, Barnes, Wesley and Spurgeon's Treasury of David. Select verses
  and tap Commentary to read each one with its author and licence. Packs download only when
  you ask, are checked against a published SHA-256, can be added from a file and deleted.
- A Licences and sources screen lists every dataset Berea carries or offers.

Site
- The public site is rebuilt on the scroll-craft engine (vendored, MIT): a scrubbed lamplight
  film, one real answer walked through as you scroll, and a live copy of the reference check
  you can try to fool. The copy is tested against the app's own check on 32 cases in CI.

## 0.2.0

Grounding
- Citations of books that do not exist (2 Hezekiah 4:1) are flagged, not only unknown chapters.
- A misquote that clearly comes from one shown verse is replaced with that verse's exact words;
  anything less certain stays flagged. When the quote is attributed to a reference, only that
  passage can supply the correction.
- Two new prompt rules for sayings that are not in the Bible and for passages that do not exist.
- Topical questions follow the cross-reference graph from their search hits, with stemmed search
  and wider stopwords: well-known passages now reach the model for 7 of 8 topical checks, up from 4.
- Eval grows to 40 questions, 8 adversarial. On gemma4:e2b: 0 invented references, 28 of 28
  expected references, 0 misattributed sayings, 8 of 8 adversarial cases passed.

Bible
- World English Bible built in alongside BSB and KJV.
- Import a translation you own from CSV, USFM, OSIS, Zefania or a zip of those. Zips are size
  capped and parsing runs in the background; built-in translation codes cannot be replaced. The
  search index is updated for the imported translation only (about 130 ms for a whole Bible on a
  Mac, instead of rebuilding every translation).
- Search the Bible; a typed reference jumps straight to its verse.
- Parallel translation beside or below the text.
- Long-press a verse for its Hebrew or Greek words with transliteration, gloss and lexicon entry.
- Optional full Greek lexicon (LSJ) pack, downloaded only on request from a pinned data release
  and checked by SHA-256.

Study
- Reading plans with progress kept on the device, and today's reading on the Study tab.
- Verse of the day.
- Study pages: observation, interpretation and application drafted from Scripture and edited by
  you.
- Export a study or all notes to Markdown.
- Encrypted backup and restore with a passphrase. Restore checks every row and imported translation
  before replacing anything.
- Android cloud backup and device transfer are off, and the iOS data folder is excluded from
  iCloud backup, so the app's own encrypted file is the only copy that leaves the device.

Platforms
- The bundled database is recopied only when its build stamp changes, instead of loading the full
  asset on every launch.
- Windows and Linux desktop targets, built in CI.
- Model recommendation from device memory.

## 0.1.0

First public release: grounded Study chat, offline reader with BSB and KJV, notes, highlights,
saved studies, quick chat, and on-device models on Android and iOS with Ollama on a Mac.
