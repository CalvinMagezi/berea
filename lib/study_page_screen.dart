import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

/// Observation, interpretation and application for one passage. Berea drafts it from the
/// retrieved context; the user edits and saves it locally.
class StudyPageScreen extends StatefulWidget {
  final AppState state;
  final Ref ref;
  const StudyPageScreen({super.key, required this.state, required this.ref});

  @override
  State<StudyPageScreen> createState() => _StudyPageScreenState();
}

class _StudyPageScreenState extends State<StudyPageScreen> {
  final _observation = TextEditingController();
  final _interpretation = TextEditingController();
  final _application = TextEditingController();
  var _draft = '';
  var _generating = false;
  String? _error;
  String? _nearMissNote;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    final saved = s.study.studyPageFor(widget.ref);
    if (saved != null) {
      _observation.text = saved.observation;
      _interpretation.text = saved.interpretation;
      _application.text = saved.application;
    }
  }

  @override
  void dispose() {
    _observation.dispose();
    _interpretation.dispose();
    _application.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (s.harness == null || !s.ready) return;
    setState(() {
      _generating = true;
      _draft = '';
      _error = null;
      _nearMissNote = null;
    });
    try {
      // The engine writes one answer at a time, shared with the Study and notebook chats.
      final page = await s.runExclusive(
        (h) => h.studyPage(widget.ref, onToken: (t) => setState(() => _draft += t)),
      );
      if (page == null) {
        _error = 'Berea is answering another question. Try again when it has finished.';
        return;
      }
      _observation.text = page.observation;
      _interpretation.text = page.interpretation;
      _application.text = page.application;
      _nearMissNote = nearMissNotice(page.guard.nearMisses);
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _generating = false);
    }
  }

  void _save() {
    s.study.saveStudyPage(widget.ref, _observation.text, _interpretation.text, _application.text);
    s.touch();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verses = s.db.passage(widget.ref, translation: s.settings.translation);
    final empty =
        _observation.text.isEmpty && _interpretation.text.isEmpty && _application.text.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Study page · ${widget.ref.label}',
          style: TextStyle(fontFamilyFallback: scriptureFontFallback),
        ),
        actions: [
          TextButton(onPressed: _generating ? null : _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                verses.map((v) => '${v.verse} ${v.text}').join(' '),
                style: scriptureStyle(context).copyWith(fontSize: 17),
              ),
              const SizedBox(height: 16),
              if (s.harness == null)
                Text(
                  'Load a model in settings to draft this page, or write it yourself.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              else
                OutlinedButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: Text(empty ? 'Draft with Berea' : 'Redraft with Berea'),
                ),
              if (_generating)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _draft.isEmpty ? 'Examining the Scriptures…' : _draft,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              if (_nearMissNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_nearMissNote!, style: TextStyle(color: scheme.error, fontSize: 13)),
                ),
              const SizedBox(height: 16),
              _Section('Observation', 'What does the text say?', _observation),
              _Section('Interpretation', 'What does it mean?', _interpretation),
              _Section('Application', 'How should I live?', _application),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String hint;
  final TextEditingController controller;
  const _Section(this.title, this.hint, this.controller);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: null,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}
