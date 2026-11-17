import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'daily_practices.dart';
import 'prayer_sheet.dart' show passageText;
import 'settings_sheet.dart' show showSettingsSheet;
import 'theme.dart';

const _pagePadding = 20.0;
const _labelSpacing = 1.2;

/// Where the two practices are listed, on the Prayer place: a row each, nothing more.
class PracticeRows extends StatelessWidget {
  final void Function(Practice) onOpen;
  const PracticeRows({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final p in Practice.values)
        ListTile(
          leading: Icon(
            p == Practice.building ? Icons.account_balance_outlined : Icons.nightlight_outlined,
          ),
          title: Text(p.title),
          subtitle: Text(p.blurb),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpen(p),
        ),
    ],
  );
}

/// Opens [practice] on a screen of its own.
void openPractice(BuildContext context, AppState state, Practice practice) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => switch (practice) {
      Practice.building => BuildingScreen(state: state),
      Practice.reflection => ReflectionScreen(state: state),
    },
  ),
);

Widget _page(Widget child) => Center(
  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: contentMaxWidth), child: child),
);

Widget _label(BuildContext context, String text) => Text(
  text.toUpperCase(),
  style: TextStyle(
    fontSize: 11,
    letterSpacing: _labelSpacing,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
);

/// A verse by reference, with its words read from the person's translation and a way into the
/// Bible. If the translation has no words for it, the reference and the button still show.
class _Verse extends StatelessWidget {
  final AppState state;
  final Ref verse;
  const _Verse({required this.state, required this.verse});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final words = passageText(state.db.passage(verse, translation: state.settings.translation));
    return Container(
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (words.isNotEmpty)
            SelectableText(
              words,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                height: 1.6,
                fontStyle: FontStyle.italic,
              ),
            ),
          Row(
            children: [
              Flexible(
                child: Text(
                  verse.label,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
              IconButton(
                tooltip: 'Open ${verse.label} in the Bible',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                onPressed: () {
                  state.openInReader(verse);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The line under each practice that leads to its reminder.
class _ReminderLink extends StatelessWidget {
  final AppState state;
  const _ReminderLink({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.reminderPlatform == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => showSettingsSheet(context, state),
        icon: const Icon(Icons.notifications_none, size: 18),
        label: const Text('Set a reminder in Settings'),
      ),
    );
  }
}

/// Daily inner building: one stone today, the one thing to do with it, and nothing else.
class BuildingScreen extends StatelessWidget {
  final AppState state;

  /// The day shown. Today unless a test says otherwise.
  final DateTime? day;
  const BuildingScreen({super.key, required this.state, this.day});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stone = stoneFor(day ?? DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(Practice.building.title)),
      body: _page(
        ListView(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 32),
          children: [
            _label(context, 'Today’s stone'),
            const SizedBox(height: 6),
            Text(
              stone.name,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              stone.picture,
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(_pagePadding),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(context, 'Today'),
                      const SizedBox(height: 8),
                      Text(
                        stone.practice,
                        style: theme.textTheme.titleLarge?.copyWith(height: 1.4),
                      ),
                      if (stone.say case final say?) ...[
                        const SizedBox(height: 16),
                        Text(
                          '“$say”',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontStyle: FontStyle.italic,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            _Verse(state: state, verse: buildingVerse),
            const SizedBox(height: 16),
            _ReminderLink(state: state),
          ],
        ),
      ),
    );
  }
}

/// The steps of the reflection, in order: be still, one lens at a time, then mercy.
enum _Step { still, sin, iniquity, transgression, mercy }

/// Daily reflection: five short steps, one at a time. Nothing is written down or kept; the
/// person looks at their day, and Berea does not look with them.
class ReflectionScreen extends StatefulWidget {
  final AppState state;
  const ReflectionScreen({super.key, required this.state});

  @override
  State<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends State<ReflectionScreen> {
  var _step = 0;

  static const _steps = _Step.values;

  void _go(int to) => setState(() => _step = to);

  @override
  Widget build(BuildContext context) {
    final last = _step == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text(Practice.reflection.title)),
      body: _page(
        Column(
          children: [
            Expanded(
              child: ListView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 16),
                children: [
                  _label(context, 'Step ${_step + 1} of ${_steps.length}'),
                  const SizedBox(height: 12),
                  _body(context, _steps[_step]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton.icon(
                      onPressed: () => _go(_step - 1),
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: last ? () => Navigator.pop(context) : () => _go(_step + 1),
                    child: Text(last ? 'Done' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, _Step step) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600);
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6);
    switch (step) {
      case _Step.still:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Be still', style: title),
            const SizedBox(height: 12),
            Text(reflectionStill, style: body),
            const SizedBox(height: 20),
            Text(
              'Walk back through the day, from waking to now. Three questions follow: where did '
              'I miss, bend, and cross?',
              style: body?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _ReminderLink(state: widget.state),
          ],
        );
      case _Step.mercy:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mercy', style: title),
            const SizedBox(height: 12),
            Text(reflectionPrayer, style: body?.copyWith(fontStyle: FontStyle.italic)),
            const SizedBox(height: 20),
            Text('Make it right', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(reflectionRepair, style: body),
            const SizedBox(height: 24),
            _Verse(state: widget.state, verse: reflectionVerse),
          ],
        );
      case _Step.sin || _Step.iniquity || _Step.transgression:
        final lens = lenses[step.index - 1];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lens.name, style: title),
            const SizedBox(height: 4),
            Text(
              '${lens.hebrew} · ${lens.picture}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(lens.question, style: theme.textTheme.titleLarge?.copyWith(height: 1.3)),
            const SizedBox(height: 16),
            for (final prompt in lens.prompts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 22, child: Text('•', style: body)),
                    Expanded(child: Text(prompt, style: body)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Name the exact person, word, motive or omission. Do not rush to defend yourself.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        );
    }
  }
}
