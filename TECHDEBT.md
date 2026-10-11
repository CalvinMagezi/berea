| Item | Reason skipped | Date | File:line |
|------|----------------|------|-----------|
| High tier tool round (`lookup_passage`, `search_bible`, `search_lexicon`) before generation | Retrieval-first pipeline covers phase 1; add once eval shows topic questions missing passages on gemma4 | 2026-10-11 | packages/harness/lib/src/harness.dart:38 |
| Quote mismatch replaces text with DB text | Phase 1 only flags `[unverified quote]`; replacement needs fuzzy alignment | 2026-10-11 | packages/harness/lib/src/citation_guard.dart:45 |
| World English Bible as default translation | Not in scrollmapper CSV set; needs USFM parser for ebible.org zip. BSB used instead | 2026-10-11 | packages/harness/bin/build_db.dart:15 |
