import 'package:flutter/material.dart';

import 'provenance.dart';

/// Says who wrote text a person did not, where that text is shown. Nothing for a person's own
/// words or a named source.
class ProvenanceLine extends StatelessWidget {
  final String provenance;
  const ProvenanceLine(this.provenance, {super.key});

  @override
  Widget build(BuildContext context) {
    final label = provenanceLabel(provenance);
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
