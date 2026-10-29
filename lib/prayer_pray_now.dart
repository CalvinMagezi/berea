import 'dart:async';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prayer_points.dart';
import 'prayer_sheet.dart';
import 'prayer_store.dart';
import 'theme.dart';

const _cardRadius = 20.0;
const _cardPadding = 20.0;
const _dotSize = 6.0;

/// A second tap this soon after Amen moved on is the same tap, not Amen for the next prayer.
const _amenSettle = Duration(milliseconds: 500);

/// More than this many prayers and the step dots give way to the count alone.
const _maxDots = 12;

/// Lines from a prayer's topic shown under it in Pray now.
const _wordLines = 2;

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

String monthName(DateTime d) => _monthNames[d.month - 1];

String dayMonth(DateTime d) => '${d.day} ${monthName(d)}';

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
/// is fixed when the session starts, so praying does not reshuffle the list underneath; prayers
/// added meanwhile join at the end.
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

  /// Told which prayer is showing, null once the session is through, so a list can mark it.
  final ValueChanged<int?>? onShow;

  /// The prayer lines bundled with the app. With them Pray now opens with praise, confession and
  /// thanks, asks through the list, and closes with others, one line from the Word at each.
  final PrayerContent? content;
  const PrayNowView({
    super.key,
    required this.store,
    required this.passage,
    required this.translation,
    required this.onDone,
    this.startAt,
    this.keyHint = false,
    this.onShow,
    this.content,
  });

  @override
  State<PrayNowView> createState() => _PrayNowViewState();
}

/// One step of the frame around the list: a label and the line from the Word to pray.
class _FrameStep {
  final String label;
  final PrayerPoint point;
  const _FrameStep(this.label, this.point);
}

class _PrayNowViewState extends State<PrayNowView> {
  late final _ids = [for (final p in widget.store.prayNowQueue()) p.id];

  /// The frame, a different line each day. Empty without the bundled lines.
  late final _before = _frame(const [
    ('Praise', 'praise'),
    ('Confess', 'confession'),
    ('Thank', 'thanksgiving'),
  ]);
  late final _after = _frame(const [('Others', 'others')]);

  /// Short of time: Ask only skips the frame.
  var _askOnly = false;

  int get _lead => _askOnly ? 0 : _before.length;
  List<_FrameStep> get _tail => _askOnly ? const [] : _after;

  List<_FrameStep> _frame(List<(String, String)> steps) {
    final day = prayerDay(widget.store.now());
    return [
      for (final (label, id) in steps)
        if (widget.content?.topic(id)?.points case final points? when points.isNotEmpty)
          _FrameStep(label, points[day % points.length]),
    ];
  }

  late var _index = switch (_ids.indexOf(widget.startAt ?? -1)) {
    -1 => 0,
    final i => i + _before.length,
  };
  late final _seen = {..._ids};

  /// Distinct, so stepping back and saying Amen again counts the prayer once.
  final _prayed = <int>{};
  Timer? _settling;

  @override
  void dispose() {
    _settling?.cancel();
    super.dispose();
  }

  void _takeNew() {
    for (final p in widget.store.prayNowQueue()) {
      if (_seen.add(p.id)) _ids.add(p.id);
    }
  }

  /// The prayer at the current step, or null on a frame step or once the list is through.
  Prayer? get _current {
    final at = _index - _lead;
    while (at >= 0 && at < _ids.length) {
      final p = widget.store.prayer(_ids[at]);
      if (p != null && !p.isAnswered && !p.archived) return p;
      _ids.removeAt(at);
    }
    return null;
  }

  /// The frame step showing, or null when a prayer is.
  _FrameStep? get _frameStep {
    final at = _index - _lead;
    if (at < 0) return _before[_index];
    final after = at - _ids.length;
    return after >= 0 && after < _tail.length ? _tail[after] : null;
  }

  int get _steps => _lead + _ids.length + _tail.length;

  bool get _hasFrame => !_askOnly && (_before.isNotEmpty || _after.isNotEmpty);

  void _askOnlyNow() => setState(() {
    _askOnly = true;
    _index = 0;
  });

  void _next() => setState(() => _index++);

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  /// Amen on a frame step records nothing, but moves on with the same guard as a prayer's Amen,
  /// so a quick second tap is not read as Amen for the first prayer.
  void _amenFrame() => _skip();

  /// Moves on without recording anything, with the guard a quick second tap needs.
  void _skip() {
    if (_settling?.isActive ?? false) return;
    _next();
    _settling = Timer(_amenSettle, () {});
  }

  Future<void> _edit(Prayer p) async {
    await showPrayerSheet(context, widget.store, editing: p, passage: widget.passage);
    if (mounted) setState(() {});
  }

  void _amen(Prayer p) {
    if (_settling?.isActive ?? false) return;
    widget.store.amen(p.id);
    _prayed.add(p.id);
    _next();
    _settling = Timer(_amenSettle, () {});
  }

  Future<void> _answered(Prayer p) async {
    if (await answerPrayer(context, widget.store, p)) setState(() {});
  }

  Future<void> _addLine(Prayer p) async {
    final line = (await askExtraLine(context))?.trim();
    if (line == null || line.isEmpty) return;
    final note = p.note.isEmpty ? line : '${p.note}\n$line';
    widget.store.edit(
      p.id,
      title: p.title,
      forWhom: p.forWhom,
      verse: p.verse,
      note: note,
      topic: p.topic,
    );
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
          Text(switch (_prayed.length) {
            0 when _ids.isNotEmpty => 'You skipped them all this time. They stay on the list.',
            0 => 'Nothing left to pray through right now.',
            1 => 'You prayed for one request today.',
            final n => 'You prayed for $n requests today.',
          }, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(onPressed: widget.onDone, child: const Text('Done')),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: widget.store, builder: (context, _) => _build(context));

  void _report(int? id) {
    final show = widget.onShow;
    if (show == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) show(id);
    });
  }

  Widget _build(BuildContext context) {
    _takeNew();
    final p = _current;
    final step = _frameStep;
    _report(p?.id);
    if (p == null && step == null) return _finished(context);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final position = '${_index + 1} of $_steps';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _back,
      },
      child: Focus(
        autofocus: true,
        child: step != null
            ? _frameBody(context, step, position, muted)
            : _body(context, p!, position, muted),
      ),
    );
  }

  /// The labels of the frame, the one being prayed in bold: Praise, Confess, Thank, Ask, Others.
  Widget _frameLabels(BuildContext context, String now) {
    final scheme = Theme.of(context).colorScheme;
    final labels = [
      ...[for (final s in _askOnly ? const <_FrameStep>[] : _before) s.label],
      'Ask',
      ...[for (final s in _tail) s.label],
    ];
    return Wrap(
      spacing: 12,
      children: [
        for (final l in labels)
          Text(
            l,
            style: TextStyle(
              fontWeight: l == now ? FontWeight.w700 : FontWeight.w400,
              color: l == now ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _frameBody(BuildContext context, _FrameStep step, String position, TextStyle? muted) {
    final scheme = Theme.of(context).colorScheme;
    final verse = passageText(widget.passage(step.point.verse));
    return ListView(
      padding: const EdgeInsets.all(_cardPadding),
      children: [
        Row(
          children: [
            _StepDots(_index, _steps),
            const SizedBox(width: 8),
            Text(widget.keyHint ? '$position · ← → to move' : position, style: muted),
          ],
        ),
        const SizedBox(height: 12),
        _frameLabels(context, step.label),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(_cardPadding),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PrayerLabel(step.label),
              const SizedBox(height: 6),
              Text(step.point.text, style: scriptureStyle(context).copyWith(fontSize: 22)),
              const SizedBox(height: 16),
              PrayerLabel('${step.point.ref} · ${widget.translation()}'),
              if (verse.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  verse,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: scriptureStyle(context)
                      .copyWith(fontSize: 15, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _amenFrame, child: const Text('Amen, next')),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(onPressed: _skip, child: const Text('Skip')),
            if (!_askOnly && _index < _lead)
              TextButton(onPressed: _askOnlyNow, child: const Text('Ask only')),
          ],
        ),
      ],
    );
  }

  /// Two lines from the prayer's topic, to pray it with the Word. None for a prayer that has no
  /// topic or whose topic this build does not have.
  List<Widget> _withTheWord(BuildContext context, Prayer p) {
    final topic = widget.content?.topic(p.topic);
    if (topic == null) return const [];
    return [
      const SizedBox(height: 12),
      PrayerLabel('Pray it with the Word \u00B7 ${topic.title}'),
      for (var i = 0; i < _wordLines && i < topic.points.length; i++)
        PointTile(number: i + 1, point: topic.points[i]),
    ];
  }

  Widget _body(BuildContext context, Prayer p, String position, TextStyle? muted) {
    return ListView(
      padding: const EdgeInsets.all(_cardPadding),
      children: [
        Row(
          children: [
            _StepDots(_index, _steps),
            const SizedBox(width: 8),
            Text(widget.keyHint ? '$position · ← → to move' : position, style: muted),
          ],
        ),
        const SizedBox(height: 16),
        if (_hasFrame) ...[_frameLabels(context, 'Ask'), const SizedBox(height: 12)],
        PrayerCard(prayer: p, passage: widget.passage, translation: widget.translation()),
        ..._withTheWord(context, p),
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
            TextButton(onPressed: _skip, child: const Text('Skip')),
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
  final PrayerContent? content;
  const PrayNowScreen({
    super.key,
    required this.store,
    required this.passage,
    required this.translation,
    this.content,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: const CloseButton(), title: const Text('Pray now')),
    body: PrayNowView(
      store: store,
      passage: passage,
      translation: translation,
      content: content,
      onDone: () => Navigator.pop(context),
    ),
  );
}

/// The Lord's Prayer from Matthew 6:9-13, a verse at a time.
class LordsPrayerScreen extends StatefulWidget {
  final PassageLookup passage;
  final String Function() translation;

  /// Any prayer in the Bible can be prayed a verse at a time; the Lord's Prayer is the default.
  final Ref? ref;
  final String title;
  const LordsPrayerScreen({
    super.key,
    required this.passage,
    required this.translation,
    this.ref,
    this.title = "The Lord's Prayer",
  });

  @override
  State<LordsPrayerScreen> createState() => _LordsPrayerScreenState();
}

class _LordsPrayerScreenState extends State<LordsPrayerScreen> {
  late final _ref = widget.ref ?? lordsPrayer;
  late final _verses = widget.passage(_ref);
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final last = _index >= _verses.length - 1;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(leading: const CloseButton(), title: Text(widget.title)),
      body: _verses.isEmpty
          ? Center(child: Text('${_ref.book.name} ${_ref.chapter} is not in this translation.'))
          : ListView(
              padding: const EdgeInsets.all(_cardPadding),
              children: [
                Row(
                  children: [
                    _StepDots(_index, _verses.length),
                    const SizedBox(width: 8),
                    PrayerLabel('${_ref.label} · ${widget.translation()}'),
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
