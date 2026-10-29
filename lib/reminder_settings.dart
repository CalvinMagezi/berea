import 'package:flutter/material.dart';

import 'app_state.dart';
import 'daily_reminder.dart';
import 'prayer_sheet.dart' show passageText;
import 'today.dart';

const _sheetPadding = 24.0;

/// Enough lines to show the verse and the prayer line under it in the preview.
const _previewLines = 7;

const deniedMessage =
    'Berea could not turn this on. Check that notifications are allowed for Berea in your '
    'device settings, then try again.';

/// Settings: the daily verse and prayer. Off until turned on, set on this device, and never
/// showing the reader's own prayers. Not shown where this build cannot schedule notifications.
class ReminderSettingsSection extends StatelessWidget {
  final AppState state;
  final ValueChanged<String> onMessage;
  const ReminderSettingsSection({super.key, required this.state, required this.onMessage});

  Future<void> _choose(BuildContext context, {required bool changing}) async {
    final denied = await showReminderSheet(context, state, changing: changing);
    if (denied == true) onMessage(deniedMessage);
  }

  @override
  Widget build(BuildContext context) {
    if (state.reminderPlatform == null) return const SizedBox.shrink();
    final r = state.reminder;
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text('Daily prayer', style: Theme.of(context).textTheme.titleSmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Verse of the day and prayer'),
          subtitle: Text(
            'A notification each morning, set on this device. Your own prayers never appear in it.',
            style: muted,
          ),
          value: r.on,
          onChanged: (on) =>
              on ? _choose(context, changing: false) : state.turnOffReminder().then((_) {}),
        ),
        if (r.on)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('At ${reminderTimeLabel(r.minutes)}'),
            subtitle: Text(
              r.referenceOnly ? 'The reference only on the lock screen' : 'The verse and prayer',
              style: muted,
            ),
            trailing: TextButton(
              onPressed: () => _choose(context, changing: true),
              child: const Text('Change'),
            ),
          ),
      ],
    );
  }
}

/// Choose a time and what the lock screen shows, then turn it on. Resolves to true when the
/// person said no to notifications, so the caller can say how to allow them.
Future<bool?> showReminderSheet(BuildContext context, AppState state, {required bool changing}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ReminderSheet(state: state, changing: changing),
    );

class _ReminderSheet extends StatefulWidget {
  final AppState state;
  final bool changing;
  const _ReminderSheet({required this.state, required this.changing});

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late var _minutes = widget.changing ? widget.state.reminder.minutes : defaultReminderMinutes;
  late var _referenceOnly = widget.state.reminder.referenceOnly;
  var _asking = false;

  Future<void> _other() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _minutes ~/ 60, minute: _minutes % 60),
    );
    if (picked != null) setState(() => _minutes = picked.hour * 60 + picked.minute);
  }

  Future<void> _turnOn() async {
    setState(() => _asking = true);
    var on = false;
    try {
      on = await widget.state.turnOnReminder(_minutes, referenceOnly: _referenceOnly);
    } finally {
      if (mounted) Navigator.pop(context, on ? null : true);
    }
  }

  /// Today's message as the notification will show it.
  (String, String) _preview() {
    final s = widget.state;
    final verse = verseOfTheDay(s.db, DateTime.now());
    if (_referenceOnly) return ('Verse of the day', verse.label);
    final text = passageText(s.db.passage(verse, translation: s.settings.translation));
    final prayer = s.prayerOfTheDay;
    return (verse.label, [text, if (prayer != null) 'Pray: ${prayer.point.text}'].join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final custom = !reminderTimes.contains(_minutes);
    final (title, body) = _preview();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(_sheetPadding, 0, _sheetPadding, _sheetPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Verse of the day and prayer', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            "Today's verse and a prayer at the time you choose. Set on this device; nothing is sent.",
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Text('When', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in reminderTimes)
                ChoiceChip(
                  label: Text(reminderTimeLabel(t)),
                  selected: _minutes == t,
                  onSelected: (_) => setState(() => _minutes = t),
                ),
              ChoiceChip(
                label: Text(custom ? reminderTimeLabel(_minutes) : 'Other time'),
                selected: custom,
                onSelected: (_) => _other(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('On the lock screen', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Verse and prayer')),
              ButtonSegment(value: true, label: Text('Reference only')),
            ],
            selected: {_referenceOnly},
            onSelectionChanged: (v) => setState(() => _referenceOnly = v.first),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Berea · preview', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(body, maxLines: _previewLines, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _asking ? null : _turnOn,
            child: Text(widget.changing ? 'Save' : 'Turn on'),
          ),
          if (!widget.changing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Your device will ask to allow notifications from Berea.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
