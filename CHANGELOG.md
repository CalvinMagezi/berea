# Changelog

## Unreleased

- The Berean Standard Bible now shows its section headings, with the parallel passages under them
  and the five books of Psalms and the acrostic letters of Psalm 119 marked. Tap a heading to
  select its whole section, ready to highlight, ask about or add to a notebook; tap it again to
  clear. The headings are public domain with the BSB text.
- Chapters longer than 40 verses (Psalm 119, Genesis 24, John 6 and many more) are read to their
  end; the reader used to stop at verse 40.
- A jump to a verse (the resume point, a search result) now reaches it in chapters whose verses
  are of very different heights.
- Synthesize, in a notebook, gathers what the Bible and your installed commentaries say about the
  notebook's passages, without the helper: each BSB section with its parallels and cross
  references, the key Hebrew and Greek words of the reading with other places they are used,
  the commentary on each section, and verses from the other testament that the passage points
  to. It reads the notebook's Bible passages and the verses its notes and study pages are on. It
  is the groundwork for listening to a notebook as a spoken deep dive.
- Passages longer than 40 verses are kept whole in a notebook, a study page, a note's verse
  preview and an export; they used to stop at verse 40.
- Tap a section heading in the reader, then Study notebook: the section becomes a notebook named
  for it, with the passage, what each installed commentary says on it, and its key Hebrew or Greek
  words kept as word studies, ready to Synthesize or Listen. Tapping it again for the same section
  opens that notebook instead of making a copy.
- Listen, in a notebook, makes a spoken deep dive of about nine minutes, read by one narrator.
  The helper writes it part by part from what Synthesize gathers: an opening, a walk through the
  verses with their Hebrew or Greek words and commentators, the hardest question the passage
  raises, witnesses from the other testament, and a recap with a question to take away. Every
  verse it quotes is checked against the Bible, and a sentence that fails the check is not read.
  Supertonic 3, a voice that runs on the device (a 145 MB download, once), then reads it aloud.
  It is made in the background: Study keeps answering between parts, the helper rests while the
  voice reads, and on Android a notification shows how far along it is and says when it is
  ready. Stop keeps what was made, and Continue picks up from there. The recording stays on the
  device and out of backups, and it says that it is machine generated.

## 0.8.0

Prayers from the Word
- Prayer gains words to pray. 24 topics of everyday need (work, farming and rain, exams, sickness
  and healing, grief, marriage and more) have 5 to 8 numbered prayer points each, and every point
  stands on one Bible verse and says no more than that verse. The points are written for Berea from
  the Berean Standard Bible. Nothing is generated and no helper is needed.
- Prayers of the Bible (the Lord's Prayer, Psalm 23, Hannah, Paul for wisdom and more) are prayed a
  verse at a time from the Bible text you have installed.
- Today's prayer shows in Prayer and on the Bible's today card: a line from the chapters of your
  reading plan, else a line for the verse of the day. Pray now opens with praise, confession and
  thanks, asks through your list (a prayer can carry a topic and shows two of its lines), and closes
  with others. Ask only skips the frame.
- Verse ties. A mark in the reader's margin shows where words are written for a verse; it is filled
  where one of your prayers stands, with "Your prayer" under the verse. Pray, on the selection bar
  or the mark, opens the points for the verse. A new prayer suggests verses from its own words on the
  phone, with a switch to pray the topic's points with it. An answered prayer shares as a testimony
  that carries the verse it stood on, with switches to include the verse and to leave out who it was for.
- Plans. After you tick a day's chapters, Pray what you read offers two or three lines from them, and
  Amen ticks the day. Six prayer plans sit beside the reading plans (7 days for your work, Exam week,
  21 days for your family, 40 days in the Psalms, The prayers of Paul, For our country and its
  leaders). There are no streaks. Fasting is off unless you turn it on, never without water, and
  shows a health note.
- Settings gains Daily prayer: an optional notification each morning with the verse of the day and
  today's prayer, at a time you choose, or the reference only on the lock screen. It is scheduled on
  the phone, asks for permission only when you turn it on, and never shows your own prayers.
- New tables in your notes file hold prayer topics, plan runs and days; they are backed up, restored
  and exported with the rest. Nothing is removed.

Word study
- Long-pressing "Jesus" (or Christ, God, LORD or any name) no longer opens a different word. In
  about 550 of the BSB's 1,430 "Jesus" the Greek has a pronoun or only a verb ("Jesus replied" is one
  Greek verb), and Berea opened that verb as if it were the name. Now it says the BSB wrote the
  name there, names the word it stands on, and lets you choose from the verse. A name that the
  Greek does have still opens exactly.
- Berea marks the word under your finger after a moment, names it above the finger ("Jesus ·
  Ἰησοῦς · G2424"), fills over the rest of the long press, then opens the study. Moving to another
  word moves the mark; lifting or scrolling cancels. A press on the verse number or between words
  marks the verse and opens its Hebrew or Greek words as before. With reduce motion on there is no
  sweep. On the Mac, press and hold does the same, and right-click offers "Study the word ..." and
  "All words in this verse".
- The study's top line now reads "Jesus, John 11:35 · BSB" above the original word.
- Words are matched to the BSB translation tables by content rather than by position, and repeats
  of a word follow the Hebrew or Greek order. The Bible database format for this changed, so the
  first launch after updating copies the Bible again.

## 0.7.0

Opens on the Bible
- Berea now opens on the Bible, and the helper loads after the first screen is up. On a Galaxy A32
  the first verse is on screen in a median 1.50 s from launch, against 2.47 s before (5 cold
  starts each, same script).
- First launch says "Setting up the Bible on this phone". It needs about 85 MB of free space and
  downloads nothing. Failures are in plain words: a full device, a notes safety copy that could
  not be written, a helper that would not start.
- A question asked while the helper loads waits and is answered when the helper is ready, or you
  are told why it was not.

Five places
- Bible, Plans, Study, Prayer and Notes, with Study as the raised Lamp b button. In a wide window
  (760 px and up) a sidebar replaces the bar: Cmd 1 to 5 switch places, notebooks are listed under
  Notes, and the helper's state sits at the foot.
- The Lamp b mark is the app icon and launch screen on Android, iOS, Mac and Windows, light and
  dark. The Mac menu bar, Dock and About now read Berea.
- The first open lands on John 1 with today's verse card; later opens resume where you stopped. The
  Reading plans icon is gone from the reader, and so is the Ask pill under a chapter, since Study
  and the selection bar both ask.

Plans
- Plans is a place: today's portion with chapter ticks and Read next, a week row, Catch up and
  Start another. There are no streaks. Ticks you made by day in earlier versions carry over.

Study
- With no helper installed, Study offers the choice of helper and Keep reading. Wi-Fi only is on
  by default.
- A helper download now resumes after a pause, a lost connection or a restart, instead of starting
  over. The partial file is kept, and size and SHA-256 are checked before it is used. An older
  copy of a model is removed only after the new one passes those checks.
- A scope chip sets the question's reach: the Bible, or one notebook. A notebook-scoped answer
  reads that notebook's notes and readings, and its source chips open the cited place.
- Past questions sit behind the clock, each labelled with its scope. An answer can be kept in a
  notebook.

Prayer
- A new place. Add a prayer, choose Pray now to go through them one at a time with the verse in
  full (the one prayed least recently first), and Amen records the day. The Lord's Prayer from
  Matthew 6:9-13 is there to start from.
- Answered keeps your own line and the date, and can be undone. Deleting asks first. Stopped
  prayers can be resumed. Sharing a prayer uses plain text through the system share sheet.
- Prayers stay on the device and are included in backup and export.

Notes
- Notes and notebooks are one place. A note can belong to a verse or stand alone. A notebook shows
  Everything, Notes, Readings, Add, and Ask about this notebook.
- The note editor is full screen, with a notebook picker, a title, an optional verse and a Pray
  this button. References you type become links.
- One Keep in a notebook sheet, with the last notebook used first, serves word study, commentary
  and answers.
- The separate notebook chat screen is gone. Its messages were copied into scoped conversations,
  and pins stay.

Selection bar
- Highlighting verses opens a bar with Highlight, Note, Pray, Ask and More (Words, Commentary,
  Study page, Copy, Share). Pray fills in the verses you chose, and a selection with gaps acts only
  on the verses selected. The Mac toolbar gains Pray.

Your data
- Moving to this version rewrites the notes database. Berea first copies it to
  `study.sqlite.pre-notes-merge` and does not migrate if it cannot. Backups now carry prayers,
  reading plan ticks and the running plan, and backups from older versions still restore.
- The change is one way: after the first launch, 0.6.0 cannot read notes that have no verse. Back
  up first if you may go back.
- Tried on real data: a phone went from schema 2 to 6 with all 39 conversations and 84 messages
  kept, and the pre-merge copy holds the same counts. A Mac went from 2 to 6 with its 2
  conversations and 4 messages kept.

Not in this version
- The daily verse notification, Find a plan on Plans, page counts and dates on PDF and EPUB
  reading rows, and a Cmd K palette on the Mac are not built.
- Study does not read a notebook's study pages, so its notes count can be lower than the notebook
  page's.

## 0.6.0

Word study
- Long-press a word in the reader to study the Hebrew or Greek word behind it: its lexicon
  entry, part of speech, how often and in which books it is used, how it is glossed, and every
  verse that uses it (30 at a time, filterable by book), with the English words that render it
  marked. Tap a verse to open it in the reader.
- The study lists other words glossed with the same English. "Perfect" stands for τέλειος,
  τελειόω, כָּלִיל, שָׁלֵם, תָּם and more; the KJV's "perfect" in Job 1:1 opens תָּם, which the BSB
  calls "blameless".
- In the BSB the word is exact, from the BSB's own translation tables (public domain with the
  text, pinned by SHA-256): 99.8% of study words on 2,000 random verses. A word the translators
  supplied says that no Hebrew or Greek word stands behind it.
- In other translations the word is chosen by meaning and labelled as a guess, with the verse's
  words a tap away to correct it: 78% of study words found in the KJV and 84% in the WEB, and
  where it picks a word it is the tables' word 91.5% of the time (`bin/word_match_check.dart`).
- Ask Berea about the word starts a Study chat on it. A question that names a Strong's number puts
  that lexicon entry first and a spread of the word's other uses in RELATED VERSES, in place of a
  keyword search, so the answer about its use elsewhere is checked like any other.
- `bin/eval.dart --words` runs 9 word study questions, 3 of them adversarial, as a release gate
  in `tool/release.sh`. It has not been run yet.
- The site has a section on word study.
- The interlinear's lexicon dialog has a Word study button. Long-pressing the verse number, or
  anywhere that is not a word, still opens the interlinear.

Performance
- The Bible database now indexes verses by translation and reference. Every passage lookup
  scanned all 93,000 verses before (about 10 ms on a fast desktop, more on a phone); it now takes
  under 2 ms, which speeds the reader and every answer's retrieval, not only word studies.
- The word study concordance adds 8.8 MB to the database on the device and 2.6 MB compressed to
  the download, the BSB alignment 3.7 MB and 1 MB, and the verse index 1.6 MB and 0.5 MB. Building it on the device instead would cost no
  download but a first word study of many seconds on a low-end phone.

## 0.5.0

Performance
- A first run on a phone with 5 to 7 GB of memory now starts Gemma 4 E2B on the low prompt budget
  (a phone under 5 GB gets Gemma 3 1B, also low). On a 5.5 GB Galaxy A32 the same question took
  148 s instead of 225 s, the first words came after 49 s instead of 125 s, and the app held
  2.7 GB instead of 3.8 GB with 1.2 GB less swapped out. Anyone who has already saved settings
  keeps them; change the tier in Settings. The low tier retrieves fewer passages, uses no
  commentary in notebook answers and caps study pages at 600 tokens.
- While the model works, the chat shows the verses it was given, so the wait is spent reading.
- Brief answers first (Settings: Brief answers first), on by default at the low tier unless you
  choose otherwise. The model writes at most four short sentences, and Go deeper under the newest
  answer asks for the full study. Both stay on screen and in the saved study; the model remembers
  only the full one. On the Galaxy A32 the answer was complete after 61 s instead of about 160 s.
  On the 40 golden questions through Ollama (a stand-in for the on-device file) it kept all 28
  expected references, with no invented references, unverified quotes or misattributed sayings,
  in 51 s against 119 to 147 s.
- A Stop button replaces the send button while an answer is written. It takes effect in about
  2.5 s while the answer is being written, and about 22 s while the model is still reading the
  prompt, with "Stopping…" shown meanwhile. A stopped answer, or one that hit its length cap, is
  cut back to its last finished sentence, so the citation check never sees half a quotation or a
  reference cut short.

Models
- Gemma 3 1B no longer needs a Hugging Face account or token. Berea hosts the unmodified file on
  its own release, downloads it with a pinned SHA-256 check and keeps it, with the Gemma NOTICE,
  in its own folder. The token field is gone from Settings and a token saved by an older build is
  deleted on launch.
- A short Terms of use screen (under Licences and sources, and from Settings) states the Gemma
  Prohibited Use Policy as a term of using a Gemma model. Downloading Gemma 3 1B asks you to
  agree first, once, and the full Gemma terms and policy are bundled for reading offline.
- Switching between models no longer leaves the app with "No active inference model set" after a
  restart: the chosen model is made active again each time the app starts, with no download.
- A double tap on Download no longer starts two downloads. Download after Gemma 3 1B failed to
  load checks the file's hash again and replaces it if it is damaged.

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
