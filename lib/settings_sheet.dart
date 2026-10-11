import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';

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
  late final _token = TextEditingController(text: draft.hfToken);

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    _url.dispose();
    _model.dispose();
    _token.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Settings get _merged => draft.copyWith(
    ollamaUrl: _url.text.trim(),
    model: _model.text.trim(),
    hfToken: _token.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    final translations = widget.state.db.translations();
    return AlertDialog(
      title: const Text('Engine'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<EngineKind>(
                segments: const [
                  ButtonSegment(value: EngineKind.device, label: Text('On device')),
                  ButtonSegment(value: EngineKind.ollama, label: Text('Ollama')),
                ],
                selected: {draft.engine},
                onSelectionChanged: (s) => setState(() => draft = draft.copyWith(engine: s.first)),
              ),
              const SizedBox(height: 16),
              if (draft.engine == EngineKind.ollama) ...[
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: 'Ollama URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: draft.deviceModelId,
                  decoration: const InputDecoration(labelText: 'Model'),
                  items: [
                    for (final m in edgeModels)
                      DropdownMenuItem(value: m.id, child: Text('${m.label} · ${m.sizeGb} GB')),
                  ],
                  onChanged: (id) => setState(
                    () => draft = draft.copyWith(deviceModelId: id, tier: edgeModelById(id!).tier),
                  ),
                ),
                if (draft.deviceModel.gated) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _token,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Hugging Face token'),
                  ),
                ],
                const SizedBox(height: 12),
                _DeviceModelStatus(state: widget.state, draft: _merged),
              ],
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            widget.state.updateSettings(_merged);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DeviceModelStatus extends StatelessWidget {
  final AppState state;
  final Settings draft;
  const _DeviceModelStatus({required this.state, required this.draft});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sameModel = draft.deviceModelId == state.settings.deviceModelId;
    final st = sameModel ? state.deviceState : DeviceModelState.notInstalled;
    switch (st) {
      case DeviceModelState.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: state.downloadProgress / 100),
            const SizedBox(height: 6),
            Text('Downloading ${state.downloadProgress}%'),
          ],
        );
      case DeviceModelState.loading:
        return const Text('Loading model…');
      case DeviceModelState.ready:
        return Text('Installed and loaded', style: TextStyle(color: scheme.primary));
      case DeviceModelState.failed:
      case DeviceModelState.notInstalled:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.deviceError != null && sameModel)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  state.deviceError!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download_outlined),
                label: Text('Download (${draft.deviceModel.sizeGb} GB)'),
                onPressed: () async {
                  await state.updateSettings(draft);
                  await state.downloadDeviceModel();
                },
              ),
            ),
          ],
        );
    }
  }
}
