# Berea, Scripture first

A plan, written 2026-11-10. Nothing in it is built.

It answers one request: remove the chat, put the Bible in the centre, add a place called
Practice built solely from Scripture, shrink the AI to something that never writes, and make word
study, commentary per verse and study depth more exact, with no personal opinions or ideas
anywhere and Scripture as the source of truth.

## How to read the numbers

Every figure carries one of these marks.

- `[code]` read in this repository at commit 4f68eb8, with the file and line.
- `[measured]` counted in this session over the BSB text in `site/data/bible` and the raw
  STEPBible files that `build_db.dart` downloads.
- `[GitHub]` read from the GitHub API on the day of writing.
- `[search]` taken from search summaries because the source site was blocked from the planning
  sandbox. Treat as indicative.
- `[estimate]` one developer's guess at effort. Not a promise.

Nothing was compiled or run. The sandbox had no Dart or Flutter and no built `berea.sqlite`, so
anything about what a screen shows is read from code. Section 14 lists what could not be checked.

## 1. Your request, clause by clause

| You asked for | Short answer | Section |
|---|---|---|
| Remove the chat AI | Yes, in one release, with no hidden stage. It is nearly free: 29 APK downloads exist across all seven releases `[GitHub]`. Search has to be repaired first, or the release that removes the chat ships a search box that answers "Jesus" with "No verses match." `[code]` | 4, 5 |
| The centre Berea icon becomes the Bible | A one-file change in the shell, plus tests. The lamp mark is tied to no feature in the brand guide `[code]`. | 5 |
| A new page called Practice | Yes. But "practice" has three honest meanings under your rule and you need to pick. | 3, 7 |
| Practices solely from Scripture, outside the box | The safe form: Berea supplies only a mechanic, and the passage supplies every word. Any list that pairs a practice with verses is a selection, and a selection needs a named chooser. | 7 |
| AI reduced to something like HQ's embedder and its proactive uses | Take HQ's discipline and leave the model out for now. Most of what HQ does proactively uses rules and joins, not the embedder. Berea's triggers carry exact keys (a reference, a Strong's number, a plan day), so a join is exact and costs 0 MB. | 8 |
| Deeper accuracy of word studies | Fix what is wrong on screen today before adding depth. One lookup path shows the wrong dictionary entry for 13.45% of Hebrew word tokens `[measured]`. | 9 |
| Commentary per verse | No new commentary could be verified this session, and nobody has counted how many verses would get a paragraph of their own. The sure win is the BSB publisher's own footnotes, which Berea throws away today. | 10 |
| Depth of studying | One view per verse that joins text, footnotes, parallels, cross references with their source, words and commentary. | 10 |
| No personal opinions; Scripture as the source of truth | Written as a rule a test can check (section 2). It is already broken in the app, mostly in Prayer, and applying it strictly removes more than the chat. | 2, 3, 11 |

## 2. The source rule

Everything Berea shows belongs to one class, and the class is visible.

1. **Scripture.** Words from an installed translation or a named original-language edition, with
   reference and translation beside them. A verse is never shown in part unless the whole verse
   is on the same screen. Psalm 14:1 in the BSB contains the sentence "There is no God."
   `[measured]`, and a screen that showed that phrase alone would print the opposite of the
   verse. The word-hiding drill is the one labelled exception.
2. **A counted fact.** A number or a list that a script recomputes from pinned inputs. Its rule
   is printed beside it in one sentence and the rows behind it open in one tap.
3. **A named source.** A person's or publisher's words, shown whole, under the name of whoever
   wrote them and whoever carried them to us, with the licence one tap away. This class is wider
   than it looks. Tagging, glosses, parsing and sense divisions are a scholar's analysis, not a
   count, so "tagged 216 times" becomes "tagged 216 times in STEPBible's tagging". Section
   headings, footnotes, red letters and supplied-word marks are the translation publisher's. Vote
   counts on cross references are an unnamed crowd's and are called that.
4. **The person's own words.** Notes, prayers, sets, answers.
5. **Interface wording.** The name of a place or a control, a fact about the app or the device,
   or the source or rule behind what is on screen. It never says what a verse, word or book
   means, never tells the reader what to do in faith or life, never evaluates, never gives an
   author or translator a motive, never asks a leading question.
6. **Machine output.** Not Scripture, not a fact, not a source. None is shown in the releases
   planned here (section 8).

Two rules follow from applying this honestly.

- **A selection names its selector.** Where Berea ships a list (which commentaries it carries,
  which reading plans, the verse of the day, the things on the Practice page), the screen says
  who chose and by what rule. Claiming that "nothing is selected" when something was is its own
  kind of opinion.
- **A source is shown losslessly.** The text on screen, with whitespace removed, equals the text
  in the source file. Line breaks at the source's own sense numbers are allowed. Rewording and
  silent cuts are not.

### How it is enforced

Keep the enforcement light. An earlier draft proposed a reviewed ledger of all 661 interface
strings of three words or more `[measured]`. For one maintainer that proves bookkeeping, not
review, and it misses two-word headings such as "Its senses".

- A deny-list lint over every string literal in `lib/` and the harness, any length, with an
  inline allow comment where a hit is legitimate. Words such as mean, should, must, worth, key,
  deeper, promise.
- One `sources` table (`id, originator, carried_by, work, year, licence, url, changes,
  machine_written`), and `source_id NOT NULL` on every row of source text. The README, the site
  and the Licences screen are generated from it.
- One Scripture widget that accepts only a value `BibleDb` can create, and a test that
  `scriptureStyle` is used nowhere else.
- Bundled lists regenerate byte for byte from a recorded rule and pinned inputs, the way
  `build_prayers.dart --check` works today `[code]`.
- About 30 interface strings fail the rule today outside the model's own files (one reading,
  `[measured]`). They are fixed by hand in the release that touches each screen.

### Where the app breaks the rule today

| Where | Fact | What the rule asks |
|---|---|---|
| Prayer points | About 1,970 lines of prose, each tied to a verse. The commit that added them says they were written "then read against the verse text by a second model, which reworded 88 lines", and it is co-authored by a language model (`c396c7e`, `[code]`). The app shows the line in Scripture type at size 22 with the verse smaller beneath it (`lib/prayer_words.dart:364-375`). TECHDEBT records that the check "cannot judge that a line says no more than its verse". | Section 11. This is decision 1. |
| Prayer topics, plan titles, the Praise / Confess / Thank / Ask / Others frame, "Verses many people stand on", the ten Bible prayers and their titles, the trimmed psalm plan | Hand choices with no rule recorded and no chooser named. | State who chose, or replace with a computed list. |
| "Pray: ..." in the daily notification | An authored line on the lock screen (`lib/daily_reminder.dart:97`). | The notification is the reference and the verse. |
| "What it means" in word study | A regex rewrite of a lexicon definition, at most four senses, with no source named (`plainSenses`, `word_study.dart:598-685`). | Show the entry whole under its author's name. |
| Lexicon definitions | Cut at 600 characters, which removes the trailing source tag from 778 of 779 long Greek entries `[measured]`. Abbott-Smith and Brown-Driver-Briggs are named nowhere in `lib/`. | Full text, named. |
| Captions | "Hebrew and Greek words worth knowing in this passage", "One English word can stand for several Hebrew and Greek words", "The translators supplied X here so the English reads well", "What does it mean?", "How should I live?" | Replace with the rule or the source, for example "Verbs, nouns, adjectives and adverbs used 3 or more times here. Names left out. Counts from STEPBible's tagging." |
| Verse of the day | The 366 single verses with the most summed OpenBible votes; 1 January is always the top one `[code]`. The card says only "VERSE OF THE DAY". | Print the rule, or take the first verse of today's reading, or drop it. |
| Shipped Hebrew name entries | 3,022 of 4,477 carry a sentence STEPBible generated ("living at the time of ...") `[measured]`. STEPBible's README says its person descriptions were written by a language model. | Split the sentence off and drop it until STEPBible says how it was made. |
| Kept chat answers | Stored as ordinary notes, indistinguishable from the person's own writing `[code]`. | One provenance column and one label (section 5). |

## 3. Decisions only you can make

Ten, ordered by what each one unblocks. Each has a recommendation and its cost to a reader.

1. **Does the rule reach content Berea already ships that no model writes at run time?** That
   is the prayer points, the 24 topics and the plain word senses. Nobody asked for these to go;
   they follow from the rule. The loss falls hardest on a new reader, and the topics (farming and
   rain, exams, looking for work) are the most locally shaped content in the app.
   *Recommendation:* yes, the rule reaches them, in two steps. In the release that removes the
   chat, change only what costs a reader nothing: the verse first and in Scripture type, the
   point smaller under it with a plain label, no "Pray:" on the lock screen. Remove or replace
   content only when the replacement in decision 4 exists.
2. **What does "Practice" mean?** Three readings, each honest. (a) Mechanics Berea performs on a
   passage the person chooses: read it a verse at a time, hide its words, recall it, pray it
   back. (b) Rows that open a word search with its rule printed, for example "Verses with 'give
   thanks' in the BSB: 36" `[measured]`. Which words get a row is still a choice. (c) A list of
   practices with verses, chosen and signed by a named person, references only.
   *Recommendation:* ship (a) first with the caption "Things Berea can do with a passage you
   choose. This is not a list of what Scripture asks." Add (c) when a named editor exists, using
   the same mechanism as decision 4. The cost of (a) alone is a page with little to browse.
3. **May a model ever order verses on screen, under a label?** Never; or only for a search the
   person typed, and only after it beats word search on questions real readers wrote.
   *Recommendation:* no model in the releases planned here. Run the cheap comparison in week zero
   so you decide with a number in front of you.
4. **What is the door from a life need to verses once the chat is gone?** Word search cannot
   carry today's words to the Bible's: "exams" and "school" are in 0 BSB verses and "job" finds
   only the man Job, 61 verses `[measured]`. Options: a public domain topical index (Nave,
   Torrey) under its author's name, if its licence reads clean; the 24 topic titles with
   references only, under a named and accountable human editor; or word search alone.
   *Recommendation:* read the licence in week zero, and pick one of the first two. No topic is
   removed in any release before one of them ships.
5. **When needs conflict, who comes first?** A new reader on a 3 GB phone, or a teacher who wants
   editions, variants and Qere. *Recommendation:* the new reader. It puts sections 9 and 10's
   later phases behind reach and search.
6. **Languages.** Every item in this plan deepens an English product. Is English only acceptable
   for the next two releases, and is Luganda or Swahili first? *Recommendation:* spend week zero
   finding out whether a Luganda and a Swahili Bible can be offered at all. If one can, it
   outranks everything in sections 9 and 10 after their first phase.
7. **Will Berea ever be sold, bundled or preloaded on phones?** Hebrew parsing in the STEPBible
   files comes from ETCBC, whose own licence is non-commercial, and several useful sources are
   share-alike. Your answer decides what may sit in the app and what must stay in a separate
   pack. *Recommendation:* decide before section 9 starts.
8. **What does Berea say about its own choices?** The catalogue of commentaries, the reading
   plans, the 66 books it carries. A check that reports a citation from Sirach as "not a book"
   gives a verdict on the canon. *Recommendation:* state each as a fact about this phone ("No
   translation on this phone has a book named Sirach") and print the catalogue's rule ("English
   works whose licence Berea could verify. Being listed is not a judgement of them.").
9. **Marks on the Scripture text.** The BSB publisher marks words of Jesus (2,302 spans) and
   supplied words (19,771 spans), and prints headings such as the ones over the Psalms
   `[measured]`. All three are the publisher's reading. *Recommendation:* headings stay as today,
   labelled as the publisher's; red letters and supplied-word marks are off until switched on,
   with a legend whenever on, and never used as a filter.
10. **Old machine-written text and the model files on upgrade.** *Recommendation:* keep every
    saved answer readable under one fixed label, offer export and "Delete all", and delete the
    model files (up to 3.66 GB) without asking, saying so once on an upgrade card.

Decided in this plan unless you object: bar order Plans, Practice, Bible, Prayer, Notes; the
sidebar keeps Bible first; a second tap on the Bible button opens the book and chapter picker;
cross references default to Bible order with the vote count shown; commentaries are ordered by
year first published; study pages become one blank field; no synthetic voice; no streaks, scores
or praise anywhere; no QR scanning (it brings a closed Google component).

## 4. The case, as a product manager

**The problem.** The model decides who can install Berea. Android 11 and 64-bit only are both
set by it (`android/app/build.gradle.kts:35-36, 53-57`). The smallest model is a 0.58 GB download
and the default is 2.6 GB (`lib/models.dart`). On the one phone ever measured, a Galaxy A32 with
5.5 GB of RAM, first words took 49 to 125 seconds (CHANGELOG). It is also the only part of the
app that writes sentences that are neither Scripture nor a named source. And it has been taking
the work: of the last 15 merged changes, 8 were about the model's wording, citations or prompt
and 5 about Scripture data, reading or study depth `[code]`.

**For whom, at what scale.** Without the model nothing needs downloading at first run and the
Android floor can drop. Uganda has about 20.5 million smartphones, and new entry phones ship with
3 to 4 GB of RAM `[search]`. How many of those the current build excludes is not known: the only
figure found is an upper bound of about a fifth of Android web use below Android 11 `[search]`,
and no share of 32-bit phones was found at all.

**What is lost.** People with 6 GB phones or a Mac lose questions in their own words, drafted
study pages, questions over their own PDFs, the spoken deep dive and offline dictation. That
group is small today: the hosted model file has 3 downloads `[GitHub]`.

**Five things that would hurt if the request were followed to the letter.**

1. *Search is broken for a reader, and the chat hid it.* The search box uses the chat's query
   builder, whose stoplist holds "god", "lord", "jesus", "christ" and "help"
   (`bible_db.dart:402-412`). "Jesus" builds no query and the screen says "No verses match."
   (`lib/search_screen.dart:62`). The BSB has that name in 1,380 verses `[measured]`. Repair
   search before the chat goes, not after.
2. *The rule removes more than the chat.* On one release day a new reader would lose the chat,
   the prayer points and topics, the Pray now frame, the plain word senses and the study-page
   questions. Section 12 adds this up and sets each loss beside what replaces it.
3. *"Like HQ's embedder" is best answered without the embedder,* for now. Section 8.
4. *Nobody uses Berea yet.* 29 APK downloads across seven releases, 3 of them 0.8.0 `[GitHub]`,
   the owner's own included. No reader has been watched using it. Getting the app onto phones, and one standing
   panel of 8 to 10 readers, are pieces of work in this plan, not afterthoughts.
5. *English only.* Decision 6.

**How success is judged with no data collected.** Sizes and timings on two bought reference
phones at every release. One task script per release with a pass count from the panel, for
example "8 of 10 find a verse they half remember within a minute". A feedback message the person
reads before sending. GitHub's own download counts.

## 5. Removing the chat and re-centring the shell

### The places

`enum HomeTab { bible, plans, study, prayer, notes }` (`lib/home_shell.dart:24`) becomes
`{ bible, plans, practice, prayer, notes }`, renamed in place so the `IndexedStack`, the sidebar
loop and the shortcut digits stay as they are. A new constant
`barOrder = [plans, practice, bible, prayer, notes]` is read only by the phone bar, and the
raised-slot test becomes `t == HomeTab.bible`. The sidebar keeps Bible first, because a list has
no centre. Cmd or Ctrl 1 to 5 keep their meaning except 3, which becomes Practice. Add Cmd or
Ctrl F for search.

`StudyButton` becomes a stateless `BibleButton(selected, onPressed)`. The writing glow, both
progress rings, both badges and the download tap go; they only described the helper. The brand
guide asks for the mark at 57.8% of a round mask, so `_markScale` 0.62 becomes 0.578, and the
sidebar mark, at 15.4 px today, rises to the 16 px minimum `[code]`. The mark stops meaning "ask"
anywhere in the app.

A second tap on the Bible button, when the Bible is already open, opens the book and chapter
picker. To be tested with the panel against opening search.

Prayer keeps its place for now. Its home should not move before decision 1 is settled. If the
authored lines leave, the order becomes Plans, Practice (holding the prayer list), Bible, Search,
Notes.

### Every door into the model, and what stands there afterwards

| Today | Afterwards |
|---|---|
| Study chat, suggestion chips, Go deeper, "Brief answers first", the scope bar | Nothing. |
| "Ask" on the verse selection bar | "Words" takes the slot now, because it works from bundled data on first run. "This verse" (section 10) takes it when it ships. |
| "Ask Berea about <word>" in word study | Nothing. The screen keeps every use and Keep. |
| "Draft with Berea" on a study page | Nothing drafts. The page is one blank field, "Your notes on <reference>". |
| "Ask about this notebook" and its side panel | Synthesize becomes the default pane. Add "Search this notebook" over the existing index. |
| Listen (a model writes a script, a neural voice reads it) | Removed. Section 13. |
| Voice questions and note dictation | Removed. The keyboard's own voice typing needs no app permission. |
| Past questions | A read-only archive under Notes, shown only when a saved answer exists. |
| Helper setup, download sheet, Engine settings, sidebar footer, Gemma terms | Nothing. |

### Stored text

Nothing a person can read today is deleted unless they delete it, and old backups keep
restoring.

- One new column on `notes`, `study_pages` and `notebook_sources`, named `provenance`, with four
  values: `person`, `source`, `machine`, `unknown`. Agree the name and the values once: a shipped
  migration is never edited. The column needs `source` because a kept commentary excerpt or
  lexicon entry is saved as an ordinary note today `[code]`, and a default of "the person's own"
  would put the person's name on a commentator's words.
- Backfill: a note whose title equals a saved question and whose text equals the answer that
  followed it is `machine`. Kept words and kept commentary are `source`. Study pages written
  before this release are `unknown`, because a draft and the person's edits share three columns
  with no record of which is which `[code]`.
- One label wherever such text is shown, exported or shared: "Written by a language model in an
  earlier version of Berea. It is not Scripture and not a named source."
- `conversations`, `messages` and `notebook_messages` stay in `userTables` so backup versions 1
  to 3 restore. Nothing writes to them again. The backup version rises to 4, and the backfill
  runs after restoring an older one.
- The model files, the voice files and the listen recordings are deleted on first launch after
  the upgrade, by exact name, with one card: "The helper was removed. N GB freed. Saved answers
  are in Notes."

With 29 downloads to date this is kept deliberately small: one column, one label, one archive with
Export and Delete all. No per-field provenance, no "mark as mine" workflow.

### What is deleted

From `lib/`: `edge_engine`, `models`, `helper_setup`, `download_details_sheet`, `voice`,
`voice_composer`, `voice_wav`, `listen`, `listen_voice`, `listen_screen`, `chat_screen`,
`past_questions`, `notebook_ask_panel`, `notebook_chat`, `study_button`. From the harness:
`harness`, `prompt_builder`, `engine`, `ollama_engine`, `tier`, `truncation`, `listen_script`,
`speech_text`, the model halves of `sources.dart` and `study_packet.dart`, `bin/berea`,
`bin/eval`, `bin/prompt_size`, `eval/*.json`. `Retriever` loses its only caller and goes too.
`citation_guard` stays: the site depends on it. Dependencies: `flutter_edge_ai`,
`flutter_edge_ai_litertlm`, `record`, `sherpa_onnx`, `audioplayers`. `connectivity_plus` stays,
because the Wi-Fi-only switch still matters for packs.

Permissions and entitlements that go: `RECORD_AUDIO`, both foreground-service permissions, the
iOS memory entitlements, microphone strings, the macOS dylib staging, the RAM channel.

34 TECHDEBT rows close `[code]`.

### Reach, after the removal

- The Android floor among the remaining plugins reads as API 24, Android 7.0 (from the locked
  plugin sources; Flutter's own floor and the 32-bit build were not checked). Lower `minSdk` only
  as far as a real phone or emulator proves.
- 32-bit ARM needs a PDFium pin for `android-arm` and the `armeabi-v7a` exclude removed. It ships
  as its own release, after one bought 32-bit phone runs it.
- The first-run copy reads the whole 81 MB database into memory and writes it over the live
  file (`lib/app_state.dart:656-658`). On a 2 GB phone that is the real risk. Copy in chunks to a
  `.part` file and rename, before the floor is lowered.
- The 0.8.0 APK is 101.9 MB `[GitHub]`. What it weighs without the model is not known: the one
  subtraction offered did not add up. Build it and read `--analyze-size` before any figure is
  published. Budget: 60 MB or less per ABI, about 150 MB on the phone after first run, nothing
  downloaded at first run.
- "Share Berea": hand the installed APK, and any downloaded pack, to the system share sheet, so
  one paid download serves a congregation. Pin the hash of the unpacked pack as well as the
  compressed one, so a pack passed from phone to phone can be verified offline.

## 6. Search that finds

This ships before the chat is removed. It needs no model and adds 0 MB.

Measured on a Python copy of today's query builder over the committed BSB, without the app's
word-form expansion, so the absolute figures need re-running in Dart `[measured]`:

- A remembered four-word phrase: the source verse is first 32.6% of the time and in the top ten
  60.2%. With an exact-phrase group first: 75.5% and 95.1%.
- BSB section headings used as questions: 53.9% in the top ten today. The lexical variants
  tried moved that by about 2 points.

Design:

- `BibleDb.searchVerses` returns labelled groups, in this order: "Go to <reference>"; "Exact
  words"; "Exact words in KJV" (or WEB) when the open translation has none; "All your words";
  "<n> of <m> words"; "Section headings, Berean Standard Bible"; for a single word, "Same Hebrew
  or Greek word".
- Every group is in Bible order, so no ordering exists that a reader cannot check.
- The stoplist shrinks to about 40 function words. A query made only of those runs as a phrase.
- The index stores stems (`porter unicode61`, `build_db.dart:100`), so a phrase hit is only a
  candidate. Confirm each by comparing normalised words before printing "Exact words".
- A spelling line built from the translation's own vocabulary: "No verses have 'X'." followed
  by every candidate one edit away with its verse count. All candidates, not one pick.
- Run on a worker with its own read-only connection, wait about 300 ms after the last keystroke,
  show groups as they arrive. Today the one query runs inside `build` on every keystroke.
- Make the word pattern Unicode-aware. It is ASCII letters only today (`bible_db.dart:313`),
  which fails a Luganda or Swahili text.

Gate, `bin/search_check.dart`: the phrase set at 93% in the top ten and 70% first; 500 sampled
vocabulary words each return a result; a p95 time per group on the 2 GB phone. It replaces
`retrieval_check.dart`, which has no rank measure and tests code that loses its caller.

## 7. Practice

### What it is

A practice is a mechanic. Berea performs an operation on a passage that the person, their plan
or one of their sets supplied. Every word on the screen is a verse from the installed
translation, a count, or the person's own. The page says so: "Things Berea can do with a passage
you choose. This is not a list of what Scripture asks."

Why not a list of practices with their verses? Because the pairing is the opinion. Generating it
from the text does not remove the choice; it moves it to whoever picks the word. Measured on
STEPBible's tagging `[measured]`:

- The verb in Psalm 119:11 that the BSB renders "hidden" (H6845) is tagged in 31 verses. Exodus
  2:2 and Proverbs 1:11 are among them.
- The verb in Joshua 1:8 and Psalm 1:2 that the BSB renders "meditate" (H1897) is tagged in 24
  verses. Psalm 2:1 and Isaiah 8:19 are among them.
- The BSB has no verse with "memorize" and none with "by heart".

A lemma list is a concordance. It is useful, and it belongs in word study with its rule printed.
It is not a list of practices unless a named person says so (decision 2).

### The mechanics

| Mechanic | What the person sees | What Berea computes or checks | What it records |
|---|---|---|---|
| **Step through** | One whole verse a screen, reference and translation, "3 of 12", "Next verse". Built by generalising the existing verse-at-a-time stepper (`lib/prayer_pray_now.dart:532`). | Nothing. | Nothing. |
| **Pray it back** | The same stepper with one empty field under each verse, "Your words", and "Add to my prayer list". No frame, no points. | Nothing. | The person's words, as theirs. |
| **Recall** | The reference, the verse hidden. The person says it, taps Show, marks "Word for word" or "Not yet". No keyboard needed, so it works on any phone and in any language. | The next due day. | Rung, due day, last result. |
| **Hide words** | The verse whole, then five stages hiding 0, 25, 50, 75 and 100 percent of its words. Positions come from a shuffle seeded by the verse, so each stage contains the last. Tap a blank to see it. | The stages. | Nothing by itself; it ends in Recall. |
| **First letters** (after a device test) | Type the first letter of each word; a right letter shows the word. | Words right first time. | As Recall. |
| **Write out** (later) | Type the verse; it is drawn with each word marked same, missing or different, "24 of 26 words the same". | Word-by-word alignment. | As Recall. |

Scheduling is a fixed ladder: 1, 2, 4, 8, 16, 32, 64, 128 days. A pass climbs one rung and a miss
returns to the first. It can be explained in one sentence, which a fitted scheduler cannot. The
pass mark and the reset go to the panel before they are fixed.

What is due is worked out from `study.sqlite` when Berea opens, never from whether a
notification fired, so a phone that kills background work loses nothing. The screens show "Due
today: 3" and "Last recalled word for word: 4 November". Never a streak, a score, a percentage
or praise.

### Where passages come from

Nothing is chosen by Berea. The rows on the page are: Due; Where you are reading; Today's plan
reading; My sets. Two ready sets exist on first run because the person already made them: "Your
highlighted verses" and "Verses on your prayer list". Every verse list in the app gets "Save
these as a set".

### Outside the box, and inside the rule

Each of these is a mechanic on the text with nothing authored. The data each rests on is stated.

- **Hear and repeat.** Play a verse from the recorded narration, say it back, mark it on the same
  ladder. Read-along marks each word as it is spoken. For a reader who cannot read English well
  this is the only practice that needs no reading. Narration with word timings exists for John
  only `[code]`.
- **The publisher's lines as the unit.** 12.5% of BSB verses end mid-sentence, and 7,628 verses
  sit on poetry lines the app discards `[measured]`. Practise by the publisher's lines where they
  exist, and show "The sentence continues in verse 23" with one tap to extend the item.
- **Whole books at a sitting.** A reader view without verse numbers or headings, with the word
  count and reading minutes computed from the text.
- **Word for word elsewhere.** "These words occur word for word in N other verses." 385 whole
  verses repeat in the BSB `[measured]`.
- **Questions here.** "7 verses in this chapter have a question mark in the BSB." 2,527 verses
  have one `[measured]`. Each row is the whole verse and opens the chapter at that verse. The
  caption reads "This list does not say who asks or who is asked." The field under it is "Your
  notes", not "Your answer".
- **Sets that travel as references.** A set is shared as one line of text,
  `Berea set 1: Jhn 3:16-18; Psa 23; Rom 8:28`, through the ordinary share sheet. The receiving
  phone renders the words from its own Bible, so no free text can ride along. No accounts, no
  server, no shared progress.
- **Check a text.** The practice the app is named for: Acts 17:11 in the BSB says the Bereans
  "examined the Scriptures every day to see if these teachings were true" `[measured]`. Paste a
  message; Berea reports which references exist and how many quoted words match each installed
  translation, with the verse beside it. It reports counts and verses, never true or false, and
  the pasted text is never stored. It reuses the citation check, which already runs with no
  model. Two cautions before it is built. Readers must first bring 50 real forwarded messages,
  because a report of "not found word for word in BSB, KJV, WEB" misleads when the message quotes
  a translation Berea does not carry. And the reference pattern used for prose finds book names
  inside ordinary Luganda, Swahili and English words `[code]`; it needs a strict grammar first.
  The site already ships the BSB and a JavaScript copy of the check, so this could run in a
  browser with no install.

### What is left out, and why

- **A list of imperatives in the chapter.** It was designed and should be cut. Filtering by verb
  form leaves out Matthew 22:37 and John 13:34, which the BSB itself calls commandments in
  Matthew 22:38 and John 13:34, while listing John 13:27, where the words are spoken to Judas
  `[measured]`. Exodus 20:2-17 holds 12 second-person imperfects and 1 imperative in the
  tagging `[measured]`, so the list would show one verse of that passage. A list like that
  will be read as a list of orders whatever the caption says.
- **Fasting.** No mechanic, no timer. The existing switch goes. Anything touching health needs a
  named health source.
- **Giving thanks, remembering, teaching a child, singing, confessing.** The text names them, but
  none has a mechanic of its own, so each would be a hand-picked list. They wait for decision 2.
- **Reminders labelled with a verse about a time of day.** Labelling a 6:00 alarm with a verse
  applies that verse to the reader. A reminder slot is a clock time and nothing else. Its content
  is the reference and the verse of the first due item.

### Data

One additive migration:

- `practice_sets(id, title NULL, made_by 'person'|'received', created, archived)`
- `practice_set_refs(set_id, pos, book, chapter, verse_start NULL, verse_end NULL)`
- `practice_items(id, book, chapter, verse_start, verse_end, translation, rung, due_day,
  last_at, last_result, check_kind)`

The tables join the backup. Restore must leave them alone when the backup predates them:
`importTables` deletes every table it knows and inserts the backup's rows `[code]`, so without
that guard restoring any older backup would wipe every set and item. No log table exists, so
there is nothing to build a streak from.

Because a 2 GB phone ends the app whenever the person leaves it, a half-finished session is kept
in Android's saved instance state, not in a table.

## 8. Subliminal AI

### What HQ does

HQ's embedder is a table: 29,528 token rows of 256 numbers. A text's vector is the mean of its
tokens' rows. No network runs, it takes about 0.02 ms per query on a Galaxy A32, and it never
writes: its outputs are a ranking, a choice among pre-written strings, or tags that already
exist. Only one of HQ's proactive behaviours uses it, the "next step" offer, which fires when the
three nearest of 707 invented examples agree. In its held-out test that offer was right 22 times
of 23 and caught 22 of 120 useful cases: cautious by design. Everything else HQ does
proactively is rules, counts and shared words. Its written tests are: works with nothing
configured, costs nothing while idle, visible and undoable, measurable, nothing leaves the
device. No notification is ever used for discovery.

### What that means for a study Bible

In HQ, subliminal means the model writes nothing and needs no setup. In a study Bible it cannot
also mean unseen: a hidden model choosing which Scripture a reader sees is what your rule
forbids. Three consequences.

- **No model states or implies a relation between passages, labelled or not.** A "related
  verses" list beside a verse reads as a claim about Scripture. Human cross references do that
  job, with their source named. A neighbour table computed at build time and frozen into the
  database would sit beside Scripture with no visible seam, so it is cut.
- **Every ordering on screen has a rule a person can say in one sentence.**
- **An averaged-token model cannot see word order.** Verses with the same words and opposite
  sense score alike. Its vectors also carry associations from the web text it was trained on.

### What ships: HQ's discipline, exact joins, no model

Each of these is a join on an exact key. Each carries "Why this?", which states its rule, and
"Hide". One a day at most; the same kind once in three days; two "Not now" in a row mute that
kind for 30 days. Those are HQ's own constants. None is ever a notification.

| Line | Rule | Ships with |
|---|---|---|
| "<reference> is in today's reading. You are memorising it." | A practice item's reference falls inside today's plan chapters. | Practice |
| "You wrote a note here on <date>." on a cross-reference row | A cross-reference target overlaps one of the person's notes. | This verse |
| "<lemma> (<number>), a word you kept, is in verse <n>." | The same full Strong's key, sense letter included, is in the open chapter; the word is in 200 verses or fewer. | Word study, after the sense fix |
| "No downloaded commentary covers <book>." then every pack that does, in year order, with its size | The person opened Commentary and no installed pack has an entry for the book. Lists all, picks none. | Packs |

A "feature never opened" line was designed after HQ's untried-first chips. Cut it until a panel
session shows a feature going unfound.

### If a model is ever admitted

Only one use survives the rule: ordering verses for a query the person typed, in a group below
every word group, headed "Ordered by computed similarity. Not a cross reference." It never
attaches anything to a verse, never picks a daily verse or a notification, never ranks sources.

It must earn its place. The test: 200 questions written by at least five readers in Uganda, half
held out, with expected verses marked by the asker from a shuffled pool; 50 questions with
nothing to find, on which the group must stay empty 95% of the time. The model must beat the
repaired word search by 10 points of recall at ten. On the phone it may add at most 150 ms and
20 MB. As an optional pack it would be about 16 MB (int8 matrix plus verse vectors, computed
from the model's stated dimensions, which were not read from its own files).

Before that, a cheaper check that needs no readers: run the embedder over the heading and
KJV-words question sets that already exist, on a machine that can fetch the model, and print its
number beside the lexical ones. That is week-zero work, and it gives decision 3 a fact.

Preconditions if it goes ahead: the weights' licence has not been read at source; no model found
has published Luganda coverage; and the model is never fetched at run time the way HQ does it.
It would be a pinned optional pack.

## 9. Word study

### First, what is wrong on screen today

| Defect | Count | Fix |
|---|---|---|
| Looking a word up by its base number returns the alphabetically first entry (`bible_db.dart:844-850`). H5892B "city" shows H5892A "excitement". | 41,110 Hebrew tokens (13.45%) and 2,588 Greek (1.82%) when reached that way `[measured]` | `lexiconExact(key)` and `lexiconUnder(base)`; remove the fallback; carry the sense letter in `word_index`. This is the largest change: the module is keyed by base number throughout. |
| Greek missing. The reference pattern rejects STEPBible's bracketed verse numbers (`build_db.dart:282`). | 350 rows in 48 verses; no Greek at all for Romans 16:25-27, 2 Corinthians 13:13-14, Philippians 1:16-17 and John 7:53 `[measured]` | Parse both numbers; one `verse_map` table decides which a translation follows. |
| Hebrew rows lost to `INSERT OR IGNORE`. A word STEPBible reconstructs from the Greek can take the place of the Leningrad word, unmarked. | 75 rows in 15 verses `[measured]` | Plain insert; store the text type. |
| Five-digit Strong's numbers cut to four, which names a different word. | 3 tokens, in Acts 24:12, 2 Corinthians 11:28 and 1 Thessalonians 2:8 `[measured]` | `\d{4,5}` in three places. |
| Words that are in some printed Greek editions and not others are loaded and counted without a mark. | 4,450 rows with no Nestle-Aland reading; counts change for 681 of 5,417 Greek numbers `[measured]` | Store the edition list per word; every count names its text. |
| Aramaic verbs given Hebrew stem names; some verb forms not decoded; cohortatives called infinitives. | up to 965, 999 and 534 `[measured]` | Delete the hand tables; load STEPBible's own morphology tables (CC BY 4.0, confirmed). |
| Psalm titles at verse 0. | 478 rows in 116 psalms `[measured]` | Through the same `verse_map`. |
| Inputs fetched from a moving branch. | 11 of 15 build inputs have no pin `[code]` | Pin by commit and hash. |

Each fix comes with a build gate: rows read equal rows stored plus a named, counted list of
exclusions; every non-empty BSB verse has word rows; every stored number equals the number in
its source cell.

### Then, whose words these are

- Remove the 600-character cut. Uncut text adds 0.76 MB `[measured]`.
- Parse the trailing tag on each Greek entry into `source_id`: of the 9,550 loaded, 5,695 are
  Abbott-Smith, 1,982 Middle Liddell and 1,873 carry no tag `[measured]`.
- Titles say what the text is: "Abbott-Smith (1922), corrected and adapted by Tyndale House
  scholars (STEPBible)", not the bare author.
- Rows with no stated source show the gloss alone. Ten of them match Mounce's dictionary, which
  is all rights reserved `[measured]`; report those to STEPBible.
- `plainSenses`, "What it means" and "Its senses" leave the screen. They leave in the same
  release that adds the replacement below, never before.

**The plain answer nobody at Berea wrote: "How the BSB translates it."** The BSB's own
translation tables give every English rendering of a Hebrew or Greek word with its count. That
is a publisher's data, countable, and readable by someone who has never opened a lexicon. It is
the first thing on the screen after the pressed word and its verse.

### Outside the BSB

A pressed word is exact in the BSB (99.8% by its own tables). In the KJV and WEB it is a guess
by meaning: found 78 to 84% of the time, agreeing with the BSB tables 91.5% of the time
(README). Today the guess opens as a study. Instead, a press in the KJV or WEB opens "Words of
<reference>" with nothing chosen. One more tap, and a guess never looks like a fact. CrossWire's
tagged KJV exists, but its terms are unclear; it stays a lead to read, not a plan.

### Depth already downloaded and thrown away

All of this is in the files the build fetches today `[measured]`:

- the sense letter on 46% of Hebrew word tags and 7.9% of Greek tokens (H7307: one letter on 216
  tokens glossed "spirit", another on 145 glossed "breath");
- which of eight printed Greek editions contain each word;
- 1,323 Qere rows and their Ketiv readings;
- meaning and spelling variants;
- the main word inside a Hebrew token, with its prefixes and suffixes;
- the relation phrases that tie an Aramaic entry to its Hebrew one.

Each is shown under the name of whoever made the judgement, which is not always STEPBible. Its
own headers name ETCBC for Hebrew parsing, the Open Scriptures project for entry letters A to F,
and Scrivener 1894 and Robinson-Pierpont 2005 for two of the editions. Together these add about
2.5 MB (computed).

Hold three things until STEPBible says in writing how they were made: per-token sub-meanings,
sense letters from G onward, and person identifications.

### Pure counting

Parsing for every part of speech, fields only. Counts by form, which must sum to the total. By
book. First use. Used once. Words that stand in the same verses, with both numbers printed
("faith: 24 of its 226 verses") so a reader can check it, and never the word "related".

### New sources, in order of how clean they are

1. Dodson's Greek lexicon (CC0, confirmed).
2. OpenScriptures HebrewLexicon: Strong's Hebrew and the Brown-Driver-Briggs outline with root
   groups (text public domain, file CC BY 4.0, confirmed; upstream calls it work in progress).
3. The Abbott-Smith TEI, whole, with its "in LXX for" notes as a bridge from a Greek word to the
   Hebrew words it renders (public domain by its 1922 date; status outside the United States not
   checked). The Hebrew word is shown as printed; any Strong's number beside it is labelled as
   added by the digitisers.
4. Strong's Greek derivation links (public domain).

Left out: Mounce, the ESV tagging, Septuagint texts built on CATSS, an unlicensed full
Brown-Driver-Briggs, MACULA's machine-clustered senses, and every description field written by a
model.

### Proof, replacing the model eval

The build gates above. A golden set that covers every defect case, a seeded sample of 200 BSB
words read by two people who know Greek and Hebrew, 300 tokens from numbers with several entries
(asserting the token's own entry opens), and 300 KJV and 300 WEB presses (asserting none opens
as exact). The existing 376-word set stays as a regression test until then; it is skipped in CI
today because CI has no Bible `[code]`.

## 10. Commentary per verse, and depth

### One view: "This verse"

Reached from the verse selection bar. Everything below the text is a folded line with a count,
loaded when opened. The order rule is printed at the foot: "The text first, then what its
publisher prints with it, then cross-reference lists, then named writers, earliest first."

1. **The verse in each installed translation.**
2. **Translators' footnotes.** "BSB translators' footnote". The publisher's own USFM is public
   domain, 1.6 MB, and holds 4,854 footnotes in 4,314 verses and 1,324 parallel-passage lines
   `[measured]`. Berea strips all of it today (`importers.dart:57, 61`).
3. **The verses the BSB leaves empty.** Sixteen verse numbers have no text, Matthew 17:21 and
   Acts 8:37 among them `[measured]`. The publisher prints each in a footnote on a neighbouring
   verse. An empty verse gets a named state: "The BSB prints this verse in a footnote at 17:20",
   then the footnote and the KJV text. These are the verses a KJV reader is most likely to ask
   about.
4. **Parallel passages** as tappable chips, "Parallel passages printed by the BSB under this
   heading". Today they print as untappable italics.
5. **Cross references, in full.** "Cross references · OpenBible.info · 34 listed · Bible order".
   Each row shows the reference, the whole verse on tap, and its vote count. Today they appear
   only inside Synthesize, four to a section, with no source `[code]`. Fix a defect on the way: a
   target range that crosses a chapter keeps only its first verse (`build_db.dart:392-396`).
6. **Words used 3 or more times here**, replacing the hidden weighted top six and its caption
   "worth knowing".
7. **Commentary**, one folded row per work: author, work, years, licence, "1 comment on John
   15:1-8, 2,340 words".
8. **The person's own notes.**

Reconciling the two BSB files: the verse text comes from the pinned `bsb.txt`, the apparatus
from the USFM. Walk each verse word by word and require equal sequences; on a mismatch store
nothing for that verse and report it. On the files in the sandbox 31,101 of 31,102 verses agreed
`[measured]`. That was measured on a different USFM file from the one the build pins, so choose
one source, pin it, and measure again before writing the gate.

### Commentary per verse: what is known and what is not

Today a comment that covers a section appears whole on every verse in it, every tag is stripped
at build (including the source's own machine-readable reference targets), references inside
commentary cannot be tapped, and the search index inside each pack, 12 MB of the core pack's 42
MB, is never queried `[code]`.

Not known: how many verses would get a paragraph of their own. No pack could be built in the
sandbox. Before any pack format changes, build the eleven modules on a machine that can reach
the pinned files and print, per module: verses with their own entry, verses inside a range,
verses where a paragraph names the verse, and verses with none.

One cheap experiment first, needing no new pack and no second download: at display time, find
the paragraph that names the verse ("verse 5", "ver. 5", "v. 5") and open the comment there with
a margin bar, the whole comment still above and below. Label it as a position: "Paragraph 4 of 11
names verse 5". Make references tappable with the existing parser, accepting lower recall.

A new pack format with reference tables, a "cited elsewhere" index and commentary search is 4 to
6 weeks `[estimate]` and serves only readers who download 4 to 25 MB of 18th and 19th century
English. It waits until panel readers are seen installing a pack.

### More sources, honestly

No new public domain commentary was verified. Every CrossWire module file was unreachable from
the sandbox, so Scofield, Geneva, the People's New Testament, Lightfoot and the rest are leads
with unread licences. One 199 KB file (`mods.d.tar.gz`) settles all of them, and Nave's and
Torrey's topical indexes for decision 4, in about an hour.

Admitting a source: read the module's own file or the publisher's page, never an aggregator.
Published before 1931, and every author, translator and editor dead more than 70 years, each
with an evidence line. Human authorship shown by the publisher's statement or a page-scan match,
never by a date. Share-alike material in its own pack, never in the app download and never
merged with public domain text.

Status of the leads:

- Robertson's Word Pictures: the 1930 volumes are public domain in the United States since 1
  January 2026; later volumes are not; no clean text was found. Not now.
- John Gill: no source with documented provenance. Stays out.
- The patristic database: licence confirmed, with a fair-use duty on anyone who redistributes.
  It needs a per-row whitelist. It also carries a "condemned by council" flag of its own;
  dropping rows on that flag would be Berea deciding which ancient writers a reader may see.
  Either ship every row that passes the licence test, in date order, or leave the database out.
- unfoldingWord and Aquifer notes: share-alike. Every Swahili article sampled is marked with no
  review level and no stated translation method, so it cannot yet be shown as a person's words.

### Depth beyond the verse

A book outline from the publisher's headings, labelled as the publisher's. Old Testament in the
New from the BSB's own footnotes in citation form only: 288 New Testament notes begin with a bare
Old Testament reference and 181 Old Testament notes read "Cited in" `[measured]`. Shown as the
footnote says it, not relabelled as a quotation.

Left out because each is one author's reconstruction: chronologies, maps of disputed sites,
speaker labels, outlines beyond the publisher's headings.

Versification: the BSB and the KJV have the same verse count in all 1,189 chapters `[measured]`,
so KJV-keyed packs line up with the BSB. Add a build check that the WEB does too; none runs
today. One table, not two, maps a translation's numbering.

## 11. Prayer under the rule

Purely Scripture already: the Bible's own prayers stepped a verse at a time (their titles are
authored), "pray this verse" with no points, the person's own list and recorded answers.

Authored: everything in the first two rows of the table in section 2.

In the release that removes the chat, with no content removed:

- the verse comes first, in Scripture type; the point sits under it, smaller, in interface type;
- each point carries a plain label saying what it is and who read it;
- "Pray:" leaves the notification;
- nothing authored is drawn in Scripture type anywhere.

Later, with decision 1 and decision 4 answered: the topics become a list of references under a
named editor or give way to a named index; the points either leave the bundle or return as text
a named person wrote. A signature on the existing lines does not make them a person's writing.
If they return they are bundled, not downloaded: the whole file is 63 KB compressed.

The Praise / Confess / Thank / Ask / Others frame, the plan titles and the trimmed psalm plan
are selections with no named selector. A psalm plan over all 150 psalms, whole, is computed and
belongs in Plans. The stepper gains "Skip verse", so an omission is the person's.

## 12. What a first-time reader loses and gains

For someone on a 3 GB phone who has never used a concordance.

| Goes | When | What stands in its place |
|---|---|---|
| Asking a question in their own words | With the chat | Search that finds a half-remembered phrase and any name. Not a replacement for a life question: see the last row. |
| A 0.58 to 2.6 GB download and a wait of a minute or more | With the chat | Nothing to download; the app opens on the Bible. |
| Plain word senses ("What it means") | With word study phase 2, not before | "How the BSB translates it", with counts. |
| Study-page questions | With the chat | One blank field. A price of the rule; no replacement. |
| The Pray now frame | With decision 1 | The stepper with "Your words" under each verse. A price of the rule for a new user. |
| Prayer points and the 24 topics | Only when decision 4's door exists | A named index or a named editor's topic list. |

Gained in the same releases: the app installs at all on more phones; footnotes, parallels and
the full cross-reference list on every verse with nothing to download; Greek in every verse and
the right dictionary entry; a verse learned on a schedule that survives a shared or sold phone.

## 13. Listening

A model wrote the Listen script and a neural voice read it; both go. What remains is Bob Souer's
recorded narration of the BSB with word timings. Only John is built (27.1 MB `[GitHub]`), and no
player exists in the app `[code]`. By word share the New Testament would be about 253 MB and the
whole Bible about 1.07 GB (computed).

A named person reading the text is Scripture read by a named source. A synthetic voice is
machine output even when its words are Scripture, costs about 172 MB, and is unmeasured on a 3 GB
phone. Cut it.

Whether narration leads the queue is an open question, not a decision: it is English, it is
large, and the claim that it serves readers who struggle with English text is an inference.
Test it for the price of an afternoon by playing the existing John pack to panel readers. If it
goes ahead, fetch by chapter with the size on the button, mark verses the narrator read in an
earlier BSB wording, and say in Attributions that the word timings were computed by forced
alignment. Before building more packs, read the licence statement at the publisher's audio page.

## 14. Order of work

Estimates are for one developer `[estimate]`. The whole plan is about six months, not one
release.

**Week zero, no code.**

- Letters. To Online Bible: the Hebrew meanings Berea ships come from its abridged
  Brown-Driver-Briggs, and STEPBible's header says "Permission should be gained from Online
  Bible before these are applied in any project". To STEPBible: whether CC BY covers that
  column; whether a derived database is "posting a copy", which every header asks users not to
  do; where the untagged Greek rows come from; how the ETCBC and Perseus terms sit with CC BY;
  which fields are machine-written. Give both a 30-day clock.
- Read `mods.d.tar.gz` (commentary leads, Nave, Torrey) and the OpenBible licence page.
- Find out whether a Luganda and a Swahili Bible can be offered, with the licence read at source.
- Recruit one panel of 8 to 10 readers from one or two congregations. Buy one 3 to 4 GB Tecno or
  Infinix and one 2 GB 32-bit Go-edition phone.
- Build the database and run the test suite on a machine with the SDK. Build the removal branch
  once and read the real APK sizes.
- Run the embedder comparison (section 8).
- Answer the ten decisions.

**Release A. Ground (1 to 2 weeks).** Pin the 11 unpinned build inputs. Give CI a Bible
database, starting with a BSB-only one built from the committed `site/data/bible` JSON, so the
reader, shell and word tests stop skipping. Copy the database in chunks at first run. *A reader
sees nothing new; every later release is guarded by more than a lint.*

**Release B. Search that finds (about 2 weeks).** Section 6. *A reader can type "Jesus" or a
half-remembered phrase and reach the verse.*

**Release C. The Bible in the centre (4 to 5 weeks).** The removal, the shell, the provenance
column and label, the archive. Practice as Step through, Pray it back, Recall on the ladder, Due
and the person's sets. Prayer's presentation change. *A reader can install with no further
download and learn a verse on a schedule.*

**Release D. On real phones.** Lower the Android floor as far as proven; the 32-bit build;
resumable and verifiable packs; Share Berea; the feedback message; a store listing; the first
panel session. *A reader on an older or 32-bit phone can install it, and so can their friend.*

**Release E. This verse, and words that are right (6 to 8 weeks, in several merges).** Footnotes,
the empty-verse state, tappable parallels, the full cross-reference list. Word-study defects
first, then source names and "How the BSB translates it", with plain senses leaving only then.
*A reader can press any verse and see what its publisher printed with it, and gets Greek and the
right entry everywhere.*

**Release F. A door for life questions.** A named index or a named editor's topic list.
Decision 1 lands here.

**Later, on panel evidence only.** Hide words by first letters, Write out, Check a text (after 50
real forwarded messages), sets shared as references, commentary anchoring, the two hints that
depend on these features, the lexicon pack, narration.

**Cut.** The encoder and its test programme unless decision 3 says otherwise; the neural voice;
the imperatives list; marking translation differences (measured: it underlines a third of every
verse); underlining where a commentator's quotation differs from the KJV; a versification
interpreter before a real Luganda file is measured; MACULA on screen; the "feature never
opened" hint; the reviewed string ledger; three reminder slots and a widget, until one daily
notification is shown to arrive on a Tecno, an Infinix and an itel over seven days; QR.

### Gates that replace the model eval

`tool/release.sh` loses lines 16-20 and 44-48, which need a model. Each gate is turned on in the
release that introduces what it tests.

| Gate | Runs | From |
|---|---|---|
| Every build input pinned by hash | CI | A |
| Reader, shell and reference tests against a built BSB | CI | A |
| `search_check`: phrase set, vocabulary set, time per group | CI and the 2 GB phone | B |
| No generative package in `pubspec.lock`; no `RECORD_AUDIO`; no name of a model runtime in `lib/` or the harness | CI | C |
| Deny-list lint over interface strings | CI | C |
| `scriptureStyle` used only by the Scripture widget; no part-verse shown alone | CI | C |
| A version 3 backup restores and leaves practice tables alone | CI | C |
| APK 60 MB or less per ABI; first run on the 2 GB phone with 150 MB free | Release, by hand | D |
| Rows read equal rows stored plus named exclusions; every BSB verse has words; no number shortened | Release build | E |
| Every source text row has a source; shown text equals source text with whitespace removed | Release build | E |
| Each of the 16 empty verses shows its footnote or another translation | CI | E |
| Word golden set | CI | E |

## 15. Not known, and not checked

- Nothing was built or run. Every statement about a screen is read from code.
- The APK size without the model; any behaviour below Android 11; whether the 32-bit build
  compiles.
- Every timing on a phone with less than 5.5 GB of RAM.
- The search percentages in Dart against the real index.
- Which tags each commentary module carries, and how many verses get a paragraph of their own.
- Every CrossWire licence. Every model's weight licence. The OpenBible licence at source. The
  licence statement for the narration. Whether the BSB's public domain dedication names its
  footnotes, headings and markup, or only "Bible text".
- The licence of the KJV text Berea ships: it is an unpinned copy from a third-party repository
  (`build_db.dart:16-17, 50`), and CrossWire's own KJV module states other terms. Choose the text
  on purpose and pin it.
- Uganda's Copyright and Neighbouring Rights (Amendment) Act, No. 8 of 2026, in force since 22
  May 2026 `[search]`. Its effect on the term was not read. Get a legal reading before any 20th
  century text ships.
- Phone shares, RAM shares and data prices in Uganda: search summaries only.
- Whether any reader wants any of this. No one has been watched using Berea.

## 16. How this plan was made

Nine readers mapped Berea and HQ's embedder. One probe counted over the BSB text and the raw
tagging files. Four researchers looked for open data, each followed by a skeptic who re-checked
every licence at source and marked what could not be confirmed. Six designers each took one
area. Six critics then read all six designs through one lens each: a strict reading of the rule,
the codebase, an entry-level phone in Uganda, licences, product value, and completeness. The
critics found 133 issues; this plan follows them where they and the designs disagreed.

Every Scripture reference in this document was looked up in the BSB text committed under
`site/data/bible` before it was written down.
