# Berea, Scripture first

A plan, written 2026-11-10. Nothing in it is built.

It answers one request: remove the chat, put the Bible in the centre, add a place called
Practice built solely from Scripture, shrink the AI to something that never writes, and make word
study, commentary per verse and study depth more exact, with no personal opinions or ideas
anywhere and Scripture as the source of truth.

## How to read the numbers

Every figure carries one of these marks.

- `[code]` read in this repository at commit 4f68eb8, with the file and line.
- `[measured]` counted in this session by script. Unless the figure says otherwise the input is
  the BSB text in `site/data/bible` or STEPBible's files as fetched on 2026-11-10 from a branch
  that is not pinned, so a shipped database may differ. Figures about footnotes, marks, poetry
  lines and parallel passages were counted in the BSB publisher's own USFM on GitHub (release
  5.2), which is not the file the build pins; the two differ by 21 headings, so recount after
  choosing one.
- `[GitHub]` read from the GitHub API on the day of writing.
- `[search]` taken from search summaries because the source site was blocked from the planning
  sandbox. Treat as indicative.
- `[estimate]` one developer's guess at effort. Not a promise.

Nothing was compiled or run. The sandbox had no Dart or Flutter and no built `berea.sqlite`, so
anything about what a screen shows is read from code. Section 15 lists what could not be checked.

## 1. Your request, clause by clause

| You asked for | Short answer | Section |
|---|---|---|
| Remove the chat AI | Yes, in one release with no hidden stage. Few people are affected: 29 APK downloads exist across all seven releases `[GitHub]`. Search has to be repaired first, or the release that removes the chat ships a search box that answers "Jesus" with "No verses match." `[code]` | 4, 5, 6 |
| The centre Berea icon becomes the Bible | A change in two files (`lib/home_shell.dart`, and `lib/study_button.dart`, which becomes the Bible button) plus three test files. The brand guide ties the lamp mark to no feature `[code]`. | 5 |
| A new page called Practice | Yes. But "practice" has three honest meanings under your rule and you need to pick. | 3, 7 |
| Practices solely from Scripture, outside the box | The form that needs no chooser: Berea supplies only a mechanic, and the passage supplies every word. A list that pairs a practice with verses is a selection, and a selection needs a named person behind it. That route is open (decision 3) and scheduled (Release F). | 7 |
| AI reduced to something like HQ's embedder and its proactive uses | Take HQ's discipline and leave the model out of Releases A to F. Berea's triggers carry exact keys (a reference, a Strong's number, a plan day), so a join is exact and adds 0 MB. In practice that is one unprompted line in Release C and two more in Release E. A model has one possible use, with a pass mark (section 8). | 8 |
| Deeper accuracy of word studies | Fix what is wrong on screen before adding depth: Greek missing from whole verses, numbers cut to the wrong word, a fallback that opens the wrong entry, and definitions shown with no author. | 9 |
| Commentary per verse | Not in Releases A to F in the form you asked for. Two steps are scheduled: count, per commentary, how many verses get a paragraph of their own (before any release); then open each comment at the paragraph that names the verse (Release E). No new commentary could be verified this session. | 10 |
| Depth of studying | One view per verse that joins text, the publisher's footnotes, parallels, cross references with their source, and commentary. | 10 |
| No personal opinions; Scripture as the source of truth | Written as a rule (section 2). Type style, source names, part-verses and bundled lists get mechanical checks. What a sentence says cannot be tested by a machine; a named person reads each new or changed string. The rule is already broken in the app, mostly in Prayer, and applying it removes more than the chat. | 2, 3, 11, 12 |

## 2. The source rule

Everything Berea shows belongs to one class, and the class is visible.

1. **Scripture.** Words from an installed translation or a named original-language edition, with
   reference and translation beside them. A verse is never shown in part unless the whole verse
   is on the same screen. Psalm 14:1 in the BSB contains the sentence "There is no God."
   `[measured]`; a screen that showed that phrase alone would drop the words the BSB prints
   before it, "The fool says in his heart,". The word-hiding drill is the one labelled exception.
2. **A counted fact.** A number or a list that a script recomputes from pinned inputs. Its rule
   is printed beside it in one sentence and the rows behind it open in one tap.
3. **A named source.** A person's or publisher's words, shown whole, under the name of whoever
   wrote them and whoever carried them to us, with the licence one tap away. This class is wider
   than it looks. Tagging, glosses, parsing and sense divisions are a scholar's analysis, not a
   count, so "tagged 216 times" becomes "tagged 216 times in STEPBible's tagging". Section
   headings, footnotes, red letters and supplied-word marks are the translation publisher's. Vote
   counts on cross references come from a website's visitors, who are not named, and the screen
   says so.
4. **The person's own words.** Notes, prayers, sets.
5. **Interface wording.** The name of a place or a control, a fact about the app or the device,
   or the source or rule behind what is on screen. It never says what a verse, word or book
   means, never tells the reader what to do in faith or life, never evaluates, never gives an
   author or translator a motive, never asks a leading question.
6. **Machine output.** Not Scripture, not a fact, not a source. No new machine output is made or
   added in the releases planned here. Three kinds made earlier stay visible for a time, each
   under a fixed label: saved chat answers (section 5); the prayer points and plan-day titles
   until Release F (section 11); and sentences STEPBible generates inside its name entries until
   Release E drops them (section 9).

Two rules follow from applying this honestly.

- **A selection names its selector.** Where Berea ships a list (which commentaries it carries,
  which reading plans, the verse of the day, the mechanics on the Practice page), the screen
  says who chose and by what rule. Claiming that nothing was selected when something was is its
  own kind of opinion.
- **A source is shown losslessly.** The text on screen, with whitespace removed, equals the text
  in the source file. Line breaks at the source's own sense numbers are allowed. Rewording and
  silent cuts are not. Where part of an entry is left out, the screen says so.

### How it is enforced

- **A named person reads every new or changed interface string** against item 5 before release,
  and says so in the pull request. A model may not be that reader. Nothing mechanical can tell
  what a sentence says.
- A deny-list lint over string literals in `lib/` and the harness is a tripwire, not proof:
  words such as mean, should, must, worth, key, deeper, promise. Most of the breaches listed
  below contain none of those words.
- One `sources` table (`id, originator, carried_by, work, year, licence, url, changes,
  machine_written`), and `source_id NOT NULL` on every row of source text. The README, the site
  and the Licences screen are generated from it.
- One Scripture widget that accepts only a value `BibleDb` can create, and a test that
  `scriptureStyle` is used nowhere else.
- Bundled lists regenerate byte for byte from a recorded rule and pinned inputs, the way
  `build_prayers.dart --check` works today `[code]`.

About 30 interface strings fail the rule today outside the model's own files. That is one
reviewer's reading of a list a script extracted, not a count. They are fixed by hand in the
release that touches each screen. An earlier idea, a reviewed ledger of every interface string,
is set aside: for one maintainer it would prove bookkeeping, not review.

### Where the app breaks the rule today

| Where | Fact | What the rule asks |
|---|---|---|
| Prayer points | About 1,970 lines of prose, each tied to a verse. The commit that added them says they were written "then read against the verse text by a second model, which reworded 88 lines", and it is co-authored by a language model (`c396c7e`, `[code]`). The app shows the line in Scripture type at size 22 with the verse smaller beneath it (`lib/prayer_words.dart:364-375`). TECHDEBT records that the check "cannot judge that a line says no more than its verse". | Section 11. Decision 1. |
| Prayer topics, plan and day titles, the Praise / Confess / Thank / Ask / Others frame, "Verses many people stand on", the ten "Prayers of the Bible" and their titles, the trimmed psalm plan | Hand choices with no rule recorded and no chooser named. | State who chose, or replace with a computed list. |
| "Pray: ..." in the daily notification | An authored line on the lock screen (`lib/daily_reminder.dart:97`). | The notification is the reference and the verse. |
| "No prayer points for this verse. Pray it as it is, or in your own words." | An instruction (`lib/pray_verse_sheet.dart:88`). | Goes. |
| Verse of the day | The 366 single verses with the most summed OpenBible votes; day N is rank N `[code]`. The card says only "VERSE OF THE DAY", and it is the content of the daily notification. | Decision 10. |
| Reading plans | Four hand-chosen plans; one is described "Prayer and wisdom, a few psalms and a proverb a day." (`lib/plans.dart:71`). | Print who chose and the rule; describe by content: "Psalms and Proverbs, 181 chapters". |
| "What it means" and "Its senses" in word study | A regex rewrite of a lexicon definition, at most four senses, with no source named (`plainSenses`, `word_study.dart:598-685`). | Show the entry whole under its author's name. |
| Lexicon definitions | Cut at 600 characters, which removes the trailing source tag from 778 of 779 long Greek entries `[measured]`. Abbott-Smith and Brown-Driver-Briggs are named nowhere in `lib/`. | Full text, named. Hebrew: see decision 9. |
| Captions | "Hebrew and Greek words worth knowing in this passage", "One English word can stand for several Hebrew and Greek words", "The translators supplied X here so the English reads well", "What does it mean?", "How should I live?" | Replace with the rule or the source. |
| Synthesize | "Witnesses from the other testament" with the caption "Verses across the Bible that the passage points to." over verses ranked by OpenBible votes, with no source shown (`lib/study_packet_screen.dart:114-115`). | "Cross references into the other testament · OpenBible.info · most votes first · the votes are that site's visitors'". |
| Shipped Hebrew name entries | 3,219 of 4,477 carry a formulaic sentence ("A man living at the time of ..., first mentioned at ...") `[measured]`. The lexicon file does not say how it is made. STEPBible's README says the longer person descriptions in a separate file, which Berea does not load, were "created by Claude 3 AI". Whether this sentence comes from them was not checked. | Split the sentence off and drop it until STEPBible says how it is made. |
| Kept chat answers, kept words, kept commentary | All stored as notes. A kept answer cannot be told from the person's own writing; a kept word holds Berea's shortened or reworded form of a lexicon entry `[code]`. | One provenance column and three labels (section 5). |

## 3. Decisions only you can make

Thirteen. Eight can be answered today (1, 2, 3, 6, 8, 10, 11, 12). Four wait for the reading and
counting in section 14's first step (4, 5, 7, 13). One has a clock (9).

**1. Does the rule reach content Berea already ships that no model writes at run time?** That is
the prayer points, the 24 topics, the Pray now frame, the plan titles, the plain word senses and
the two study-page questions. You did not ask for these to go; they follow from the rule.
*Recommendation:* yes, in three steps. Release C changes only presentation: the verse first and
in Scripture type, the point smaller under it with its label, no "Pray:" on the lock screen.
Release E replaces the plain senses in the same merge that adds their replacement. Release F
removes or replaces the prayer content, the frame and the study-page questions, once the door in
decision 4 exists.
*Cost to a reader:* a new reader loses the most (section 12). The topics (farming and rain,
exams, looking for work) are the most locally shaped content in the app.

**2. What does "Practice" mean?** Three readings. (a) Mechanics Berea performs on a passage the
person chooses: step through it a verse at a time, hide its words, recall it, write under it.
(b) Rows that open a word search with its rule printed, for example "Verses with 'give thanks' in
the BSB: 36" `[measured]`. (c) A list of practices with verses, chosen and signed by a named
person, references only.
*Recommendation:* (a) in Release C under the caption "Things Berea can do with a passage you
choose. Berea chose these mechanics. This is not a list of what Scripture asks." Then (c) in
Release F. Not (b) on the Practice page: which words get a row is a choice with nobody's name on
it. Word search stays where it is, in search.
*Cost:* until Release F, a new reader opens Practice and finds one working row.

**3. Who may be a named editor?** Decisions 2 and 4 and the prayer points all wait on a named
person. Options: you, under your own name; a pastor or a small group you name; nobody, in which
case a list of practices, the topic list and the prayer points are all closed and a public
domain index is the only door.
*Recommendation:* name one person now. The screen reads "Chosen by <name>, <year>. References
only." *Cost:* Berea carries one named person's selection, shown as that.

**4. What is the door from a life need to verses once the chat is gone?** Word search cannot
carry today's words to the Bible's: "exams" and "school" are in 0 BSB verses and "job" finds
only the name Job, 61 verses `[measured]`. Options: a public domain topical index (Nave, Torrey)
under its author's name, if its licence reads clean; the 24 topic titles with references only,
under the editor of decision 3; or word search alone.
*Recommendation:* read the licence first, then pick one of the first two. No topic is removed
in any release before one of them ships. *Cost of word search alone:* a reader with a question
about their life has no door.

**5. May a model ever order verses on screen?** Never; or only for a search the person typed,
under a label, and only if it passes the test in section 8.
*Recommendation:* the second. Nothing ships in Releases A to F either way. A model never states
a relation between passages, never picks a daily verse, never writes.
*Cost of "never":* a search whose words are in no translation and no gloss finds nothing until
decision 4's door exists.

**6. When needs conflict, who comes first?** A new reader on a 3 GB phone, or a teacher who
wants editions, variants and Qere. *Recommendation:* the new reader. It puts everything in
sections 9 and 10 that is not in Release E behind reach, search and language.

**7. Languages.** Everything here deepens an English product. Berea already imports USFM, OSIS,
Zefania and CSV, so offering a Luganda or Swahili Bible is mostly a licence question, plus book
names in the reference parser and search on the text.
*Recommendation:* find out whether one can be offered. If so it gets its own release straight
after Release D and before Release E. If not, the README says so.
*Cost of waiting:* every release until then serves English readers only.

**8. Will Berea ever be sold, bundled for pay, or preloaded on phones?**
*Recommendation:* no, and say so in the README. *Cost to a reader:* none. Your answer is needed,
but it does not settle the two licence questions behind it. Hebrew parsing in the STEPBible
files comes from ETCBC, whose own licence is non-commercial, and Greek parsing rests on work that
is share-alike. Those need the letters in section 14 whatever you answer.

**9. If Online Bible has not granted permission after 30 days.** The Hebrew meanings Berea ships
are Online Bible's abridged Brown-Driver-Briggs, and STEPBible's file says "Permission should be
gained from Online Bible before these are applied in any project". They are on screen in all
seven published releases.
*Recommendation:* build the fallback first (Strong's Hebrew from the OpenScriptures
HebrewLexicon, confirmed CC BY 4.0 over public domain text) so the swap is one build setting,
and swap in the first release after day 30 without a written grant. No release prints
"Permission requested". You also decide whether the published releases and the lexicon pack
stay up. *Cost to a reader:* an older, shorter Hebrew entry until permission arrives.

**10. What does Berea say about its own choices?** The catalogue of commentaries, the reading
plans, the verse of the day, the 66 books it carries. Today the app answers a citation from a
book outside those 66 with "Not in Scripture" (`lib/chat_screen.dart:766`) and the site with
"There is no such book in the Bible." (`site/page.js:332`), which is a verdict on the canon.
*Recommendation:* state each as a fact about this phone: "No translation on this phone has a
book named Sirach." Print the catalogue's rule: "English works whose licence Berea could verify.
Being listed is not a judgement of them." Plans page: "Four plans chosen by Berea's maintainer.
Each is whole chapters in Bible order, spread evenly over its days." Verse of the day: in
Release C the card and the daily notification take the first verse of today's plan reading when
a plan is running, and nothing otherwise.
*Cost:* no verse of the day for a reader with no plan.

**11. Marks on the Scripture text.** The BSB publisher marks words of Jesus (2,302 spans) and
supplied words (19,771 spans) and prints section headings `[measured]`. All three are the
publisher's.
*Recommendation:* headings stay in the reader as today, under "Headings are the BSB publisher's,
not Bible text". Red letters and supplied-word marks are off until switched on, with a legend
whenever on, and never used as a filter. Whether headings may also be searched is part of this
decision: section 6 proposes it, last and under the publisher's name; say no and the group is
dropped.

**12. Old machine-written text and the model files on upgrade.**
*Recommendation:* keep every saved answer readable under one fixed label, offer export and
"Delete all", and delete the model files (up to 3.66 GB) without asking, saying so once on an
upgrade card. *Cost:* none, unless someone wanted to keep the model.

**13. How does Berea reach phones?** Today the only route is an APK on GitHub. Options: a store
listing; an APK passed from phone to phone; both.
*Recommendation:* both, as part of Release D, after the first panel session shows how apps
reach these readers' phones.

**Applies unless you say otherwise.** Bar order Plans, Practice, Bible, Prayer, Notes; the
sidebar keeps Bible first. Cross references default to Bible order with the vote count shown.
Commentaries are ordered by year first published. Controls are named by what the app does
("Your words under each verse", "Done"), not by an act of faith ("Pray it back", "Amen"). Counts
of a Greek word use the printed text behind the open translation where that is verified, and
show both numbers where two texts differ. Berea records on the phone only what a feature needs:
practice items and their due days, and later which unprompted lines it showed, never displayed.
No synthetic voice. No streaks, scores or praise. No QR scanning: it brings a closed Google
component. What a second tap on the Bible button does (book picker or search) is settled in the
first panel session.

## 4. The case, as a product manager

**The problem.** Today Berea installs only on Android 11 or newer and 64-bit phones, and both
limits exist because of the model (`android/app/build.gradle.kts:35-36, 53-57`). The model itself
is optional: a 0.58 to 2.6 GB download that only the chat, Listen and dictation need. Reading,
search, word study and prayer already work with nothing downloaded `[code]`. So the reader who
never wanted the chat still pays for it, in phones that cannot install the app and in megabytes
of native library. On the one phone ever measured, a Galaxy A32 with 5.5 GB of RAM, first words
took 49 to 125 seconds (CHANGELOG). The model is also the only part of the app that writes new
sentences that are neither Scripture nor a named source. And it has been taking the work: of the
last 15 merged changes, 8 were about the model's wording, citations or prompt and 5 about
Scripture data, reading or study depth `[code]`.

**For whom, at what scale.** Removing the model lets the Android floor drop (Release D) and
shrinks the APK by an amount not yet measured. Uganda has about 20.5 million smartphones, and new
entry phones ship with 3 to 4 GB of RAM `[search]`. How many of those the current build excludes
is not known: the only figure found is an upper bound of about a fifth of Android web use below
Android 11 `[search]`, and no share of 32-bit phones was found at all.

**What is lost.** Anyone who set up the helper loses questions in their own words, drafted study
pages, questions over their own PDFs, the spoken deep dive and offline dictation. How many
people that is cannot be counted: the default model downloads from Hugging Face and a Mac uses
Ollama, and Berea sees neither. The ceiling is everyone who installed Berea: 29 APK and 20 macOS
downloads across all releases `[GitHub]`, the owner's own included.

**Five things that would hurt if the request were followed to the letter.**

1. *Search is broken for a reader, and the chat hid it.* The search box uses the chat's query
   builder, whose stoplist holds "god", "lord", "jesus", "christ" and "help"
   (`bible_db.dart:402-412`). "Jesus" builds no query and the screen says "No verses match."
   (`lib/search_screen.dart:62`). The BSB has that name in 1,382 verses `[measured]`. Repair
   search before the chat goes.
2. *The rule removes more than the chat.* Section 12 adds up what a new reader loses and sets
   each loss beside what replaces it.
3. *"Like HQ's embedder" is best answered without the embedder,* for now. Section 8.
4. *Nobody uses Berea yet,* and no reader has been watched using it. Meeting readers and getting
   the app onto phones are work in this plan, and the first session comes before any release.
5. *English only.* Decision 7.

**How success is judged with no data collected.** Sizes and timings on a bought 3 to 4 GB phone
at every release, and on a 2 GB 32-bit phone from Release D, when a build for it first exists.
One task script per release with a pass count from a standing panel of 8 to 10 readers, for
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
Ctrl F for search, and on a phone put search one tap from every place: today it opens from the
reader alone.

`StudyButton` becomes a stateless `BibleButton(selected, onPressed)`. The writing glow, both
progress rings, both badges and the download tap go; they only described the helper. The brand
guide asks for the mark at 57.8% of a round mask, so `_markScale` 0.62 becomes 0.578, and the
sidebar mark, at 15.4 px today, rises to the 16 px minimum `[code]`. The mark stops meaning "ask"
anywhere in the app.

Prayer keeps its place for now. Its home should not move before decision 1 is settled. If the
authored lines leave, the order becomes Plans, Practice (holding the prayer list), Bible, Search,
Notes.

### Every door into the model, and what stands there afterwards

| Today | Afterwards |
|---|---|
| Study chat, suggestion chips, Go deeper, "Brief answers first", the scope bar | Nothing. |
| "Ask" on the verse selection bar | "Words" takes the slot now, because it works from bundled data on first run. "This verse" (section 10) takes it in Release E. |
| "Ask Berea about <word>" in word study | Nothing. The screen keeps every use and Keep. |
| "Draft with Berea" on a study page | Nothing drafts. The page and its three fields stay until decision 1's last step. |
| "Ask about this notebook" and its side panel | Synthesize becomes the default pane, with its two captions reworded in the same release (section 2). Add "Search this notebook" over the existing index. |
| Listen (a model writes a script, a neural voice reads it) | Removed. Section 13. |
| Voice questions and note dictation | Removed. The keyboard's own voice typing needs no app permission. |
| Past questions | A read-only archive under Notes, shown only when a saved answer exists. |
| Helper setup, download sheet, the engine rows of Settings (`lib/settings_sheet.dart:291-393`), sidebar footer, Gemma terms | Nothing. The Settings dialog itself stays and is retitled: it is called "Engine" today and also holds translations, packs, reminders and backup. |

### Stored text

Nothing a person can read today is deleted unless they delete it, and old backups keep
restoring.

- One new column on `notes`, `study_pages` and `notebook_sources`, named `provenance`, with five
  values: `person`, `source`, `berea_rewrite`, `machine`, `unknown`. Agree the name and the
  values once: a shipped migration is never edited.
- Backfill. A note whose text equals the text of any assistant row in `messages` or
  `notebook_messages` is `machine`, whatever its title: a full study kept after "Go deeper" is
  titled with the question but saved under the words "Go deeper" `[code]`. A note with
  `kind` `word` or `studyword` is `berea_rewrite`: its body is a definition cut at 600
  characters or reworded by `plainSenses` `[code]`. A plain note titled "<installed work> on
  <reference>" whose last line is that work's "<author> · <licence>" is kept commentary and is
  `source`. Study pages written before this release are `unknown`, because a draft and the
  person's edits share three columns. Everything else is `person`. A `notebook_sources` row
  copied from a note takes that note's value.
- Labels, wherever such text is shown, exported or shared. `machine`: "Written by a language
  model in an earlier version of Berea. It is not Scripture and not a named source."
  `berea_rewrite`: "Shortened by an earlier version of Berea from a lexicon entry. Not the entry
  as written." `unknown`: "Written before this version. Parts may have been drafted by a language
  model."
- A kept answer whose saved conversation was already deleted cannot be found by the backfill.
  The upgrade card says so.
- `conversations`, `messages` and `notebook_messages` stay in `userTables` so backup versions 1
  to 3 restore. Nothing writes to them again. The backup version rises to 4, and the backfill
  runs after restoring an older one.
- The model files, the voice files and the listen recordings are deleted on first launch after
  the upgrade, by exact name, with one card: "The helper was removed. N GB freed. Saved answers
  are in Notes."

With 29 downloads to date this is kept small: one column, three labels, one archive with Export
and Delete all. No per-field provenance, no "mark as mine" workflow.

### What is deleted

From `lib/`: `edge_engine`, `models`, `helper_setup`, `download_details_sheet`,
`helper_download`, `voice`, `voice_composer`, `voice_wav`, `listen`, `listen_voice`,
`listen_screen`, `chat_screen`, `past_questions`, `notebook_ask_panel`, `notebook_chat`,
`study_button`; and `terms.dart` cut to what still applies.

From the harness: `harness`, `prompt_builder`, `engine`, `ollama_engine`, `tier`, `truncation`,
`listen_script`, `speech_text`, the model halves of `sources.dart` and `study_packet.dart`,
`bin/berea`, `bin/eval`, `bin/prompt_size`, `bin/retrieval_check`, `bin/notebook_fixture`,
`eval/*.json`. The `Retriever` class goes with its three callers. The `StudyContext` type in the
same file stays and moves beside `citation_guard`, which takes it in `apply` and which
`bin/export_site.dart:122` builds for the site.

Assets: `prompts/system.md`, `licenses/gemma/`, `licenses/supertonic/`.

Dependencies: `flutter_edge_ai`, `flutter_edge_ai_litertlm`, `record`, `sherpa_onnx`,
`audioplayers`, `connectivity_plus`. No pack download checks the Wi-Fi-only switch today, and
both screens that hold the switch are deleted `[code]`. Each pack button shows its size. A
Wi-Fi-only switch for packs would be new work and is not planned.

Permissions and platform pieces: `RECORD_AUDIO`, both foreground-service permissions and the
deep-dive `<service>`, the iOS memory entitlements, microphone strings, the macOS dylib staging,
the gstreamer packages in CI, and the `totalMemory` method of the device channel. The channel
stays: iOS uses it to keep the data folder out of iCloud backups.

Words: the README, the site, the web manifest and the pubspec description still describe a
language model and are rewritten in the same release.

40 TECHDEBT rows close `[code]`: 34 about the chat, the model and voice input, the terms row,
and the five Listen rows.

### Reach, after the removal

- The Android floor among the remaining plugins reads as API 24, Android 7.0 (from the locked
  plugin sources; Flutter's own floor and the 32-bit build were not checked). Lower `minSdk` only
  as far as a real phone or emulator proves.
- 32-bit ARM needs a PDFium pin for `android-arm` and the `armeabi-v7a` exclude removed. It is
  built only if the panel's own phones show a need.
- The first-run copy reads the whole database into memory and writes it over the live file
  (`lib/app_state.dart:656-658`). Its size was not weighed here: the README says about 81 MB, the
  app's own text says 85, and the comment over the copy code says 67. On a 2 GB phone that copy
  is the real risk. Copy in chunks to a `.part` file and rename, before the floor is lowered.
- The 0.8.0 APK is 101.9 MB `[GitHub]`. What it weighs without the model is not known: the one
  subtraction offered did not add up. Build it and read `--analyze-size` before any figure is
  published. Budget: 60 MB or less per ABI, about 150 MB on the phone after first run.
- "Share Berea": hand the installed APK, and any downloaded pack, to the system share sheet, so
  one download can be passed on without more data. Whether readers pass apps this way is a
  question for the first panel session. Pin the hash of the unpacked pack as well as the
  compressed one, so a pack passed from phone to phone can be verified offline.

## 6. Search that finds

This ships before the chat is removed. It needs no model and adds 0 MB.

Measured on a Python copy of today's query builder over the committed BSB, without the app's
word-form expansion, so every figure needs re-running in Dart against the real index
`[measured]`:

- Four consecutive words cut from a BSB verse (1,990 of them, exact wording): the source verse
  is first 32.6% of the time and in the top ten 60.2%; 4.3% build no query at all. With an
  exact-phrase group first: 75.5% and 95.1%.
- Six consecutive KJV words, looking for the same verse in the BSB (2,000): 40.9% in the top ten
  today, 49.4% with the best word-search variant tried, before an "Exact words in KJV" group is
  added.
- BSB section headings used as questions (3,096): 53.9% in the top ten today. The lexical
  variants tried moved that by about 2 points.
- Phrases as readers remember them, often from a translation Berea does not carry, are untested.
  The panel's first task script tests them.

Design:

- `BibleDb.searchVerses` returns labelled groups, in this order: "Go to <reference>"; "Exact
  words"; "Exact words in KJV" (or WEB) when the open translation has none; "All your words";
  "<n> of <m> words"; for a single word, one group per original word, every one listed and none
  picked: "<lemma> (<number>), glossed '<word>' in STEPBible's tagging: <n> verses"; last, if
  decision 11 allows it, "Section headings, printed by the BSB publisher".
- Every group is in Bible order, so no ordering exists that a reader cannot check.
- The stoplist shrinks to about 40 function words. A query made only of those runs as a phrase.
  Taking the four names and "help" out of the stoplist is the first merge.
- The index stores stems (`porter unicode61`, `build_db.dart:100`), so a phrase hit is only a
  candidate. Confirm each by comparing normalised words before printing "Exact words".
- A spelling line built from the translation's own vocabulary: "No verses have 'X'." followed by
  every candidate one edit away with its verse count. All candidates, not one pick.
- Run on a worker with its own read-only connection, wait about 300 ms after the last keystroke,
  show groups as they arrive. Today the one query runs inside `build` on every keystroke.
- Make the word pattern Unicode-aware. It is ASCII letters only today (`bible_db.dart:313`),
  which fails a Luganda or Swahili text.

Gate, `bin/search_check.dart`: the cut-phrase set at 93% in the top ten and 70% first (targets);
500 sampled vocabulary words each return a result; a p95 time per group on the 3 to 4 GB phone.

## 7. Practice

### What it is

A practice is a mechanic. Berea performs an operation on a passage that the person, their plan
or one of their sets supplied. Every word on the screen is a verse from the installed
translation, a count, or the person's own. The page says: "Things Berea can do with a passage
you choose. Berea chose these mechanics. This is not a list of what Scripture asks."

Why not a list of practices with their verses? Because the pairing is the opinion. Generating it
from the text does not remove the choice; it moves it to whoever picks the word. Measured on
STEPBible's tagging `[measured]`:

- The verb in Psalm 119:11 that the BSB renders "hidden" (H6845) is tagged in 31 verses. Exodus
  2:2 and Proverbs 1:11 are among them.
- The verb in Joshua 1:8 and Psalm 1:2 that the BSB renders "meditate" and "meditates" (H1897)
  is tagged in 24 verses. Psalm 2:1 and Isaiah 8:19 are among them.
- The BSB has no verse with "memorize" and none with "by heart".

A lemma list is a concordance. It is useful, and it belongs in word study with its rule printed.
It becomes a list of practices only when a named person says so (decisions 2 and 3).

### The mechanics

| Mechanic | What the person sees | What Berea computes or checks | What it records |
|---|---|---|---|
| **Step through** | One whole verse a screen, reference and translation, "3 of 12", "Next verse". Built by generalising the existing verse-at-a-time stepper (`lib/prayer_pray_now.dart:532`). | Nothing. | Nothing. |
| **Your words under each verse** | The same stepper with one empty field under each verse and "Add to my prayer list". No frame, no points. | Nothing. | The person's words, as theirs. |
| **Recall** | The reference, the verse hidden. The person says it, taps Show, marks "Word for word" or "Not yet". No keyboard needed, so it works on any phone and in any language. | The next due day. | Rung, due day, last result. |
| **Hide words** | The verse whole, then five stages hiding 0, 25, 50, 75 and 100 percent of its words. Positions come from a shuffle seeded by the verse, so each stage contains the last. Tap a blank to see it. | The stages. | Nothing by itself; it ends in Recall. |
| **First letters** (after a keyboard test on a Go-edition phone) | Type the first letter of each word; a right letter shows the word. | Words right first time. | As Recall. |
| **Write out** (later) | Type the verse; it is drawn with each word marked same, missing or different, "24 of 26 words the same". | Word-by-word alignment. | As Recall. |

Scheduling is a fixed ladder: 1, 2, 4, 8, 16, 32, 64, 128 days. A pass climbs one rung and a miss
returns to the first. It can be explained in one sentence, which a fitted scheduler cannot. The
pass mark and the reset are provisional until a panel session has tried them.

What is due is worked out from `study.sqlite` when Berea opens, never from whether a
notification fired, so a phone that kills background work loses nothing. The screens show "Due
today: 3" and "Last recalled word for word: 4 November". Never a streak, a score, a percentage
or praise.

### Where passages come from

Berea chooses the mechanics and, through its reading plans, today's plan reading; the page says
so. The person chooses the rest. The rows are: Due; Where you are reading; Today's plan reading
(from the plan the person started); My sets.

On a new install the page has one working row, "Where you are reading: John 1". Due, Today's
plan reading and My sets are empty until the person starts a plan, highlights a verse or adds a
prayer. "Your highlighted verses" and "Verses on your prayer list" appear as sets once each
holds a verse, and every verse list in the app gets "Save these as a set".

### Outside the box, and inside the rule

Each of these is a mechanic on the text with nothing authored. The data each rests on is stated.
None is in Releases A to F except where section 14 says so.

- **Hear and repeat.** Play a verse from the recorded narration, say it back, mark it on the same
  ladder. Read-along marks each word as it is spoken. This is the one mechanic here that needs no
  reading. Narration with word timings exists for John only `[code]`, and it is English.
- **The publisher's lines as layout.** 12.5% of BSB verses (3,894 of 31,086 with text) do not end
  with a full stop, question mark or exclamation mark, and 7,628 verses sit on poetry lines the
  app discards `[measured]`. Lay each verse out in the publisher's lines where they exist, with
  the whole verse always on the screen. A line is never an item, a step, a recall prompt or a
  notification by itself: in the publisher's file "There is no God." stands on its own line in
  Psalm 14:1. Show "The sentence continues in verse 23" with one tap to extend the item.
- **Whole books at a sitting.** A reader view without verse numbers or headings, with the word
  count and reading minutes computed from the text.
- **Word for word elsewhere.** "These words occur word for word in N other verses." 410 verse
  texts occur more than once in the BSB, in 990 verses `[measured]`.
- **Questions here.** "7 verses in this chapter have a question mark in the BSB." 2,527 verses
  have one `[measured]`. Each row is the whole verse and opens the chapter at that verse. The
  caption reads "This list does not say who asks or who is asked." The field under it is "Your
  notes".
- **Sets that travel as references.** A set is shared as one line of text,
  `Berea set 1: Jhn 3:16-18; Psa 23; Rom 8:28`, through the ordinary share sheet. The receiving
  phone renders the words from its own Bible, so no free text can ride along. No accounts, no
  server, no shared progress.
- **Check a text.** Paste a message; Berea reports which references exist and how many quoted
  words match each installed translation, with the verse beside it. It reports counts and
  verses, never true or false, and the pasted text is never stored. It reuses the citation
  check, which already runs with no model. Three cautions before it is built. Readers must first
  bring 50 real forwarded messages, because "Not found word for word in BSB, KJV, WEB" misleads
  when the message quotes a translation Berea does not carry. The reference pattern takes
  ordinary short words for book names when a number follows them: Luganda "ne 2" reads as
  Nehemiah 2, Swahili "na 5" as Nahum 5, English "the job 3 days ago" as Job 3 `[code]`; it
  needs a strict grammar first. And its wording about books follows decision 10. The site
  already ships the BSB and a JavaScript copy of the check, so this could run in a browser with
  no install.

### What is left out, and why

- **A list of imperatives in the chapter.** It was designed and should be cut. Filtering by verb
  form leaves out Matthew 22:37 and John 13:34, which the BSB calls commandments in Matthew
  22:38 and John 13:34, while listing John 13:27, where the words are spoken to Judas
  `[measured]`. Exodus 20:2-17 holds 12 second-person imperfects and 1 imperative in the
  tagging `[measured]`, so the list would show one verse of that passage. A list like that
  will be read as a list of orders whatever the caption says.
- **Fasting.** No mechanic, no timer. The existing switch on a prayer plan goes in Release F.
  Anything touching health needs a named health source.
- **Giving thanks, remembering, teaching a child, singing, confessing.** The designs listed
  these. None is a mechanic, so each would be a hand-picked list of verses. They wait for
  decisions 2 and 3.
- **Reminders labelled with a verse about a time of day.** A reminder slot is a clock time and
  nothing else. Its content is the reference and the verse of the first due item.

### Data

One additive migration:

- `practice_sets(id, title NULL, made_by 'person'|'received', created, archived)`
- `practice_set_refs(set_id, pos, book, chapter, verse_start NULL, verse_end NULL)`
- `practice_items(id, book, chapter, verse_start, verse_end, translation, rung, due_day,
  last_at, last_result, check_kind)`

The tables join the backup. Restore must leave them alone when the backup predates them:
`importTables` deletes every table it knows and inserts the backup's rows `[code]`, so without
that guard restoring any older backup would wipe every set and item. No practice log exists, so
there is nothing to build a streak from.

A 2 GB phone may end the app when the person leaves it (how often is not measured), so a
half-finished session is kept in Android's saved instance state, not in a table.

## 8. Subliminal AI

### What HQ does

HQ's embedder is a lookup table of about 29,500 token rows by 256 numbers (the row count is
inferred from the 30 MB file; it was not read from the model's files). A text's vector is the
average of its tokens' rows. No neural network runs. HQ downloads the table once, on first use.
HQ's pull request reports about 0.02 ms per query on a Galaxy A32; nothing here measured it
again.

Its main job in HQ is search by meaning, where it carries 60% of the ranking beside keyword
search. On HQ's own notes it found 50 of 64 reworded queries in the top five, keyword search 45,
and both together 52.

Two unprompted behaviours use it. The "next step" offer fires when the three nearest of 707
invented examples agree and the nearest scores at least 0.7; in its held-out test it was right
22 times of 23 and caught 22 of 120 useful cases, cautious by design. The second is silent
tagging: every 30 minutes HQ gives up to five untagged notes the tags that at least two of
their eight nearest notes share. HQ has recorded no evaluation of that one. The rest of what HQ
does unprompted (offer detectors, a weekly tip, a device-only digest, chips ordered untried
first) uses rules, counts and shared words.

It never writes: its outputs are a ranking, a choice among pre-written strings, or tags that
already exist. HQ's written tests are: works with nothing configured, costs nothing while idle,
visible and undoable, measurable, nothing leaves the device. No notification is ever used for
discovery.

### What that means for a study Bible

In HQ, subliminal means the model writes nothing and needs no setup. In a study Bible it cannot
also mean unseen: a hidden model choosing which Scripture a reader sees is what your rule
forbids. Three consequences.

- **No model states or implies a relation between passages, labelled or not.** A "related
  verses" list beside a verse reads as a claim about Scripture. Human cross references do that
  job, with their source named. A neighbour table computed at build time and frozen into the
  database would sit beside Scripture with no visible seam, so it is cut. HQ's silent tagging
  has no counterpart here for the same reason.
- **Every ordering on screen has a rule a person can say in one sentence.**
- **An averaged-token model cannot see word order.** Verses with the same words and opposite
  sense score alike. Its vectors also carry associations from the text it was trained on.

### What ships: HQ's discipline, exact joins, no model

Each of these is a join on an exact key. Each carries "Why this?", which states its rule, and
"Hide". One a day at most; the same kind once in three days; two "Not now" in a row mute that
kind for 30 days. Those are HQ's own constants. None is ever a notification.

| Line | Rule | Release |
|---|---|---|
| "<reference> is in today's reading. It is one of your Practice items." | A practice item's reference falls inside today's plan chapters. | C |
| "You wrote a note here on <date>." on a cross-reference row | A cross-reference target overlaps one of the person's notes. Shown only inside a list the person opened. | E |
| "<lemma> (<number>), a word you kept, is in verse <n>." | The same full Strong's key, letter included, is in the open chapter; the word is in 200 verses or fewer. | E |
| "No downloaded commentary covers <book>." then every pack that does, in year order, with its size | The person opened Commentary and no installed pack has an entry for the book. Lists all, picks none. | Later |

Pacing needs one small table of which line was shown and what the person answered. It is never
displayed. Nothing else in Berea acts unasked. A "feature never opened" line was designed after
HQ's untried-first chips; it is cut until a panel session shows a feature going unfound.

### The one use a model could have, and its pass mark

Ordering verses for a query the person typed, in a group below every word group, headed "Ordered
by computed similarity. Not a cross reference." It never attaches anything to a verse, never
picks a daily verse or a notification, never ranks sources.

The test: 200 questions written by at least five readers in Uganda, with their written consent,
half held out, with expected verses marked by the asker from a shuffled pool; and 50 questions
with nothing to find, on which the group must stay empty 95% of the time. The model must beat
the repaired word search by 10 points of recall at ten. On the phone it may add at most 150 ms
and 20 MB. As an optional pack it would be about 16 MB (computed from the model's stated
dimensions).

Before that, a cheaper check that needs no readers: run the embedder over the heading and
KJV-words question sets that already exist, on a machine that can fetch the model, and print its
number beside the lexical ones. That gives decision 5 a fact.

Preconditions if it goes ahead: the weights' licence has not been read at source, and must be
before any file made with them is published; no model found has published Luganda coverage; and
the model is never fetched at run time the way HQ does it. It would be a pinned optional pack.

## 9. Word study

### First, what is wrong on screen today

| Defect | Count | Fix |
|---|---|---|
| Greek missing. The reference pattern rejects STEPBible's bracketed verse numbers (`build_db.dart:282`). | 350 rows in 48 verses; no Greek at all for Romans 16:25-27, 2 Corinthians 13:13-14, Philippians 1:16-17 and John 7:53 `[measured]` | Parse both numbers; one `verse_map` table decides which a translation follows. |
| Five-digit Strong's numbers cut to four, which names a different word. | 3 tokens, in Acts 24:12, 2 Corinthians 11:28 and 1 Thessalonians 2:8 `[measured]` | `\d{4,5}` in the token pattern (`build_db.dart:283`). In the lexicon loaders admit a five-digit row only when its number occurs in the text, or decide on purpose to load all 1,485. Widen the four-digit patterns in `word_study.dart:13`, `citation_guard.dart` and `site/check/check.js` in the same change. |
| Hebrew rows lost to `INSERT OR IGNORE`. A word STEPBible reconstructs from the Greek can take the place of the Leningrad word, unmarked. | 75 rows in 15 verses `[measured]` | Plain insert; store the text type. |
| Opening a study by the bare number returns the alphabetically first entry under it (`bible_db.dart:844-850`). A normal press opens the token's own entry; this path is taken when the BSB tables and STEPBible's tagging disagree about a verse, from "Other words glossed", and from the press label. How often is not measured. | If every token were opened that way, the entry shown would not be its own for 41,110 Hebrew tokens (13.45%) and 2,588 Greek (1.82%). For 10,455 of the Hebrew ones it is a different word (H5892B "city" shows H5892A "excitement"); for the rest it is another STEPBible sense or namesake of the same word `[measured]`. | Opened by bare number, the screen lists every entry under that number and picks none. Where the tagging names an entry for this verse, that entry carries "STEPBible's tagging for this verse". |
| Words that are in some printed Greek editions and not others are loaded and counted without a mark. | 4,397 such rows are loaded today (4,450 once the skipped verses are restored); counts change for 681 of 5,417 Greek numbers `[measured]` | Store the edition list per word; every count names its text. |
| Aramaic verbs given Hebrew stem names; some verb forms not decoded; cohortatives called infinitives. | up to 965, 999 and 534 `[measured]` | Delete the Hebrew and Aramaic hand tables and load STEPBible's Hebrew morphology table (CC BY 4.0, read). The Greek table could not be fetched; keep the Greek hand maps until it is read. |
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
- The 1,982 Middle Liddell rows come from Perseus, which is share-alike. They leave the base
  database for their own share-alike file with its licence, credit and change note.
- Rows with no stated source show the gloss alone, and the screen says "STEPBible gives no
  source for this entry's definition; only its gloss is shown." Only 39 of the 1,873 are
  ordinary New Testament numbers with a definition of their own. Ten of the 39 share three or
  more seven-word runs with an entry in Mounce's dictionary, which is all rights reserved
  (`[measured]` against one copy of it; a lower bound). Report those ten to STEPBible.
- Name sentences are split from the definition and dropped: "STEPBible's summary sentence for
  this name is not shown."
- Parsing labels name the originator where STEPBible's own headers do: "ETCBC morphology,
  through STEPBible (CC BY-NC upstream)". No new feature is built on Hebrew parsing until ETCBC
  and STEPBible answer.
- Hebrew meanings: decision 9.
- `plainSenses`, "What it means" and "Its senses" leave the screen in the same merge that adds
  the replacement below, never before.

**The plain answer nobody at Berea wrote: "How the BSB translates it."** The BSB's own
translation tables give every English rendering of a Hebrew or Greek word with its count. That
is a publisher's data, countable, and readable by someone who has never opened a lexicon.

The order of the word screen is printed at its foot: "The word in its verse; then how the BSB
publisher's tables translate it (only the BSB publishes such tables); then dictionary entries,
earliest work first."

### Outside the BSB

A pressed word is exact in the BSB (99.8% by its own tables). In the KJV and WEB it is a guess by
meaning. The guess finds a word for 78.4% (KJV) and 83.6% (WEB) of study words in 2,000 random
verses. Whether the word found is the right one has not been measured in either translation. The
only accuracy figure comes from running the same guess on the BSB, where its picks match the BSB
tables 91.5% of the time (README). Today the guess opens as a study. Instead, a press in the KJV
or WEB opens "Words of <reference>" with nothing chosen. One more tap, and a guess never looks
like a fact. CrossWire's tagged KJV exists, but its terms are unclear; it stays a lead to read.

### Depth already downloaded and thrown away

All of this is in the files the build fetches today `[measured]`:

- the letter on 46% of Hebrew word tags and 7.9% of Greek tokens. About a third of the Hebrew
  ones (51,329 of 140,621) are letters A to F, a split the Open Scriptures project mapped to
  Brown-Driver-Briggs entries. The rest, and every Greek one, are STEPBible's own letters from G
  onward, its calls on which sense or which namesake a word has in a verse (H7307: G on 216
  tokens glossed "spirit", H on 145 glossed "breath");
- which of eight printed Greek editions contain each word;
- 1,323 Qere rows and their Ketiv readings;
- meaning and spelling variants;
- the main word inside a Hebrew token, with its prefixes and suffixes;
- the relation phrases that tie an Aramaic entry to its Hebrew one.

Each is shown under the name of whoever made the judgement, which is not always STEPBible. Its
own headers name ETCBC for Hebrew parsing, the Open Scriptures project for letters A to F, and
Scrivener 1894 and Robinson-Pierpont 2005 for two of the editions. Together these add about
1.6 MB by the designer's estimates; none was measured in a built database.

The full key, letter included, is stored and used to open a token's own entry, as a normal press
already does. Held from any new display until STEPBible says in writing how each is made:
per-token sub-meanings, counts and splits by the letters from G onward, and person
identifications.

### Pure counting

Parsing for every part of speech, fields only. Counts by form, which must sum to the total. By
book. First use. Used once. Words that stand in the same verses, with both numbers printed
("faith: 24 of its 227 verses") so a reader can check it, and never the word "related".

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

### Phases

Phase 1 is the defects table. Phase 2 is sources named, full definitions, "How the BSB
translates it" and the KJV and WEB press. Phase 3 is the dropped depth, the counting and the new
sources. Release E holds phases 1 and 2.

### Proof, replacing the model eval

The build gates above. A golden set that covers every defect case, a seeded sample of 200 BSB
words read by two people who know Greek and Hebrew, 300 tokens from numbers with several entries
(asserting the token's own entry opens), and 300 KJV and 300 WEB presses (asserting none opens
as exact). The existing 376-word set stays as a regression test until then; it is skipped in CI
today because CI has no Bible `[code]`.

## 10. Commentary per verse, and depth

### One view: "This verse"

Reached from the verse selection bar. Everything below the text is a folded line with a count,
loaded when opened. The order is printed at the foot: "The verse in each translation on this
phone; then what the BSB publisher prints with its text; then cross-reference lists; then named
writers, earliest first; then your notes."

1. **The verse in each installed translation.**
2. **Translators' footnotes.** "BSB translators' footnote". The publisher's own USFM holds 4,854
   footnotes in 4,314 verses `[measured]`. Berea strips the footnotes today
   (`importers.dart:57`) and drops the words-of-Jesus and supplied-word marks (`:61`). The
   publisher dedicates the BSB "Bible text" to the public domain; whether that covers footnotes,
   headings, parallel lines and markup is not confirmed, and is one of the questions in section
   14.
3. **The verses the BSB leaves empty.** Sixteen verse numbers have no text, Matthew 17:21 and
   Acts 8:37 among them `[measured]`. The publisher prints each in a footnote on a neighbouring
   verse. An empty verse gets a named state: "The BSB prints this verse in a footnote at 17:20",
   then the footnote and the KJV text. A reader coming from the KJV will find these sixteen
   numbers empty in the BSB.
4. **Parallel passages** as tappable chips, "Parallel passages printed by the BSB under this
   heading". The build already loads these lines with the headings and the reader prints them
   as plain italics (`build_db.dart:118-119`, `lib/reader_screen.dart:846-854`), so this starts
   from the stored `headings.refs`.
5. **Cross references, in full.** "Cross references · list published by OpenBible.info · 34
   listed · Bible order · the votes are that site's visitors', who are not named". Each row
   shows the reference, the whole verse on tap, and "87 votes by site visitors". Today cross
   references appear only inside Synthesize, four to a section, with no source `[code]`. Fix a
   defect on the way: a target range that crosses a chapter keeps only its first verse
   (`build_db.dart:392-396`).
6. **Words used 3 or more times in this passage**, shown when the selection is a range of
   verses, and on Synthesize, where it replaces the hidden weighted top six and its caption
   "worth knowing". For a single verse the row is absent, not empty.
7. **Commentary**, one folded row per work: author, work, years, licence, "1 comment on John
   15:1-8, 2,340 words". Each comment opens at the paragraph that names the verse (below).
8. **The person's own notes.**

Reconciling the two BSB files: the verse text comes from the pinned `bsb.txt`, the apparatus
from the USFM. Walk each verse word by word and require equal sequences; on a mismatch store
nothing for that verse and report it. On the files in the sandbox 31,101 of 31,102 verses agreed
`[measured]`, on a different USFM file from the one the build pins. Choose one source, pin it,
and measure again before writing the gate.

### Commentary per verse: what is known and what is not

Today a comment that covers a section appears whole on every verse in it, every tag is stripped
at build (including the digitiser's machine-readable reference targets), references inside
commentary cannot be tapped, and the search index inside each pack, 12 MB of the core pack's 42
MB, is never queried `[code]`.

Not known: how many verses would get a paragraph of their own. No pack could be built in the
sandbox. So the first step, before any release, is to build the eleven modules on a machine that
can reach the pinned files and print, per module: verses with their own entry, verses inside a
range, verses where a paragraph names the verse, and verses with none.

The second step is in Release E and needs no new pack and no second download: at display time,
find the paragraph that names the verse ("verse 5", "ver. 5", "v. 5") and open the comment there
with a margin bar, the whole comment still above and below. It is labelled as a position:
"Paragraph 4 of 11 names verse 5". References become tappable with the existing parser,
accepting lower recall.

A new pack format with reference tables, a "cited elsewhere" index and commentary search is 4 to
6 weeks `[estimate]` and serves only readers who download 4 to 25 MB of 18th and 19th century
English. It waits until panel readers are seen installing a pack. When it comes, reference tags
are labelled as the digitiser's markup, and every year and author used for ordering gets an
evidence line first.

### More sources, honestly

No new public domain commentary was verified. Every CrossWire module file was unreachable from
the sandbox, so Scofield, Geneva, the People's New Testament, Lightfoot and the rest are leads
with unread licences. One 199 KB file (`mods.d.tar.gz`) settles all of them, and Nave's and
Torrey's topical indexes for decision 4.

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
outlines beyond the publisher's headings, and speaker labels. Red letters are the publisher's
speaker marking and the one exception (decision 11).

Versification: the BSB and the KJV have the same verse count in all 1,189 chapters `[measured]`,
so KJV-keyed packs line up with the BSB. Add a build check that the WEB does too; none runs
today. One table, not two, maps a translation's numbering.

### Phases

Phase 1 is "This verse", all eight parts, from bundled data and installed packs. Phase 2 is the
new pack format and what depends on it. Release E holds phase 1.

## 11. Prayer under the rule

Scripture in the body, with Berea's choices around it: the ten passages listed as "Prayers of
the Bible", where which ten, the name "prayer" for each, and their titles are Berea's, with no
rule or chooser recorded. Purely the person's: their own list and recorded answers.

Authored: the first four rows of the table in section 2.

In Release C, with no content removed:

- the verse comes first, in Scripture type; the point sits under it, smaller, in interface type;
- each point and each plan-day title carries the label "Written for Berea with a language
  model. It is not Scripture and not a named source.";
- "Pray:" leaves the notification;
- nothing authored is drawn in Scripture type anywhere.

In Release F, with decisions 1, 3 and 4 answered:

- the topics become a list of references under the named editor, or give way to a named index;
- the points either leave the bundle or return as text a named person wrote. A signature on the
  existing lines does not make them a person's writing. If they return they are bundled, not
  downloaded: the whole file is 63 KB compressed;
- plan days become references only; the Today's prayer card and the prayer mark in the reader's
  margin go with the points;
- the Praise / Confess / Thank / Ask / Others frame goes;
- the list of ten either goes under the named editor or is retired, since Step through accepts
  any passage;
- a psalm plan over all 150 psalms, whole, is computed and moves to Plans. The stepper gains
  "Skip verse", so an omission is the person's;
- the fasting switch and its note go;
- CI and `tool/release.sh:28-29` stop requiring the prayer content that no longer ships.

## 12. What a first-time reader loses and gains

For someone on a 3 GB phone who has never used a concordance.

| Goes | When | What stands in its place |
|---|---|---|
| Asking a question in their own words | Release C | Search that finds a phrase cut from the text and any name. Not a replacement for a life question: see the last row. |
| A centre button that asks for a 0.58 to 2.6 GB download | Release C | A centre button that opens the Bible. |
| Verse of the day when no plan is running | Release C | Nothing, unless decision 10 goes another way. |
| Plain word senses ("What it means") | Release E, in the same merge as the replacement | "How the BSB translates it", with counts. |
| Study-page questions | Release F | One blank field. A price of the rule; no replacement. |
| The Pray now frame | Release F | The stepper with a field under each verse. A price of the rule for a new user. |
| Prayer-plan day titles and points, Today's prayer card, the prayer mark in the margin | Release F | Plan days as references only. |
| The fasting switch and its health note | Release F | Nothing, until a named health source exists. |
| Prayer points and the 24 topics | Release F, and only when decision 4's door exists | A named index or the named editor's topic list. |

Gained: a search box that finds a name (B); a verse learned on a schedule that survives a shared
or sold phone (C); the app installing on more phones (D); footnotes, parallels and the full
cross-reference list on every verse with nothing to download, and Greek in every verse (E).

## 13. Listening

A model wrote the Listen script and a neural voice read it; both go. What remains is Bob Souer's
recorded narration of the BSB with word timings. Only John is built (27.1 MB `[GitHub]`), and no
player exists in the app `[code]`. By word share the New Testament would be about 253 MB and the
whole Bible about 1.07 GB (computed).

A named person reading the text is Scripture read by a named source. A synthetic voice is
machine output even when its words are Scripture, costs about 172 MB, and is unmeasured on a 3 GB
phone. Cut it.

Whether narration leads the queue is an open question: it is English, it is large, and the claim
that it serves readers who struggle with English text is an inference. Test it by playing the
existing John pack to panel readers. If it goes ahead, fetch by chapter with the size on the
button, mark verses the narrator read in an earlier BSB wording, and say in Attributions that the
word timings were computed by forced alignment. Before building more packs, read the licence
statement at the publisher's audio page.

## 14. Order of work

Estimates are for one developer `[estimate]`, taken from line items priced by a reviewer who
read the code. Stages A, B, C and E come to roughly 22 to 30 weeks. D, the language release and
F are not sized. That is more than six months.

**Before any release (two to three weeks, alongside Stage A).**

- *First panel session.* Recruit 8 to 10 readers from one or two congregations. With today's
  0.8.0, write down for each reader's own phone: Android version, 32 or 64 bit, RAM, free
  storage, the translation their church uses, the language they read, and how apps reach the
  phone (a store, a file from a friend, WhatsApp). Then watch each reader find a verse, press a
  word and open Prayer. The phone list decides whether the lower floor and the 32-bit build are
  worth Release D.
- *Letters.* To Online Bible: decision 9. To STEPBible: whether CC BY covers the Hebrew meaning
  column; whether a derived database is "posting a copy", which every file header asks users not
  to do, and if so the lexicon pack is withdrawn or built on the device; where the untagged Greek
  rows come from; how the ETCBC, Perseus and MorphGNT terms sit with CC BY; which fields are
  machine-written. To ETCBC: consent for a free app. To BSB Publishing: whether the public domain
  dedication covers footnotes, headings, parallel-passage lines, the two marks and the
  translation tables. A 30-day clock on the first.
- *Reading.* `mods.d.tar.gz` (commentary leads, Nave, Torrey). The OpenBible licence page. The
  model card, only if decision 5 is not "never". Choose the KJV text on purpose and pin it:
  today it is an unpinned copy from a third-party repository (`build_db.dart:16-17, 50`).
- *Languages.* Find out whether a Luganda and a Swahili Bible can be offered, with the licence
  read at source.
- *Counting.* Build the database and run the test suite on a machine with the SDK. Build the
  eleven commentary modules and print the per-verse table of section 10. Run the embedder
  comparison of section 8.
- *A throwaway branch* that only drops the five model and voice packages and stubs what calls
  them. Build it for arm64 and for `android-arm`, read `--analyze-size` for both, and start the
  arm build on a 32-bit phone. That settles three unknowns: the APK size, whether the 32-bit
  build compiles, and whether it starts.
- *Phones.* Buy one 3 to 4 GB Tecno or Infinix and one 2 GB 32-bit Go-edition phone.
- *The thirteen decisions,* and the name of the editor.

**Stage A. Ground (1 to 2 weeks; merged, not published).** Pin the 11 unpinned build inputs.
Give CI a Bible database, starting with a BSB-only one built from the committed
`site/data/bible` JSON. It holds verse text only, so it un-skips the search, reference and
reader tests that need no words; first split the one skip guard
(`test/support/bible.dart:35`) into a text guard and a full-database guard, so the word tests
stay skipped until CI builds the full database from pinned inputs. Copy the database in chunks
at first run. Cache the open chapter and build the other places when first opened: the reader
re-reads SQLite on every app change today (a TECHDEBT row). Build the Strong's Hebrew fallback
behind a build setting.

**Release B. Search that finds (about 2 weeks).** Section 6. *A reader can type "Jesus", or
words copied from a verse, and reach it.* Panel session with its task script.

**Release C. The Bible in the centre (8 to 10 weeks, in two parts).**

- C1 (5 to 6 weeks): the removal, the shell, the provenance column and labels, the archive, the
  reworded Synthesize captions, the verse-of-the-day change, Prayer's presentation change, and
  a Practice place holding Step through and the person's sets.
- C2 (2 to 3 weeks, a guess): Hide words, Recall on the ladder, Due, "Your words under each
  verse", and the one line "<reference> is in today's reading."

*A reader gets a centre button that opens the Bible and can learn a verse on a schedule.* Panel
session.

**Release D. On real phones (not sized until the 32-bit build has been tried).** D1: lower the
Android floor as far as a real phone proves; resumable and verifiable packs; Share Berea; the
feedback message; the route chosen in decision 13. D2: the 32-bit build, only if the panel's
phones show a need. *A reader on an older phone can install it, and so can their friend.*

**Release L. A Bible in Luganda or Swahili,** only if the first step finds one that can be
offered. Book names in the reference parser; search on the text.

**Release E. This verse, and words that are right (9 to 12 weeks, in several merges).**

- E1 (3 to 4 weeks): section 10 phase 1, with the sources table and the line "You wrote a note
  here".
- E2 (6 to 8 weeks): section 9 phases 1 and 2, with plain senses leaving in the same merge that
  adds "How the BSB translates it"; the generated name sentences dropped; the kept-word line.

*A reader can press any verse and see what its publisher printed with it, and gets Greek in
every verse and a named source under every definition.*

**Release F. A door for life questions (1 to 2 weeks for the prayer changes; the index or the
editor's lists are not sized).** A named index or the named editor's topic list; the editor's
list of practices; everything in section 11's second list.

**Later, on panel evidence only.** First letters after the keyboard test; Write out; Questions
here; Word for word elsewhere; whole books at a sitting; the publisher's lines as layout; sets
shared as references; Check a text, after 50 real forwarded messages; hear and repeat, and
narration; section 9 phase 3; section 10 phase 2; the book outline and Old Testament in the New;
the line "No downloaded commentary covers <book>."

**Cut.** The embedding model and its test programme, if decision 5 is "never"; the neural voice;
the imperatives list; marking translation differences (measured, BSB against KJV: about a third
of the words in a typical verse); underlining where a commentator's quotation differs from the
KJV; a versification interpreter before a real Luganda file is measured; MACULA on screen; the
"feature never opened" line; the reviewed string ledger; three reminder slots and a widget,
until one daily notification is shown to arrive on a Tecno, an Infinix and an itel over seven
days; QR.

### Gates that replace the model eval

`tool/release.sh` loses lines 16-20 and 44-48, which need a model, and the eval file named on
line 67. Each gate is turned on in the stage that introduces what it tests.

| Gate | Runs | From |
|---|---|---|
| Every build input pinned by hash | CI | A |
| Search, reference and reader tests against a BSB-only database | CI | A |
| `search_check`: phrase set and vocabulary set | CI | B |
| Search time per group | The 3 to 4 GB phone, by hand | B |
| No generative package in `pubspec.lock`; no `RECORD_AUDIO`; no name of a model runtime in `lib/` or the harness | CI | C |
| Deny-list lint, with a dated allow list for the strings Release E removes | CI | C |
| `scriptureStyle` used only by the Scripture widget; no part-verse shown alone (Psalm 14:1 and 53:1 are test cases) | CI | C |
| A version 3 backup restores and leaves practice tables alone | CI | C |
| APK 60 MB or less per ABI; first run with 150 MB free; the same timings on the 2 GB phone | Release, by hand | D |
| Rows read equal rows stored plus named exclusions; every BSB verse has words; no number shortened | Release build | E |
| Every source text row has a source; shown text equals source text with whitespace removed | Release build | E |
| Each of the 16 empty verses shows its footnote or another translation | CI | E |
| Word golden set, against the full database | CI | E |

## 15. Not known, and not checked

- Nothing was built or run. Every statement about a screen is read from code.
- The APK size without the model; any behaviour below Android 11; whether the 32-bit build
  compiles.
- Every timing on a phone with less than 5.5 GB of RAM, and how often such a phone ends the app
  in the background.
- The search percentages in Dart against the real index, and search for phrases as readers
  remember them.
- How often word study opens by the bare number.
- Which tags each commentary module carries, and how many verses get a paragraph of their own.
- Every CrossWire licence. Every model's weight licence. The OpenBible licence at source. The
  licence statement for the narration. Whether the BSB's public domain dedication names its
  footnotes, headings, markup and translation tables, or only "Bible text". STEPBible's Greek
  morphology table, which could not be fetched.
- The licence of the KJV text Berea ships.
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
the codebase, an entry-level phone in Uganda, licences, product value, and completeness. They
reported 133 issues. A first draft of this document was then checked by five reviewers against
the code, the raw data, the rule, the critics' findings and the owner's point of view; they
reported 94 problems, and this version applies them.

Three of the critics' points are set aside here, with the reason:

- *Drop the Hebrew meanings in the first chat-free build whatever Online Bible answers.* This
  plan builds the fallback first and swaps on day 30 without a grant, because the swap is a
  visible loss to readers and the text has been published for a month already. No release prints
  "Permission requested".
- *A reviewed ledger of every interface string.* Replaced by a named person reading each changed
  string, plus a lint. A ledger for one maintainer proves bookkeeping.
- *Lead the first Practice release with Check a text.* It waits for 50 real forwarded messages,
  because its report misleads when a message quotes a translation Berea does not carry.

Every Scripture reference in this document was looked up in the BSB text committed under
`site/data/bible` before it was written down.
