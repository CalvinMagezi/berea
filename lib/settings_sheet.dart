import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'backup.dart';
import 'commentary_settings.dart';
import 'reminder_settings.dart';

const minPassphraseLength = 8;

/// The Settings button every place shows in its app bar, as Study does.
class SettingsButton extends StatelessWidget {
  final AppState state;
  const SettingsButton({super.key, required this.state});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Settings',
    icon: const Icon(Icons.tune),
    onPressed: () => showSettingsSheet(context, state),
  );
}

/// A part of Settings a hint can open straight to.
enum SettingsPart { commentary, lexicon }

/// Opens Settings, scrolled to [show] when given.
Future<void> showSettingsSheet(BuildContext context, AppState state, {SettingsPart? show}) {
  return showDialog<void>(context: context, builder: (_) => _SettingsDialog(state, show: show));
}

class _SettingsDialog extends StatefulWidget {
  final AppState state;
  final SettingsPart? show;
  const _SettingsDialog(this.state, {this.show});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late Settings draft = widget.state.settings;

  final _parts = {for (final p in SettingsPart.values) p: GlobalKey()};

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_refresh);
    if (widget.show case final part?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final at = _parts[part]!.currentContext;
        if (at != null && at.mounted) Scrollable.ensureVisible(at, alignment: 0.1);
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// Result of the last action, shown inside the dialog where it cannot be hidden.
  String? _message;

  void _say(String message) {
    if (mounted) setState(() => _message = message);
  }

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
            textCapitalization: TextCapitalization.characters,
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
    try {
      final n = await widget.state.importTranslation(files, code);
      setState(() => draft = draft.copyWith(translation: code));
      _say('Imported $code: $n verses');
    } catch (e) {
      _say(plainFailure(e, 'The translation could not be imported.'));
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

  Future<void> _installLexicon(BuildContext context, {required bool fromFile}) async {
    Uint8List? bytes;
    if (fromFile) {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty) return;
      bytes = await picked.single.readAsBytes();
    }
    try {
      await widget.state.installLexiconPack(bytes: bytes);
      setState(() {});
      _say('Full lexicon installed.');
    } catch (e) {
      _say(plainFailure(e, 'The lexicon pack could not be installed.'));
    }
  }

  Future<void> _installMiddleLiddell(BuildContext context, {required bool fromFile}) async {
    Uint8List? bytes;
    if (fromFile) {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty) return;
      bytes = await picked.single.readAsBytes();
    }
    try {
      await widget.state.installMiddleLiddellPack(bytes: bytes);
      setState(() {});
      _say('Middle Liddell definitions installed.');
    } catch (e) {
      _say(plainFailure(e, 'The Middle Liddell pack could not be installed.'));
    }
  }

  Future<void> _backup(BuildContext context) async {
    final pass = await _askPassphrase(context, confirm: true);
    if (pass == null || !context.mounted) return;
    final bytes = await widget.state.backup(pass);
    final saved = await FilePicker.saveFile(
      fileName: 'berea-backup.berea',
      bytes: bytes,
      type: FileType.any,
    );
    if (saved != null) _say('Backup saved.');
  }

  Future<void> _restore(BuildContext context) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final bytes = await picked.single.readAsBytes();
    if (!context.mounted) return;
    final pass = await _askPassphrase(context, confirm: false);
    if (pass == null || !context.mounted) return;
    _say('Checking the backup\u2026');
    final BackupContents contents;
    try {
      contents = await widget.state.openBackup(bytes, pass);
    } catch (e) {
      _say(plainFailure(e, 'The backup could not be opened. Nothing changed.'));
      return;
    }
    if (!context.mounted) return;
    String count(String t, String one, String many) {
      final n = contents.tables[t]?.length ?? 0;
      return '$n ${n == 1 ? one : many}';
    }

    final summary = [
      count('notes', 'note', 'notes'),
      count('conversations', 'saved study', 'saved studies'),
      count('study_pages', 'study page', 'study pages'),
      count('highlights', 'highlight', 'highlights'),
      if (contents.hasNotebooks) count('notebooks', 'notebook', 'notebooks'),
      if (contents.imports.isNotEmpty) 'translations ${contents.imports.keys.join(', ')}',
    ].join(', ');
    final replaced = contents.hasNotebooks
        ? 'note, study, plan, highlight and notebook'
        : 'note, study, plan and highlight';
    final notebooksNote = contents.hasNotebooks
        ? ''
        : ' This backup was made before notebooks, so your notebooks are kept.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace your data?'),
        content: Text(
          'This backup holds $summary. Restoring replaces every $replaced on this device '
          'with it. This cannot be undone.$notebooksNote',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
        ],
      ),
    );
    if (ok != true) {
      _say('Restore cancelled. Nothing changed.');
      return;
    }
    try {
      final skipped = widget.state.applyBackup(contents);
      _say(
        skipped.isEmpty
            ? 'Backup restored.'
            : 'Backup restored. These imported translations could not be read: '
                  '${skipped.join(', ')}.',
      );
    } catch (e) {
      _say(plainFailure(e, 'The backup could not be restored.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final translations = widget.state.db.translations();
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: draft.translation,
                decoration: const InputDecoration(labelText: 'Translation'),
                items: [for (final t in translations) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (t) => setState(() => draft = draft.copyWith(translation: t)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Red letters'),
                subtitle: const Text('The BSB publisher marks the words of Jesus.'),
                value: draft.redLetters,
                onChanged: (on) => setState(() => draft = draft.copyWith(redLetters: on)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Supplied words in italics'),
                subtitle: const Text('Words the BSB translators added so the English reads well.'),
                value: draft.suppliedWords,
                onChanged: (on) => setState(() => draft = draft.copyWith(suppliedWords: on)),
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
              if (widget.state.setAsideImports.isNotEmpty)
                Text(
                  'Could not load imported translations: ${widget.state.setAsideImports.join(', ')}. '
                  'Import them again from the original files.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                ),
              const Divider(height: 24),
              Text(
                'Full Greek lexicon',
                key: _parts[SettingsPart.lexicon],
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                widget.state.db.hasFullLexicon
                    ? 'Installed. Long-press a New Testament verse and tap a word to read it.'
                    : 'Optional, about 9 MB: the complete Liddell-Scott-Jones entries for every '
                          'Greek word in the New Testament (STEPBible, CC BY). Downloaded only if you '
                          'ask, from the Berea releases on GitHub.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!widget.state.db.hasFullLexicon)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download'),
                      onPressed: () => _installLexicon(context, fromFile: false),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('From a file'),
                      onPressed: () => _installLexicon(context, fromFile: true),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Text('Middle Liddell definitions', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                widget.state.db.hasMiddleLiddell
                    ? 'Installed. Greek entries whose definition is Middle Liddell\'s show it, with its credit.'
                    : 'Optional, under 1 MB: the definitions STEPBible takes from Middle Liddell (the '
                          'Perseus Digital Library, share-alike) for about 2,000 Greek entries. They are '
                          'kept in their own file and downloaded only if you ask, from the Berea releases '
                          'on GitHub.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!widget.state.db.hasMiddleLiddell)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download'),
                      onPressed: () => _installMiddleLiddell(context, fromFile: false),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('From a file'),
                      onPressed: () => _installMiddleLiddell(context, fromFile: true),
                    ),
                  ],
                ),
              const Divider(height: 24),
              CommentarySettings(
                key: _parts[SettingsPart.commentary],
                state: widget.state,
                onMessage: _say,
              ),
              ReminderSettingsSection(state: widget.state, onMessage: _say),
              const Divider(height: 24),
              Text('Your data', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Notes, studies, notebooks, plans and imports live only on this device. A backup is one '
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
              if (_message != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_message!),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            widget.state.updateSettings(draft);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
