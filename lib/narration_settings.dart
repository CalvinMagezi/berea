import 'package:berea_harness/berea_harness.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'narration_packs.dart';

const _progressSize = 24.0;
const _progressStroke = 3.0;

/// The Narration part of the settings: download, add from a file or delete each book's pack.
class NarrationSettings extends StatelessWidget {
  final AppState state;

  /// Reports the outcome of an action inside the settings dialog.
  final ValueChanged<String> onMessage;
  const NarrationSettings({super.key, required this.state, required this.onMessage});

  NarrationShelf get shelf => state.narration;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Narration', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'The Berean Standard Bible read by $narrationCredit (public domain), one download '
          'per book. Tap Listen in the Bible tab to hear a chapter with each word marked as it '
          'is read. Downloaded only if you ask, from the Berea releases on GitHub, checked '
          'against its published fingerprint, and kept on this device.',
          style: muted,
        ),
        for (final book in shelf.availableBooks) _bookRow(context, bookById(book), muted),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('From a file'),
            onPressed: _installFromFile,
          ),
        ),
      ],
    );
  }

  Widget _bookRow(BuildContext context, Book book, TextStyle muted) {
    final pin = narrationPins[book.id];
    final progress = shelf.progress[book.id];
    final Widget action;
    if (progress != null) {
      action = SizedBox.square(
        dimension: _progressSize,
        child: CircularProgressIndicator(
          value: progress,
          strokeWidth: _progressStroke,
          semanticsLabel: 'Downloading the narration of ${book.name}',
          semanticsValue: '${(progress * 100).round()}',
        ),
      );
    } else if (shelf.isInstalled(book.id)) {
      action = IconButton(
        tooltip: 'Delete the narration of ${book.name}',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(context, book),
      );
    } else {
      action = IconButton(
        tooltip: 'Download the narration of ${book.name}',
        icon: const Icon(Icons.download_outlined),
        onPressed: pin == null ? null : () => _download(book),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(book.name),
      subtitle: Text([narrationCredit, if (pin != null) pin.sizeLabel].join(' · '), style: muted),
      trailing: action,
    );
  }

  Future<void> _download(Book book) async {
    try {
      await shelf.download(book.id);
      onMessage('The narration of ${book.name} is installed.');
    } catch (e) {
      onMessage('The narration of ${book.name} could not be installed: $e');
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
      onMessage('The narration of ${await shelf.installFromFile(path)} is installed.');
    } catch (e) {
      onMessage('Narration install failed: $e');
    }
  }

  Future<void> _delete(BuildContext context, Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete the narration of ${book.name}?'),
        content: const Text('You can download it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    if (state.readAlong.state.value?.book == book.id) await state.readAlong.stop();
    shelf.delete(book.id);
    onMessage('The narration of ${book.name} is deleted.');
  }
}
