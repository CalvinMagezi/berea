import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// On-device models Berea knows how to download. Same `.litertlm` files AI Edge Gallery uses.
class EdgeModel {
  final String id;
  final String label;
  final String repo;
  final String file;
  final double sizeGb;
  final ModelType type;
  final Tier tier;

  /// Gated repos need a Hugging Face token after accepting the model license.
  final bool gated;
  const EdgeModel({
    required this.id,
    required this.label,
    required this.repo,
    required this.file,
    required this.sizeGb,
    required this.type,
    required this.tier,
    this.gated = false,
  });

  /// flutter_edge_ai keys installed models by the downloaded filename.
  String get installedName => file;

  /// Gemma 4 takes spoken audio directly, so voice questions need no separate speech model.
  bool get hearsAudio => type == ModelType.gemma4;
}

const edgeModels = <EdgeModel>[
  EdgeModel(
    id: 'gemma-4-e2b',
    label: 'Gemma 4 E2B',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    file: 'gemma-4-E2B-it.litertlm',
    sizeGb: 2.6,
    type: ModelType.gemma4,
    tier: Tier.mid,
  ),
  EdgeModel(
    id: 'gemma-4-e4b',
    label: 'Gemma 4 E4B',
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
    file: 'gemma-4-E4B-it.litertlm',
    sizeGb: 4.3,
    type: ModelType.gemma4,
    tier: Tier.high,
  ),
  EdgeModel(
    id: 'gemma-3-1b',
    label: 'Gemma 3 1B (needs Hugging Face token)',
    repo: 'litert-community/Gemma3-1B-IT',
    file: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    sizeGb: 0.5,
    type: ModelType.gemmaIt,
    tier: Tier.low,
    gated: true,
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
