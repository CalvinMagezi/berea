import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prayer_sheet.dart';
import 'prayer_store.dart';
import 'theme.dart';

const _cardRadius = 20.0;
const _cardPadding = 20.0;
const _dotSize = 6.0;

/// More than this many prayers and the step dots give way to the count alone.
const _maxDots = 12;

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

String dayMonth(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

/// Matthew 6:9-13, read from the Bible in the reader's translation.
final lordsPrayer = Ref(bookById(40), 6, 9, 13);

class _StepDots extends StatelessWidget {
  final int index;
  final int count;
  const _StepDots(this.index, this.count);

  @override
  Widget build(BuildContext context) {
    if (count > _maxDots) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: _dotSize,
            height: _dotSize,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= index ? scheme.primary : scheme.surfaceContainerHighest,
            ),
          ),
      ],
    );
  }
}

/// The card Pray now shows: who, what, the note, and the verse in full.
class PrayerCard extends StatelessWidget {
  final Prayer prayer;
  final PassageLookup passage;
  final String translation;
  const PrayerCard({
    super.key,
    required this.prayer,
    required this.passage,
    required this.translation,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ref = prayer.ref;
    final verseText = ref == null ? '' : passageText(passage(ref));
    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prayer.forWhom.isNotEmpty) ...[
            Text(
              'FOR ${prayer.forWhom.toUpperCase()}',
              style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 1.2),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            prayer.title,
            style: t.headlineSmall?.copyWith(
              fontFamilyFallback: scriptureFontFallback,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (prayer.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(prayer.note, style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (ref != null && verseText.isNotEmpty) ...[
            const Divider(height: 32),
            PrayerLabel('${ref.label} · $translation'),
            const SizedBox(height: 8),
            Text(verseText, style: scriptureStyle(context).copyWith(fontSize: 18)),
          ],
        ],
      ),
    );
  }
}

String prayedSummary(Prayer p) => p.daysPrayed == 0
    ? 'Not prayed yet'
    : 'Prayed on ${p.daysPrayed} ${p.daysPrayed == 1 ? 'day' : 'days'} '
          'since ${dayMonth(p.firstPrayed!)}';

/// One prayer at a time, least recently prayed first. Amen records today and moves on. The order
/// is fixed when the session starts, so praying does not reshuffle the list underneath.
class PrayNowView extends StatefulWidget {
  final PrayerStore store;
  final PassageLookup passage;
  final String Function() translation;

  /// Leaves Pray now: closes the page on a phone, resets the panel on a wide screen.
  final VoidCallback onDone;

  /// The prayer to open on, such as the row clicked in the wide list. Its place in the order
  /// is kept, so the ones before it are a step back.
  final int? startAt;

  /// Shows that the arrow keys move between prayers, for the wide layout.
  final bool keyHint;
  const PrayNowView({
    super.key,
    required this.store,
    required this.passage,
    required this.translation,
    required this.onDone,
    this.startAt,
    this.keyHint = false,
  });

  @override
  State<PrayNowView> createState() => _PrayNowViewState();
}

class _PrayNowViewState extends State<PrayNowView> {
  late final _ids = [for (final p in widget.store.prayNowQueue()) p.id];
  late var _index = switch (_ids.indexOf(widget.startAt ?? -1)) {
    -1 => 0,
    final i => i,
  };
  var _prayed = 0;

  Prayer? get _current {
    while (_index < _ids.length) {
      final p = widget.store.prayer(_ids[_index]);
      if (p != null && !p.isAnswered && !p.archived) return p;
      _ids.removeAt(_index);
    }
    return null;
  }

  void _next() => setState(() => _index++);

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _edit(Prayer p) async {
    await showPrayerSheet(context, widget.store, editing: p, passage: widget.passage);
    if (mounted) setState(() {});
  }

  void _amen(Prayer p) {
    widget.store.amen(p.id);
    _prayed++;
    _next();
  }

  Future<void> _answered(Prayer p) async {
    if (await answerPrayer(context, widget.store, p)) setState(() {});
  }

  Future<void> _addLine(Prayer p) async {
    final line = (await askExtraLine(context))?.trim();
    if (line == null || line.isEmpty) return;
    final note = p.note.isEmpty ? line : '${p.note}\n$line';
    widget.store.edit(p.id, title: p.title, forWhom: p.forWhom, verse: p.verse, note: note);
    setState(() {});
  }

  Widget _finished(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(_cardPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Amen', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            _prayed == 0
                ? 'Nothing left to pray through right now.'
                : 'You prayed for ${_prayed == 1 ? 'one request' : '$_prayed requests'} today.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: widget.onDone, child: const Text('Done')),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = _current;
    if (p == null) return _finished(context);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final position = '${_index + 1} of ${_ids.length}';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _back,
      },
      child: Focus(autofocus: true, child: _body(context, p, position, muted)),
    );
  }

  Widget _body(BuildContext context, Prayer p, String position, TextStyle? muted) {
    return ListView(
      padding: const EdgeInsets.all(_cardPadding),
      children: [
        Row(
          children: [
            _StepDots(_index, _ids.length),
            const SizedBox(width: 8),
            Text(widget.keyHint ? '$position · ← → to move' : position, style: muted),
          ],
        ),
        const SizedBox(height: 16),
        PrayerCard(prayer: p, passage: widget.passage, translation: widget.translation()),
        const SizedBox(height: 8),
        Text(prayedSummary(p), style: muted, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _answered(p),
                icon: const Icon(Icons.check),
                label: const Text('Answered'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _amen(p),
                icon: const Icon(Icons.chevron_right),
                iconAlignment: IconAlignment.end,
                label: const Text('Amen, next'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(onPressed: _next, child: const Text('Skip')),
            TextButton.icon(
              onPressed: () => _addLine(p),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Add a line'),
            ),
            TextButton(onPressed: () => _edit(p), child: const Text('Edit')),
          ],
        ),
      ],
    );
  }
}

/// Pray now as its own page, for phones.
class PrayNowScreen extends StatelessWidget {
  final PrayerStore store;
  final PassageLookup passage;
  final String Function() translation;
  const PrayNowScreen({
    super.key,
    required this.store,
    required this.passage,
    required this.translation,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: const CloseButton(), title: const Text('Pray now')),
    body: PrayNowView(
      store: store,
      passage: passage,
      translation: translation,
      onDone: () => Navigator.pop(context),
    ),
  );
}

/// The Lord's Prayer from Matthew 6:9-13, a verse at a time.
class LordsPrayerScreen extends StatefulWidget {
  final PassageLookup passage;
  final String Function() translation;
  const LordsPrayerScreen({super.key, required this.passage, required this.translation});

  @override
  State<LordsPrayerScreen> createState() => _LordsPrayerScreenState();
}

class _LordsPrayerScreenState extends State<LordsPrayerScreen> {
  late final _verses = widget.passage(lordsPrayer);
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final last = _index >= _verses.length - 1;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(leading: const CloseButton(), title: const Text("The Lord's Prayer")),
      body: _verses.isEmpty
          ? const Center(child: Text('Matthew 6 is not in this translation.'))
          : ListView(
              padding: const EdgeInsets.all(_cardPadding),
              children: [
                Row(
                  children: [
                    _StepDots(_index, _verses.length),
                    const SizedBox(width: 8),
                    PrayerLabel('${lordsPrayer.label} · ${widget.translation()}'),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(_cardPadding),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(_cardRadius),
                  ),
                  child: Text(
                    _verses[_index].text,
                    style: scriptureStyle(context).copyWith(fontSize: 20),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: last ? () => Navigator.pop(context) : () => setState(() => _index++),
                  child: Text(last ? 'Amen' : 'Next line'),
                ),
              ],
            ),
    );
  }
}
