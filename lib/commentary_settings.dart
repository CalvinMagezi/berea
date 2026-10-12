import 'package:berea_harness/berea_harness.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'attributions_screen.dart';
import 'commentary_packs.dart';

/// The Commentaries part of the settings: download, add from a file or delete each optional
/// pack, and the licences of everything Berea carries.
class CommentarySettings extends StatelessWidget {
  final AppState state;

  /// Reports the outcome of an action inside the settings dialog.
  final ValueChanged<String> onMessage;
  const CommentarySettings({super.key, required this.state, required this.onMessage});

  CommentaryShelf get shelf => state.commentary;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Commentaries', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Optional public domain commentaries. Select verses in the Bible tab and tap '
          'Commentary to read them. Each is downloaded only if you ask, from the Berea releases '
          'on GitHub, checked against its published fingerprint, and kept on this device.',
          style: muted,
        ),
        for (final spec in commentaryPackSpecs) _packRow(context, spec, muted),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('From a file'),
              onPressed: () => _installFromFile(),
            ),
            TextButton.icon(
              icon: const Icon(Icons.info_outline),
              label: const Text('Licences and sources'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const AttributionsScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _packRow(BuildContext context, CommentaryPackSpec spec, TextStyle muted) {
    final pin = commentaryPins[spec.id];
    final authors = [for (final id in spec.modules) commentaryModuleById(id)?.author ?? id];
    final progress = shelf.progress[spec.id];
    final Widget action;
    if (progress != null) {
      action = SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(
          value: progress,
          strokeWidth: 3,
          semanticsLabel: 'Downloading ${spec.title}',
          semanticsValue: '${(progress * 100).round()}',
        ),
      );
    } else if (shelf.isInstalled(spec.id)) {
      action = IconButton(
        tooltip: 'Delete ${spec.title}',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(context, spec),
      );
    } else {
      action = IconButton(
        tooltip: 'Download ${spec.title}',
        icon: const Icon(Icons.download_outlined),
        onPressed: pin == null ? null : () => _download(spec),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(spec.title),
      subtitle: Text(
        [authors.join('; '), if (pin != null) pin.sizeLabel].join(' · '),
        style: muted,
      ),
      trailing: action,
    );
  }

  Future<void> _download(CommentaryPackSpec spec) async {
    try {
      await shelf.download(spec);
      onMessage('${spec.title} installed.');
    } catch (e) {
      onMessage('${spec.title} could not be installed: $e');
    }
  }

  Future<void> _installFromFile() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final path = picked.single.path;
    if (path == null) {
      onMessage('That file is not on this device.');
      return;
    }
    try {
      onMessage('${await shelf.installFromFile(path)} installed.');
    } catch (e) {
      onMessage('Commentary install failed: $e');
    }
  }

  Future<void> _delete(BuildContext context, CommentaryPackSpec spec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${spec.title}?'),
        content: const Text('You can download it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    shelf.delete(spec);
    onMessage('${spec.title} deleted.');
  }
}
