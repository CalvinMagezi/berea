# Changelog

## 0.2.0

Grounding
- Citations of books that do not exist (2 Hezekiah 4:1) are flagged, not only unknown chapters.
- A misquote that clearly comes from one shown verse is replaced with that verse's exact words;
  anything less certain stays flagged.
- Two new prompt rules for sayings that are not in the Bible and for passages that do not exist.
- Eval grows to 40 questions, 8 adversarial. On gemma4:e2b: 0 invented references, 0
  misattributed sayings, 8 of 8 adversarial cases passed.

Bible
- World English Bible built in alongside BSB and KJV.
- Import a translation you own from CSV, USFM, OSIS, Zefania or a zip of those.
- Search the Bible; a typed reference jumps straight to its verse.
- Parallel translation beside or below the text.
- Long-press a verse for its Hebrew or Greek words with transliteration, gloss and lexicon entry.
- Optional full Greek lexicon (LSJ) pack, downloaded only on request.

Study
- Reading plans with progress kept on the device, and today's reading on the Study tab.
- Verse of the day.
- Study pages: observation, interpretation and application drafted from Scripture and edited by
  you.
- Export a study or all notes to Markdown.
- Encrypted backup and restore with a passphrase.

Platforms
- Windows and Linux desktop targets, built in CI.
- Model recommendation from device memory.

## 0.1.0

First public release: grounded Study chat, offline reader with BSB and KJV, notes, highlights,
saved studies, quick chat, and on-device models on Android and iOS with Ollama on a Mac.
