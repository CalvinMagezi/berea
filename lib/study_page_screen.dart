import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'provenance.dart';
import 'provenance_line.dart';
import 'theme.dart';

/// Observation, interpretation and application for one passage. The user writes it and
/// saves it locally.
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

  AppState get s => widget.state;
  var _provenance = provenancePerson;

  @override
  void initState() {
    super.initState();
    final saved = s.study.studyPageFor(widget.ref);
    _provenance = saved?.provenance ?? provenancePerson;
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

  void _save() {
    s.study.saveStudyPage(widget.ref, _observation.text, _interpretation.text, _application.text);
    s.touch();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final verses = s.db.verses(widget.ref, translation: s.settings.translation);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Study page · ${widget.ref.label}',
          style: TextStyle(fontFamilyFallback: scriptureFontFallback),
        ),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
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
              ProvenanceLine(_provenance),
              const SizedBox(height: 16),
              _Section('Observation', _observation),
              _Section('Interpretation', _interpretation),
              _Section('Application', _application),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  const _Section(this.title, this.controller);

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
          ),
        ],
      ),
    );
  }
}
