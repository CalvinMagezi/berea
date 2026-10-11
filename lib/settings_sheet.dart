import 'package:berea_harness/berea_harness.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';

const minPassphraseLength = 8;

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

  /// A translation the user owns: CSV, USFM book files, OSIS, Zefania, or a zip of those.
  /// Stays on this device.
  Future<void> _importTranslation(BuildContext context) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'usfm', 'sfm', 'xml', 'osis', 'zip'],
    );
    if (picked.isEmpty) return;
    final files = [for (final f in picked) (name: f.name, bytes: await f.readAsBytes())];
    if (!context.mounted) return;
    final guess = picked.first.name
        .split('.')
        .first
        .replaceAll(RegExp('[^A-Za-z]'), '')
        .toUpperCase();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: guess.length > 8 ? guess.substring(0, 8) : guess);
        return AlertDialog(
          title: const Text('Translation code'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 8,
            decoration: const InputDecoration(hintText: 'NIV, NLT, ESV'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim().toUpperCase()),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = widget.state.importTranslation(files, code);
      setState(() => draft = draft.copyWith(translation: code));
      messenger.showSnackBar(SnackBar(content: Text('Imported $code: $n verses')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<String?> _askPassphrase(BuildContext context, {required bool confirm}) {
    final a = TextEditingController();
    final b = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(confirm ? 'Choose a passphrase' : 'Backup passphrase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: a,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Passphrase'),
              ),
              if (confirm) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: b,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Repeat passphrase'),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (a.text.length < minPassphraseLength) {
                  setInner(() => error = 'Use at least $minPassphraseLength characters.');
                } else if (confirm && a.text != b.text) {
                  setInner(() => error = 'The passphrases differ.');
                } else {
                  Navigator.pop(ctx, a.text);
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _backup(BuildContext context) async {
    final pass = await _askPassphrase(context, confirm: true);
    if (pass == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await widget.state.backup(pass);
    final saved = await FilePicker.saveFile(
      fileName: 'berea-backup.berea',
      bytes: bytes,
      type: FileType.any,
    );
    if (saved != null) messenger.showSnackBar(const SnackBar(content: Text('Backup saved.')));
  }

  Future<void> _restore(BuildContext context) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final bytes = await picked.single.readAsBytes();
    if (!context.mounted) return;
    final pass = await _askPassphrase(context, confirm: false);
    if (pass == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace your data?'),
        content: const Text(
          'Restoring replaces every note, study, plan and highlight on this device with the '
          "backup's contents. This cannot be undone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.state.restore(bytes, pass);
      messenger.showSnackBar(const SnackBar(content: Text('Backup restored.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

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
                if (widget.state.deviceGb != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'This device has ${widget.state.deviceGb!.toStringAsFixed(1)} GB of memory. '
                      'Recommended: ${recommendedModel(widget.state.deviceGb).label}.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import a translation'),
                  onPressed: () => _importTranslation(context),
                ),
              ),
              const Divider(height: 24),
              Text('Your data', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Notes, studies, plans and imports live only on this device. A backup is one '
                'encrypted file you keep; without its passphrase nobody, including you, can open it.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Back up'),
                    onPressed: () => _backup(context),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore'),
                    onPressed: () => _restore(context),
                  ),
                ],
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
