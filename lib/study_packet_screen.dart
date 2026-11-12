import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'extras_hint.dart';
import 'notebooks_screen.dart';
import 'settings_sheet.dart';
import 'theme.dart';

/// A comment shown in Synthesize is cut here; the whole text is in the notebook's chat sources.
const _commentChars = 700;

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
          child: packet.isEmpty ? const _Empty() : _PacketList(state: widget.state, packet: packet),
        ),
      ),
    );
  }
}

/// The work a commentary chunk comes from: its title without "on James 3:1".
String _work(SourceChunk c) {
  final at = c.title.lastIndexOf(' on ');
  return at > 0 ? c.title.substring(0, at) : c.title;
}

/// [chunks] grouped by work, in the order the works first appear.
Map<String, List<SourceChunk>> _byWork(Iterable<SourceChunk> chunks) {
  final out = <String, List<SourceChunk>>{};
  for (final c in chunks) {
    out.putIfAbsent(_work(c), () => []).add(c);
  }
  return out;
}

final _spaces = RegExp(r'\s+');

String _excerpt(String text) {
  final flat = text.replaceAll(_spaces, ' ').trim();
  return flat.length <= _commentChars ? flat : '${flat.substring(0, _commentChars).trimRight()}...';
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
  final AppState state;
  final StudyPacket packet;
  const _PacketList({required this.state, required this.packet});

  @override
  Widget build(BuildContext context) {
    final p = packet;
    final works = _byWork([for (final s in p.sections) ...s.commentary]).length;
    final verses = p.sections.fold(0, (n, s) => n + s.verses.length);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          '${plural(p.sections.length, 'section', 'sections')} · '
          '${plural(verses, 'verse', 'verses')}, from the Berean Standard Bible'
          '${works == 0 ? '' : ' and ${plural(works, 'commentary', 'commentaries')}'}. '
          'Tap a reference to read it.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (p.inputs.packs.isEmpty)
          ExtrasHint(state: state, part: SettingsPart.commentary, text: commentaryHint),
        for (final s in p.sections) _SectionCard(state: state, section: s),
        if (p.keyWords.isNotEmpty) ...[
          const _Heading('Key words', 'Hebrew and Greek words in these verses, from the BSB translation tables.'),
          for (final k in p.keyWords) _KeyWordTile(state: state, word: k),
        ],
        if (p.witnesses.isNotEmpty) ...[
          const _Heading(
            'Cross references into the other testament',
            'OpenBible.info · most votes first · the votes are that site\'s visitors\'.',
          ),
          for (final w in p.witnesses) _WitnessTile(state: state, witness: w),
        ],
        if (p.introductions.isNotEmpty) ...[
          const _Heading('Introductions', 'What the commentators say about the book or chapter.'),
          for (final MapEntry(key: work, value: chunks) in _byWork(p.introductions).entries)
            _CommentTile(work: work, chunks: chunks),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final AppState state;
  final PacketSection section;
  const _SectionCard({required this.state, required this.section});

  @override
  Widget build(BuildContext context) {
    final s = section;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              '${s.ref.label} · ${plural(s.verses.length, 'verse', 'verses')}'
              '${s.inherited ? ' · continues a section' : ''}',
              style: text.bodySmall,
            ),
            if (s.parallelVerses.isNotEmpty)
              _RefChips(state: state, label: 'Parallel passages', verses: s.parallelVerses),
            if (s.crossReferences.isNotEmpty)
              _RefChips(state: state, label: 'Cross references', verses: s.crossReferences),
            if (s.commentary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Commentary', style: text.labelLarge),
              for (final MapEntry(key: work, value: chunks) in _byWork(s.commentary).entries)
                _CommentTile(work: work, chunks: chunks),
            ],
          ],
        ),
      ),
    );
  }
}

class _RefChips extends StatelessWidget {
  final AppState state;
  final String label;
  final List<Verse> verses;
  const _RefChips({required this.state, required this.label, required this.verses});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final v in verses)
              ActionChip(
                label: Text(v.label),
                tooltip: v.text,
                onPressed: () => state.openInReader(Ref(v.book, v.chapter, v.verse)),
              ),
          ],
        ),
      ],
    ),
  );
}

/// One commentary work, folded: its name and how many comments, opening to read them.
class _CommentTile extends StatelessWidget {
  final String work;
  final List<SourceChunk> chunks;
  const _CommentTile({required this.work, required this.chunks});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(work),
      subtitle: Text(plural(chunks.length, 'comment', 'comments')),
      children: [
        for (final c in chunks) ...[
          if (c.ref case final ref?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                ref.label,
                style: TextStyle(fontWeight: FontWeight.w600, color: muted),
              ),
            ),
          SelectableText(_excerpt(c.text), style: const TextStyle(height: 1.45)),
        ],
      ],
    );
  }
}

class _KeyWordTile extends StatelessWidget {
  final AppState state;
  final KeyWord word;
  const _KeyWordTile({required this.state, required this.word});

  @override
  Widget build(BuildContext context) {
    final e = word.entry;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: e.lemma, style: const TextStyle(fontSize: 20)),
            TextSpan(
              text: '  ${e.translit}',
              style: TextStyle(fontStyle: FontStyle.italic, color: muted),
            ),
          ],
        ),
      ),
      subtitle: Text(
        '${e.gloss.isEmpty ? '' : 'Means "${e.gloss}". '}'
        'Used ${plural(word.count, 'time', 'times')} here, first in ${word.firstUse.label}.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => state.openInReader(word.firstUse),
    );
  }
}

class _WitnessTile extends StatelessWidget {
  final AppState state;
  final Witness witness;
  const _WitnessTile({required this.state, required this.witness});

  @override
  Widget build(BuildContext context) {
    final to = witness.to;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(to.label),
      subtitle: Text('${to.text}\nPointed to from ${witness.from.label}.'),
      isThreeLine: true,
      onTap: () => state.openInReader(Ref(to.book, to.chapter, to.verse)),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  final String about;
  const _Heading(this.text, this.about);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        Text(about, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}
