| Item | Reason skipped | Date | File:line |
|------|----------------|------|-----------|
| High tier tool round (`lookup_passage`, `search_bible`, `search_lexicon`) before generation | Retrieval-first pipeline covers phase 1; add once eval shows topic questions missing passages on gemma4 | 2026-10-11 | packages/harness/lib/src/harness.dart:38 |
| Quote mismatch replaces text with DB text | Phase 1 only flags `[unverified quote]`; replacement needs fuzzy alignment | 2026-10-11 | packages/harness/lib/src/citation_guard.dart:45 |
| Tier chosen from the model, not from device RAM | No RAM API in the chosen plugins; model picker implies tier. Add a RAM probe if users pick models their phone cannot hold | 2026-10-11 | lib/settings_sheet.dart:75 |
| No non-gated low-tier model in the catalog | litert-community Qwen3 0.6B bundles fail in LiteRT-LM 0.18 (old file: SentencePiece "piece must not include null character"; new file: "Failed to apply template"). Gemma 3 1B works but is gated. Revisit when the community re-exports Qwen3 | 2026-10-11 | lib/models.dart:30 |
| Reader has no in-Bible search UI | FTS5 index exists; a search field on the Bible tab is a small addition when asked | 2026-10-11 | lib/reader_screen.dart:1 |

| One LiteRT-LM conversation per turn (system prompt re-prefilled every turn) | Measured on the emulator (CPU, 8 GB): holding the conversation needs a 9.4k context; turn 2 prefill fell 21.3 s to 17.7 s but turn 1 rose 26.4 s to 32.0 s and Android killed background apps. Net slower. Re-measure on a real GPU phone before revisiting | 2026-10-11 | lib/edge_engine.dart:30 |
