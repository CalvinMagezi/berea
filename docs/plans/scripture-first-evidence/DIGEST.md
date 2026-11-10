# Berea, Scripture first: digest of what was found (2026-11-10)

Read this first. Detail and file:line evidence are in the sibling files named at the end.
Paths are under /home/user/berea unless they start with /home/user/hq.

## The owner's ask, in their words

"brainstorm and plan out how to remove the chat ai, make the center berea icon the Bible now and
add a new page called 'Practice' and lets now think safely outside the box how to create practices
solely based off scripture and then reduce the AI in our app to be subliminal AI like hqs inbuilt
embedding model and how its being used for proactive capabilities. And how to go deeper into the
accuracy of our word studies, commentaries per verse and depth of studying. Lets really think
granular without expressing any personal opinions or ideas with scripture being the source of truth
objectively."

The owner also asks, as a standing preference, that every build be judged as a product manager
would: what problem is solved, and at what scale of value, with a focus on people at the bottom of
the pyramid in places like Uganda. Push back where a proposal does not serve that.

## Working draft of the source rule (designers may tighten it, not loosen it)

Everything Berea shows is one of:
 (a) Scripture, word for word, with its reference and translation;
 (b) a mechanical fact about the text: a count, a parsing, the same lemma, the same words, a
     position, something a script can recompute from the data;
 (c) a named human source shown as that source's words: a lexicon, a commentary, a translators'
     footnote, a cross-reference list, with author, work and licence;
 (d) the person's own words (notes, prayers, answers).
Machine output is a fifth thing and is never (a) to (d). The draft position is: a model may ORDER
or SELECT among items that are already (a) to (d), or choose which existing feature to offer, and
it never writes a sentence. Wherever a model's ordering is shown as a relation between passages it
carries a plain label saying it is computed. Open question for designers: is even that too much,
and where exactly may it act.

## Facts that shape the plan

Shell and chat
- Five places from one enum: Bible, Plans, Study, Prayer, Notes (lib/home_shell.dart:24). Study is
  centre only because it is index 2; the raised slot is `t == HomeTab.study` (:264). The app
  already opens on Bible (:59). Bar and sidebar loop the same enum; shortcuts are Cmd or Ctrl 1 to 5
  by index (:133-146); a sixth place overflows `digits` and gives 60 px slots on a 360 px phone.
- The Study place holds only the chat, helper setup and download, and Past questions. The verse of
  the day and today's reading already live on the Bible reader (TodayCard, lib/reader_screen.dart:546).
- The brand guide ties the lamp mark to no feature; only code comments tie it to the helper.
- Entry points into the model: Study chat, suggestion chips, Go deeper, selection bar "Ask", word
  study "Ask Berea about <lemma>", study page "Draft with Berea", "Ask about this notebook" and its
  panel, Listen (the model writes a script, a neural voice reads it), voice dictation (Gemma
  transcribes). Past questions replays saved turns.
- Model-free already: Synthesize (study packet), Study notebook, notebooks as reading and notes,
  word study minus Ask, Words (interlinear), Commentary, study page as a hand-written worksheet,
  search, plans, highlights, notes, backup, export.
- Stored model text: `messages` (assistant rows), `notebook_messages`, `study_pages` (model draft
  and the person's edits share columns, no provenance), `notes` (a kept answer is an ordinary
  note), listen script and WAV on disk. Restore rejects unknown tables and columns, so old backups
  must keep loading.
- Last 15 merged changes: 8 about the model's wording, citations or prompt context, 5 about
  Scripture data, reading or study depth, 2 mixed. Of the 11 dated 4 November: 8 model.
- 34 TECHDEBT rows close when the model goes.

Reach
- Model sizes 0.58, 2.6 and 3.66 GB; one phone measured (Galaxy A32, 5.5 GB RAM): 49 to 125 s to
  first words, 2.7 to 3.8 GB held. Models need 5 GB RAM and up (lib/models.dart:134).
- Android minSdk 30 and arm64 only exist "because LiteRT-LM needs API 30 and ships arm64 only"
  (android/app/build.gradle.kts:35-36, 53-57). iOS memory entitlements, microphone permission,
  macOS dylib staging and the RAM channel are also model-caused.
- The Bible database is about 81 MB (29 MB compressed); first verse on screen in 1.5 s on the A32.
- Uganda (search summaries, treat as indicative): about 20.5M smartphones (UCC Q2 2026); Samsung,
  Tecno, Infinix, Itel lead; new entry phones ship with 3 to 4 GB RAM; up to about a fifth of
  Android web use is below API 30. No verified share of 32-bit devices. Data prices unverified.
- Without the model nothing must be downloaded at first run. Optional packs today: lexicon 9 MB,
  commentary 4 to 25 MB each, voice 145 MB.

The rule against authored text is already broken in places
- Prayer: about 1,970 authored prayer lines "written for Berea" (24 topics, 441 chapters, 366 daily
  lines, 6 plans), topic titles, plan and day titles, the Praise/Confess/Thank/Ask/Others frame,
  hand-picked verse lists, a trimmed psalm plan, the fasting note, "Pray: <line>" in notifications,
  the reader's margin mark. TECHDEBT records that the check "cannot judge that a line says no more
  than its verse". The purely Scriptural parts: the ten Bible prayers stepped a verse at a time
  (titles are authored), "pray this verse" with no points, the person's own list and answers.
- Word study: `plainSenses` rewrites lexicon definitions by regex and shows them as "What it means"
  with no source named; Abbott-Smith and BDB are named nowhere in lib/; definitions are cut at 600
  characters, which also cuts the trailing source tag. Fixed UI sentences explain things.
- Study pages ask "What does it mean?" and "How should I live?" as labels over the person's own
  fields.
- Data shipped upstream contains machine prose: STEPBible says TIPNR person descriptions and its
  planned concept descriptions were written by Claude 3. Aquifer's Swahili has no stated method.
- Licence flags on data already shipped (STEP headers): TBESH meanings come from Online Bible's
  abridged BDB ("Permission should be gained from Online Bible"); TBESG mixes Abbott-Smith (PD),
  Middle Liddell from Perseus (CC BY-SA) and 3,011 untagged rows; TAHOT morphology is "from ETCBC"
  (BHSA is CC BY-NC); every header says "Please do not post copies of this data file elsewhere".

Word study, measured on the raw STEPBible files
- Kept today: reference, original, transliteration, context gloss, Strong's, morphology code; a
  lexicon of 21,232 rows. Dropped at build: edition markers and per-word edition lists in TAGNT,
  meaning and spelling variants, context sub-meaning per token (111,031 Hebrew tokens; every Greek
  row), person and place ids (39,762 Hebrew, 5,446 Greek), Qere and Ketiv (1,323 Qere rows), root
  markers, alternative numbers, the relation phrases and uStrong column of the lexicons, definition
  text past 600 characters (1,548 entries), 1,485 LXX-only Greek lexicon rows.
- Parse defects: 350 Greek rows in 48 verses fail the reference pattern, so John 7:53, Romans
  16:25-27, 2 Corinthians 13:13-14, Philippians 1:16-17 and 3 John 15 have no Greek; 58 to 75 Hebrew
  rows lose to INSERT OR IGNORE; three five-digit Strong's numbers are truncated to wrong words;
  4,450 Greek rows with no Nestle-Aland reading load unmarked beside the main text; Psalm titles are
  verse 0 in TAHOT and inside verse 1 in the BSB.
- Senses: 46% of Hebrew root tags and 7.9% of Greek tokens carry a sense or namesake letter that
  the study merges. Looking a word up by base number returns the alphabetically first entry: wrong
  entry for 41,110 Hebrew tokens (13.45%) and 2,588 Greek (1.82%) when reached that way (H5892B
  "city" shows H5892A "excitement"). Examples of merged senses: H7307 spirit 216, breath 145;
  H5315 soul 246, life 207, myself 130, person 96; G2264 three different Herods.
- Pressed word: exact in the BSB (99.8% by its own tables); outside it a guess by meaning, 78 to
  84% found, 91.5% agreeing with the BSB tables. Golden set: 376 words, one reviewer, BSB only,
  skipped in CI.
- Morphology shown for verbs only; 999 Hebrew verbs undecoded; Aramaic verbs get Hebrew stem names.
- Not there: Septuagint bridge, word families, collocations, per-translation rendering counts,
  variants, Qere/Ketiv, full Hebrew lexicon.

Commentary and verse depth
- Packs are SQLite, plain text, keyed to KJV verses; a section comment shows whole on every verse
  it covers. All tags are stripped at build, including the source's own machine-readable
  `<scripRef passage="...">` targets. References inside commentary are not tappable. The FTS index
  in each pack is never queried. No versification map; WEB numbering is unchecked.
- Cross references (OpenBible, 345k, with votes) appear only inside Synthesize, four per section,
  with no source or vote count. A selected verse has no cross-reference list. TSK is plain text.
- Translators' footnotes are not read at all. The BSB publisher's own USFM (BSB-publishing/bsb2usfm
  on GitHub, public domain, 1.6 MB, measured) has 4,854 footnotes, 2,302 words-of-Jesus spans,
  1,324 parallel-passage lines and 19,771 supplied-word spans. Berea strips all of these.
- No new public domain commentary was verified: every CrossWire conf was unreachable from the
  sandbox. Robertson's Word Pictures: 1930 volumes are US public domain since 1 January 2026;
  later volumes are not yet; no clean text source. Gill: no clean source.

Text probe (BSB and STEPBible, measured)
- 2,527 BSB verses contain a question mark (OT 1,706, NT 821); 1,129 verses are questions only.
- Greek imperatives: 1,646 tokens, 1,045 verses with a second-person imperative, 446 lemmas. Top:
  become 45, do 43, go 38, give 35, say 34, hear 32, fear 29, see 27, greet 27 ... pray 17,
  rejoice 17, write 15. Prohibitions are often not imperatives (103 aorist subjunctives with μή).
- Hebrew imperatives: 4,305 tokens in 2,684 verses, 607 lemmas; Psalms has 699. Top: hear 191,
  go 161, take 104, arise 91, say 88, see 85, speak 82, return 76 ... praise 52, remember 51,
  bless 30. The Ten Commandments are second-person imperfects with a negative, not imperatives.
- BSB verse length: median 22 words; 19,613 verses are 25 words or fewer.
- Refrains: "His loving devotion endures forever" in 41 verses; 385 whole verses repeat.
- No speaker or quotation marking exists in the STEP files. Speaker datasets (Clear, Glyssen) are
  editors' attributions and need a word alignment Berea lacks; the BSB's own words-of-Jesus markup
  is the publisher's.

HQ's embedder and how it is used
- Model2Vec potion-base-8M: a table of 29,528 token rows by 256 numbers; a text's vector is the
  mean of its tokens' rows, normalised. About 30 MB on disk, 36 MB in memory, 0.02 ms per query on
  a Galaxy A32. No neural network runs. It ignores word order. HQ downloads it on first use.
- It never writes: its outputs are a ranking, a choice among pre-written strings, or existing tags.
- Next step offers: compare the task with 707 invented, labelled examples (238 labelled "nothing");
  offer only when the 3 nearest agree and the nearest is at least 0.7; one line under a reply;
  Yes only fills the composer; once a day at most; two "not now" mutes it for 30 days. Held-out
  test: 23 shown, 22 right; silent on 53 of 53; 22 of 120 useful cases caught, "deliberately
  cautious".
- Other proactive parts use no embedder: rule detectors, a weekly collection tip by shared words,
  a device-only adoption digest, chips ordered untried first.
- HQ's written tests: works with nothing configured, costs nothing while idle, visible and
  undoable, measurable, nothing leaves the device. No notifications for discovery.
- For Berea: the verse corpus is fixed, so verse vectors or neighbour lists can be made at build
  time and the phone does lookups only. Only the person's notes and queries need an encoder on the
  phone: a WordPiece tokenizer, the matrix (30 MB float32, 7.6 MB int8), a mean. Pure Dart is
  possible (tokenizer packages exist; no pure Dart Model2Vec package). Model weight licences were
  not read at source. No model here has published Luganda coverage; Swahili only in large ones.
- Berea's own topical retrieval baseline has no model: FTS5 with stemming, word forms tied by
  shared glosses, and cross-reference hubs: 7 or 8 of 8 hard questions. TECHDEBT judged a 110 MB
  embedder not worth it. All-stopword questions ("Who is Jesus?") return nothing.

Citation check with no model
- CitationGuard runs on any string: reference exists, unknown book, quote is word for word, quote
  corrected to the verse's words, Strong's number exists, wrong-language note, near miss. The site
  already runs a JavaScript copy on pasted text. Gaps for pasted text: no lookup from an uncited
  quote to its verse, one translation per check, quotes under 30 characters skipped.
- Android: the app is not a share target today; ACTION_SEND and ACTION_PROCESS_TEXT would let a
  forwarded message or selected text be sent to Berea.

Practice mechanics (research)
- Every drill in verse-memory apps is a transformation of the verse's own words: hide words
  step by step, first letters, choose the next word, type and compare, recite. None needs authored
  content. Remember Me (MIT, Flutter) is open source. FSRS has an MIT Dart package; fixed defaults
  work. Evidence is strong for recall practice and spacing, moderate for reading aloud, weak for
  first letters and copying.
- A set of passages can travel as references only (QR or file), so no free text rides along.
- Reminders are already inexact, boot-restored and off by default.
- The skeptic's warning: any hand-picked list of "practices" and their verses is an editorial
  selection. A list regenerated from a word or lemma in the text is mechanical.

## Reference lookup

`python3 /tmp/claude-0/-home-user/238c2100-29fb-54dd-a418-155245010f46/scratchpad/tools/refcheck.py "Joshua 1:8" "Psalm 1:2"`
prints each reference from the BSB text committed in the repo, or NOT FOUND. Use it for every
reference you write. Never quote a verse from memory.

## Files in this folder

shell.md, ai_engine.md, ai_features.md, harness.md, word_study.md, commentary.md,
prayer_precedent.md, conventions.md (Berea readers); hq_embedder.md (HQ); data_probe.md (counts);
r_lexical.merged.txt, r_commentary.merged.txt, r_embeddings.merged.txt, r_practice.merged.txt
(research with the skeptic's verdict beside each item: read the VERDICT and CORRECTION lines, and
the VERIFY SUMMARY at the end, before relying on any dataset or licence).
