import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'notebooks_screen.dart';
import 'theme.dart';

/// What a deep dive on a notebook would draw on, gathered from the Bible and the installed
/// commentaries without the helper: each BSB section, its parallels and cross references, the
/// key words of the reading, commentary, and witnesses from the other testament.
class StudyPacketScreen extends StatefulWidget {
  final AppState state;
  final int notebookId;
  const StudyPacketScreen({super.key, required this.state, required this.notebookId});

  @override
  State<StudyPacketScreen> createState() => _StudyPacketScreenState();
}

class _StudyPacketScreenState extends State<StudyPacketScreen> {
  // Built once: it reads every verse's words, so a rebuild must not repeat it.
  late final packet = widget.state.studyPacket(widget.notebookId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Synthesize')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: packet.isEmpty ? const _Empty() : _PacketList(packet: packet),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(
      'Nothing to synthesize yet. Add a Bible passage to this notebook, or keep a note or a '
      'study page on a passage in it.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _PacketList extends StatelessWidget {
  final StudyPacket packet;
  const _PacketList({required this.packet});

  @override
  Widget build(BuildContext context) {
    final p = packet;
    final noCommentary = p.inputs.packs.isEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Gathered from the Bible (BSB)${noCommentary ? '' : ' and your installed commentaries'}. '
          'Nothing here is written by the helper.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (noCommentary)
          const _Note('No commentary is installed. Add one in Settings to include it here.'),
        for (final s in p.sections) _SectionCard(section: s),
        if (p.keyWords.isNotEmpty) ...[
          const _Heading('Key words'),
          for (final k in p.keyWords)
            _Line(
              '${k.entry.lemma} (${k.entry.translit}), "${k.entry.gloss}"',
              '${strongsBase(k.entry.key)} · ${plural(k.count, 'time', 'times')} in the reading, '
                  'first in ${k.firstUse.label}',
            ),
        ],
        if (p.witnesses.isNotEmpty) ...[
          const _Heading('Witnesses from the other testament'),
          for (final w in p.witnesses) _Line(w.to.label, '${w.to.text}\nFrom ${w.from.label}'),
        ],
        if (p.introductions.isNotEmpty) ...[
          const _Heading('Introductions'),
          for (final t in {for (final c in p.introductions) c.title}) _Line(t, null),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final PacketSection section;
  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final s = section;
    final text = Theme.of(context).textTheme;
    final works = {for (final c in s.commentary) c.title};
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: text.titleMedium),
            Text(
              '${s.ref.label} · ${plural(s.verses.length, 'verse', 'verses')}'
              '${s.inherited ? ' · continues a section' : ''}',
              style: text.bodySmall,
            ),
            if (s.parallelVerses.isNotEmpty)
              _Labelled('Parallels', s.parallelVerses.map((v) => v.label).join('; ')),
            if (s.crossReferences.isNotEmpty)
              _Labelled('Cross references', s.crossReferences.map((v) => v.label).join('; ')),
            if (works.isNotEmpty) _Labelled('Commentary', works.join('; ')),
          ],
        ),
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  final String label;
  final String value;
  const _Labelled(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _Line extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _Line(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
  );
}
