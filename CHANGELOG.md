# Changelog

## Unreleased

Performance
- A phone with under 7 GB of memory now starts on the low prompt budget with Gemma 4 E2B. On a
  5.5 GB Galaxy A32 the same question took 148 s instead of 225 s, the first words came after
  49 s instead of 125 s, and the app held 2.7 GB instead of 3.8 GB with 1.2 GB less swapped out.
  Phones that already chose a tier keep it; change it in Settings.
- While the model works, the chat shows the verses it was given, so the wait is spent reading.
- Brief answers first, on by default at the low tier (Settings: Brief answers first). The model
  writes at most four short sentences, and a Go deeper button asks for the full study, which
  replaces the brief answer in the conversation. On the Galaxy A32 the answer was complete after
  61 s instead of about 150 s. On the 40 golden questions it kept all 28 expected references, with
  no invented references, unverified quotes or misattributed sayings.
- A Stop button replaces the send button while an answer is written. What was written so far is
  kept and checked like any other answer. It takes effect in about 2.5 s while the answer is being
  written, and up to about 20 s during the first wait for the model to read the prompt, with
  "Stopping…" shown meanwhile.

Models
- Gemma 3 1B no longer needs a Hugging Face account or token. Berea hosts the unmodified file on
  its own release, downloads it with a pinned SHA-256 check and keeps it in its own folder. The
  token field is gone from Settings and a token saved by an older build is deleted on launch.
- A short Terms of use screen (under Licences and sources, and from Settings) states the Gemma
  Prohibited Use Policy as a term of using a Gemma model in Berea. Downloading Gemma 3 1B asks you
  to agree first, once, and the full Gemma terms and policy are bundled for reading offline.
- Switching between models no longer leaves the app with "No active inference model set" after a
  restart: the chosen model is made active again each time the app starts, with no download.

## 0.4.0

Performance
- A streaming answer no longer redraws the whole app for every token. Only the answer being
  written redraws, at most 15 times a second, so the Bible and Notes tabs stop rereading the
  database while the model works. Measured on a Mac with Ollama: one answer rebuilt the Study,
  Bible and Notes screens 30 times each before, twice now. Study page drafts stream the same way.
- The chat stays at the newest text while an answer streams, and no longer pulls you back down
  if you scroll up to read. A notebook chat opened mid-answer follows it.
- A model download redraws the app once per percent instead of once per chunk.

Desktop
- When Ollama is not running, a question now says "Berea could not reach Ollama at ... Install
  Ollama and start it, or choose On device in Settings." It used to show a raw socket error.
  Ollama errors also lose their "Bad state:" prefix.
- Each release carries the Mac app under a fixed name, `berea-macos.zip`, as it does the APK.

Corrections
- 0.3.0 said the new BSB text matches the narrated BSB audio. It does not quite: the Souer
  narration (2022-2023) follows the earlier wording in the few verses that changed, for example
  John 1:9 and Psalm 18:40. Read-along timings for those verses are approximate.

Audio
- A build-time pipeline (tool/audio/) aligns the CC0 BSB narration word by word and packs each
  book as a downloadable SQLite file. Timings are dedicated to the public domain. The John pilot
  is the first pack.

Notebooks
- A Notebooks tab. A notebook gathers sources on one passage or topic: Bible passages in your
  reading translation, commentary from the installed packs (one source per work, with its author
  and licence), your own notes, pasted text, PDFs and EPUB books. Create, rename and delete
  notebooks; add and remove sources; open a source to read the text Berea kept, with PDF page
  numbers.
- Sources are read on a background isolate, one at a time, and shown with a progress bar while
  they are read. Each is split into sections of about 1,200 characters that keep their position
  in the source and their PDF page, and indexed for search, ready for chat over a notebook.
- Limits: files up to 64 MB, PDFs up to 2,000 pages, about 600 pages of text per source and 100
  sources per notebook. Scanned PDFs without a text layer and DRM-protected EPUB chapters are not
  read. A source still being read after five minutes is abandoned, so one bad file cannot hold
  up the others.
- PDF text comes from PDFium, bundled with the app (BSD and Apache licensed, through the MIT
  pdfium_flutter package). Its licence texts are on a new Software licences page.
- Backups are now version 2 and include notebooks. Version 1 backups still restore, and leave the
  notebooks on the device as they are.
- Chat inside a notebook. Answers draw on the notebook's sources and on Scripture, and cite
  sources by tag: [S3 p.14] for a PDF page, [S3 §2] for a section of anything else, [C4821] for
  commentary from an installed pack on the passages in view. Tap the chip to open the source at
  the cited section. Pin a source to offer it to every answer. Each notebook keeps one
  conversation, saved with the notebook and included in backups.
- A source tag naming a source, page or section the model was not shown is marked
  "unverified source", as invented verse references are. A quote cited to a source must be in
  that source; a quote cited to a verse must be in the verse. A quote a source supports that
  reads as a verse reworded is marked "differs from Scripture", so a source that misquotes
  Scripture cannot vouch for the misquote. Bracketed text that means a source but is not a tag
  ([Source 9], [S3 and S9]) is marked too.
- Study pages wait their turn for the model, as the Study and notebook chats do.

Grounding
- Quotes in Greek, Hebrew or any other script are now checked. Before, a quote with no English
  letters was taken as shown. The site's live check does the same (two new parity cases).
- Only what fit the prompt counts as shown. A verse or source the budget cut no longer supports
  a quote or a near-miss check.
- Prompt budgets now estimate tokens high: one token for every digit, punctuation mark and
  Hebrew or Greek character. The old estimate let word-study and long-passage prompts overrun
  the model's context on the mid and high tiers (measured up to 14,417 tokens against a 9,912
  window); every measured prompt now fits with its full answer. Answers to long questions carry
  a little less context as a result.

Study
- Ask by voice. Hold the microphone beside the question box, or tap it to start and tap again to
  stop, and speak for up to 30 seconds. Gemma 4 E2B or E4B hears the question on the device and
  types it into the box for you to check and edit; nothing is sent until you tap Send, and the
  answer goes through the same grounding and reference check as a typed question. The recording
  is a temporary file, deleted as soon as it is read and before the model hears it. With
  Gemma 3 1B or Ollama the button explains that voice needs Gemma 4 and opens Settings.
- Recording starts the moment you press. A quick tap keeps listening until the next tap, and the
  status line says which. Sliding off the button, a call or a system dialog, leaving the app or
  switching tabs throws the recording away. A transcript is added after anything you already
  typed, and a question sent from the Bible tab waits until the voice question is done.
- Only one voice question runs at a time across the Study tab and the quick chat, and nothing
  else uses the model while it transcribes. Changing the model waits for it to finish.
- If Gemma 4's audio part fails to load, typed questions still work and the button says voice
  is off. A missing microphone, a microphone stuck at the wrong sample rate and a recording with
  no speech each get their own message. On Linux, voice needs parecord and ffmpeg.
- The app asks for the microphone the first time you use voice (Android RECORD_AUDIO, iOS and
  macOS microphone permission). If you refuse, Berea says where to allow it.

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
