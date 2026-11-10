# Handover: Berea, Scripture first

Written 2026-11-10 by the cloud session that made the plan, for the session that picks it up on
the owner's laptop. PR: https://github.com/CalvinMagezi/berea/pull/46. Branch
`ccr-c94dd07f-qjyfu8`. The plan is `docs/plans/scripture-first.md`; read it first.

## State

- The branch holds documents only: the plan, this note, and a small evidence folder
  (`docs/plans/scripture-first-evidence/`). No app code has changed.
- Nothing was compiled or run. The cloud sandbox had no Dart or Flutter, no built
  `assets/berea.sqlite`, and could not reach ebible.org, bereanbible.com, huggingface.co or
  crosswire.org. Every statement about what a screen shows is read from code.
- The rest of the research (nine code readers, four dataset researchers with skeptics, six
  designs, six critiques, five plan reviews) lived in the cloud sandbox's scratch folder and is
  gone. What survives is the plan itself plus the evidence folder: `DIGEST.md` (the verified facts
  the plan was written from), `data_probe.md` (counts over the BSB and STEPBible files) and
  `refcheck.py`.
- `refcheck.py "Book C:V"` prints a verse from the BSB text in `site/data/bible`, or NOT FOUND.
  Use it for every reference you write. Never quote a verse from memory.

## What the owner has not yet answered

The plan's section 3 has thirteen decisions. Do not start Release C (the removal) until the
owner has answered at least decisions 1, 2 and 3: whether the rule reaches the existing prayer
points, topics and Pray now frame; what "Practice" means; who may be a named editor. Ask them.

Releases A and B need no decision and are safe to start.

## Where to start (Stage A, then Release B)

1. **Run what the sandbox could not.** `cd packages/harness && dart pub get && dart run
   bin/build_db.dart`, then `flutter pub get`, `dart test`, `flutter test`. Record which tests
   skip and why (`test/support/bible.dart:35`, `needsBuiltBible`). Note the real size of
   `assets/berea.sqlite` (the README says 81 MB, the app says 85, a comment says 67).
2. **Pin the 11 unpinned build inputs** in `packages/harness/bin/build_db.dart` (STEPBible,
   KJV, WEB, OpenBible, the BSB USFM, all fetched from moving branches). The KJV is an unpinned
   copy from a third-party repository; choose the text on purpose.
3. **Split the test skip guard** into a text guard and a full-database guard, and add a CI job
   that builds a BSB-only database from the committed `site/data/bible` JSON. It will un-skip
   search, reference and reader tests. Word tests need the full database and stay skipped.
4. **Copy the Bible database in chunks** to a `.part` file and rename (`lib/app_state.dart:
   656-658` reads all of it into memory today).
5. **Release B, search.** In `bible_db.dart` (stoplist at lines 402-412) take "god", "lord",
   "jesus", "christ" and "help" out; shrink the list to about 40 function words; return labelled
   result groups in Bible order (section 6 of the plan); confirm phrase hits against the
   verse text because the index stores stems; make the word pattern Unicode-aware
   (`bible_db.dart:313`). Add `bin/search_check.dart` and re-measure the Python percentages in
   the plan in Dart before setting any gate; they were computed without the app's word-form
   expansion.

## Things the plan could not settle and you may find

- `lib/prayer_pray_now.dart:532` (`LordsPrayerScreen`) is the stepper Practice would generalise.
- The plan's APK size figures after removal are guesses. Build a throwaway branch that drops the
  five model and voice packages, build arm64 and `android-arm`, and read `--analyze-size`.
- STEPBible's Greek morphology table (TEGMC) could not be fetched; the Hebrew one was read.
- Licence letters (Online Bible, STEPBible, ETCBC, BSB Publishing) are the owner's to send;
  drafts of what to ask are in plan section 14.

## Working agreements

- The owner's rule: Berea shows only Scripture, a counted fact, a named source, the person's own
  words, or interface wording that never says what a verse means. No theological opinions, no
  interpretation, in code, copy or docs.
- A named person (the owner) reads each new or changed interface string. A model may not be that
  reader.
- The owner wants product-manager pushback: say what problem a change solves, for whom, and at
  what scale, with entry-level Android phones in Uganda in mind.
- Writing style (HQ's rules apply to Berea docs too): plain sentences, no em dashes, none of
  "delve", "leverage", "robust", "seamless", "cutting-edge".
- Do not open a pull request for code until asked; this branch's PR (#46) is the plan.
- Branch for work: continue on `ccr-c94dd07f-qjyfu8` unless the owner names another.
