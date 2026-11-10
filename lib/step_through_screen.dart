import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

/// Steps through passages one verse at a time with no commentary or scoring.
class StepThroughScreen extends StatefulWidget {
  final AppState state;
  final String title;
  final List<Ref> refs;

  const StepThroughScreen({
    super.key,
    required this.state,
    required this.title,
    required this.refs,
  });

  @override
  State<StepThroughScreen> createState() => _StepThroughScreenState();
}

class _StepThroughScreenState extends State<StepThroughScreen> {
  var _index = 0;
  late final List<Verse> _verses;

  @override
  void initState() {
    super.initState();
    final translation = widget.state.settings.translation;
    // Flatten verses across references in order, skipping references missing from the translation.
    _verses = [
      for (final ref in widget.refs)
        ...widget.state.db.verses(ref, translation: translation),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final translation = widget.state.settings.translation;

    if (_verses.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No verses to show in $translation.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final verse = _verses[_index];
    final isLast = _index >= _verses.length - 1;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Text(
                    verse.label,
                    style: TextStyle(
                      fontFamilyFallback: scriptureFontFallback,
                      color: scheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    translation,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  verse.text,
                  style: scriptureStyle(context).copyWith(fontSize: 20),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_index + 1} of ${_verses.length}',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (_index > 0) ...[
                    OutlinedButton(
                      onPressed: () => setState(() => _index--),
                      child: const Text('Previous verse'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  FilledButton(
                    onPressed: isLast
                        ? () => Navigator.pop(context)
                        : () => setState(() => _index++),
                    child: Text(isLast ? 'Done' : 'Next verse'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
