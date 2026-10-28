import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// Where a model file comes from, pinned by tag or commit and checked by size and hash, so what
/// arrives is exactly what was released and getting it needs no account anywhere.
class PinnedSource {
  final String url;
  final String sha256;
  final int bytes;
  const PinnedSource({required this.url, required this.sha256, required this.bytes});
}

/// Gemma Terms of Use §3.1 asks for exactly this notice with every copy of a Gemma model.
const gemmaNotice =
    'Gemma is provided under and subject to the Gemma Terms of Use found at '
    'ai.google.dev/gemma/terms';
const gemmaProhibitedUse = 'ai.google.dev/gemma/prohibited_use_policy';

/// Raise this when the wording in lib/terms.dart changes, so the next download asks again.
const termsVersion = 1;

/// On-device models Berea knows how to download. Same `.litertlm` files AI Edge Gallery uses.
class EdgeModel {
  final String id;
  final String label;
  final String repo;
  final String file;
  final double sizeGb;
  final ModelType type;
  final Tier tier;

  /// The file Berea downloads, from its own releases or a Hugging Face commit.
  final PinnedSource source;

  /// A licence notice to show before the download, for models that ask for one.
  final String? notice;

  /// One line on what the model is like, for the helper choice in Study.
  final String summary;
  const EdgeModel({
    required this.id,
    required this.label,
    required this.repo,
    required this.file,
    required this.sizeGb,
    required this.type,
    required this.tier,
    required this.summary,
    required this.source,
    this.notice,
  });

  /// flutter_edge_ai keys installed models by the downloaded filename. Berea 0.4 to 0.6 let the
  /// plugin fetch from [repo] into its own folder, and such a copy is still used.
  String get installedName => file;

  /// Gemma 4 takes spoken audio directly, so voice questions need no separate speech model.
  bool get hearsAudio => type == ModelType.gemma4;

  /// The download's size in bytes.
  int get publishedBytes => source.bytes;
}

/// Download sizes are labelled in decimal gigabytes, as model sizes are published.
const bytesPerDownloadGb = 1000 * 1000 * 1000;

/// [bytes] in decimal gigabytes to one place, such as "1.1".
String gbOf(int bytes) => (bytes / bytesPerDownloadGb).toStringAsFixed(1);

const edgeModels = <EdgeModel>[
  EdgeModel(
    id: 'gemma-4-e2b',
    label: 'Gemma 4 E2B',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    file: 'gemma-4-E2B-it.litertlm',
    sizeGb: 2.6,
    type: ModelType.gemma4,
    tier: Tier.mid,
    summary: 'Hears spoken questions.',
    source: PinnedSource(
      url:
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/'
          '1caa527c1e88b55f046fcd8d2b4265606680663d/gemma-4-E2B-it.litertlm',
      sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
      bytes: 2588147712,
    ),
  ),
  EdgeModel(
    id: 'gemma-4-e4b',
    label: 'Gemma 4 E4B',
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
    file: 'gemma-4-E4B-it.litertlm',
    sizeGb: 3.7,
    type: ModelType.gemma4,
    tier: Tier.high,
    summary: 'Fuller answers for phones with 10 GB or more. Hears spoken questions.',
    source: PinnedSource(
      url:
          'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/'
          'e6a3892a8c22cf87ff99583996149cf3cb32452b/gemma-4-E4B-it.litertlm',
      sha256: '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
      bytes: 3659530240,
    ),
  ),
  EdgeModel(
    id: 'gemma-3-1b',
    label: 'Gemma 3 1B',
    repo: 'litert-community/Gemma3-1B-IT',
    file: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    sizeGb: 0.6,
    type: ModelType.gemmaIt,
    tier: Tier.low,
    summary: 'Quicker, shorter answers.',
    source: PinnedSource(
      url:
          'https://github.com/CalvinMagezi/berea/releases/download/model-gemma3-1b-1/'
          'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
      sha256: '1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be',
      bytes: 584417280,
    ),
    notice: gemmaNotice,
  ),
];

EdgeModel edgeModelById(String id) =>
    edgeModels.firstWhere((m) => m.id == id, orElse: () => edgeModels.first);

/// Below this, Gemma 4 E2B leaves too little room for the OS and the app.
const minGbForE2b = 5.0;

/// At or above this, Gemma 4 E4B is comfortable.
const minGbForE4b = 10.0;

/// Best model for [gb] of RAM; null [gb] (unknown) picks the default.
EdgeModel recommendedModel(double? gb) {
  if (gb == null || gb >= minGbForE2b && gb < minGbForE4b) return edgeModelById('gemma-4-e2b');
  if (gb >= minGbForE4b) return edgeModelById('gemma-4-e4b');
  return edgeModelById('gemma-3-1b');
}

/// Below this, Gemma 4 E2B at the mid tier's 5.4k context holds about 3.8 GB with 1.2 GB swapped
/// on a 5.5 GB Galaxy A32, and answers take 225 s against 148 s at the low tier. Measured on that
/// one phone; the band between 5.5 and 7 GB is untested.
const minGbForMidTier = 7.0;

/// The prompt budget [m] runs at on a device with [gb] of RAM; unknown RAM keeps the model's own.
Tier recommendedTier(EdgeModel m, double? gb) =>
    m.tier == Tier.mid && gb != null && gb < minGbForMidTier ? Tier.low : m.tier;
