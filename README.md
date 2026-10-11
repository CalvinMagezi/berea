# Berea

Offline Bible study agent. Runs fully on device with Google AI Edge models (LiteRT-LM) on Android,
iOS and macOS, or against Ollama on a Mac. Named for Acts 17:11.

The model never recalls Scripture from memory. The harness retrieves verbatim text from a local
database, the model reasons over it, and a validator strips anything the model invents. Grounding
strength is therefore independent of model strength.

## What it does

- **Study**: ask about a passage, a word or a question of life. Answers are grounded in retrieved
  Scripture and every citation is checked. Every study is saved locally and can be reopened.
- **Bible**: an offline reader with BSB and KJV built in. Select verses to ask Berea about them,
  add a note or highlight them. Import a translation you own as a CSV; it stays on the device.
- **Notes**: your saved studies, notes and highlights. One local SQLite file, no account, no sync,
  nothing leaves the device.

## Locked build

| Layer | Choice | Why |
|-------|--------|-----|
| App | Flutter 3.47, Dart 3.13 | One codebase for Android, iOS, macOS |
| On-device runtime | `flutter_edge_ai` + `flutter_edge_ai_litertlm` (LiteRT-LM) | Same `.litertlm` files AI Edge Gallery uses. `flutter_gemma` is discontinued in favour of this package |
| Desktop dev runtime | Ollama HTTP, `gemma4:e2b` | Same model family as on device, tool calling, Apache 2.0 |
| Storage | SQLite + FTS5 (`sqlite3` package) | BM25 retrieval, zero native deps beyond SQLite |
| Harness | Pure Dart package `packages/harness` | Testable on Mac without a phone |
| License | MIT | |

Models are downloaded on first run from the Hugging Face LiteRT community, never bundled. The AI
Edge Gallery app keeps its models in its own sandbox, so this app downloads the same files itself.
The catalog lives in `lib/models.dart`. Gemma 4 E2B and E4B are not gated; Gemma 3 1B needs a
Hugging Face token after accepting the licence, entered in the engine settings.

## Platform notes

- Android: `minSdk 30`, arm64 only (LiteRT-LM requirement). The emulator runs models on CPU.
- macOS: the Podfile `post_install` stages LiteRT-LM companion dylibs into the app. Without it the
  build is green but the first on-device model load fails. Ollama is the default engine on macOS.
- iOS: deployment target 15.0, CocoaPods only (Swift Package Manager is turned off in
  `pubspec.yaml`), and the extended-virtual-addressing and increased-memory-limit entitlements so
  a 2.6 GB model fits on a real iPhone. The simulator runs models on CPU only. SPM debug builds
  embed an absolute host rpath, and when the checkout lives in a privacy-protected folder such as
  `~/Documents` the simulator's dyld hangs on it before `main` runs.
- Debug builds read `BEREA_AUTORUN` or `autorun.txt` in the app's documents folder and run that
  question on launch, so a headless simulator or emulator can exercise the on-device path.

## Model tiers

| Tier | Model | Prompt budget | Retrieval k | Tool round |
|------|-------|---------------|-------------|------------|
| low | Gemma 3 1B | 2k tokens | 3 | no |
| mid | Gemma 4 E2B (~2.6 GB) | 4k | 6 | no |
| high | Gemma 4 E4B, Ollama gemma4:e2b | 8k | 10 | one, max two |

Tier is picked from device RAM and model id. The system prompt is static and comes first so the
LiteRT-LM prefix cache hits; retrieved chunks come after.

## Pipeline per turn

1. RefParser: regex references in the user text ("John 3:16", "Jn 3.16-18", "1 Cor 13"). Fetch
   passages verbatim from SQLite.
2. Retriever: FTS5 over bible, lexicon, cross references and corpus. Top k by tier.
3. PromptBuilder: static system prompt, then PASSAGES, LEXICON, WORDS, CROSS REFERENCES and
   RELATED VERSES blocks trimmed to the tier budget, last two turns, question.
4. LlmEngine streams the answer. High tier may run one tool round first
   (`lookup_passage`, `search_bible`, `search_lexicon`).
5. CitationGuard: every reference in the output is looked up. Unknown reference: stripped and
   logged. Quoted text that differs from the database: replaced with the database text. A
   "Scripture cited" footer lists the verified passages.

## Data (all redistributable)

| Dataset | License | Role |
|---------|---------|------|
| Berean Standard Bible (BSB) | Public domain (CC0) | Default translation, via scrollmapper/bible_databases |
| King James Version | Public domain | Second translation (matches the gem) |
| STEPBible TAHOT / TAGNT | CC BY 4.0 | Every Hebrew OT and Greek NT word with transliteration, gloss, Strong's and morphology |
| STEPBible TBESH / TBESG | CC BY 4.0 | Hebrew and Greek lexicon keyed by Strong's |
| OpenBible.info cross references | CC BY | Cross reference block, ranked by votes |

`dart run bin/build_db.dart` in `packages/harness` downloads these and writes `assets/berea.sqlite`
(about 60 MB). The file is gitignored; CI or a release step builds it.

The gem also used the NLT, which is Tyndale copyright and is excluded, as is the NIV (Biblica).
Both can be imported from a `Book,Chapter,Verse,Text` CSV you own through the engine settings;
the file is stored under the app's support folder and re-imported after a database rebuild. It is
never committed and never uploaded.

User data lives in `study.sqlite` next to the Bible database: notes on verse ranges, highlights,
and every conversation with Berea.

## Repository layout

```
lib/ android/ ios/ macos/   Flutter app (repo root)
lib/home_shell.dart         Study, Bible and Notes tabs
lib/reader_screen.dart      Offline reader with selection, notes and highlights
lib/study_store.dart        Local SQLite for notes, highlights and saved studies
packages/harness/    Pure Dart: RefParser, Retriever, PromptBuilder, CitationGuard, LlmEngine
packages/harness/bin/build_db.dart   Downloads datasets, builds assets/berea.sqlite
packages/harness/bin/berea.dart      CLI chat against Ollama
packages/harness/bin/eval.dart       Golden eval, exits 1 on any invented reference
packages/harness/eval/golden.json    Questions with expected references
prompts/system.md    System prompt
prompts/gem-original.md   Captured gem for reference
```

## Phases

1. Mac CLI harness against Ollama. DB build, RefParser, CitationGuard, eval. No UI.
2. Flutter macOS shell on the same harness. Chat and passage pane.
3. Android with `flutter_gemma` and Gemma 4 E2B. Download manager, tier logic.
4. iOS, same plugin, Metal GPU. Tune budgets on a real phone.
5. Only if BM25 misses in eval: EmbeddingGemma 300M via LiteRT for semantic corpus search.

## Eval gate

```bash
cd packages/harness && dart run bin/eval.dart --tier mid --model gemma4:e2b
```

Reports invented references, expected reference coverage and unverified quotes. Invented
references must be zero for a release.
