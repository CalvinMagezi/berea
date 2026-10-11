import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

Future<void> showSettingsSheet(BuildContext context, AppState state) {
  return showDialog<void>(context: context, builder: (_) => _SettingsDialog(state));
}

class _SettingsDialog extends StatefulWidget {
  final AppState state;
  const _SettingsDialog(this.state);

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late Settings draft = widget.state.settings;
  late final _url = TextEditingController(text: draft.ollamaUrl);
  late final _model = TextEditingController(text: draft.model);

  @override
  Widget build(BuildContext context) {
    final translations = widget.state.db.translations();
    return AlertDialog(
      title: const Text('Engine'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'Ollama URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Tier>(
              initialValue: draft.tier,
              decoration: const InputDecoration(labelText: 'Tier (prompt budget)'),
              items: [
                for (final t in Tier.values)
                  DropdownMenuItem(value: t, child: Text('${t.name} · ${t.promptTokens} tokens')),
              ],
              onChanged: (t) => setState(() => draft = draft.copyWith(tier: t)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: draft.translation,
              decoration: const InputDecoration(labelText: 'Translation'),
              items: [for (final t in translations) DropdownMenuItem(value: t, child: Text(t))],
              onChanged: (t) => setState(() => draft = draft.copyWith(translation: t)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            widget.state.updateSettings(
              draft.copyWith(ollamaUrl: _url.text.trim(), model: _model.text.trim()),
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
