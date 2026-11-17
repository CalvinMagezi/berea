import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'daily_practices.dart';
import 'daily_reminder.dart' show reminderTimeLabel;
import 'reminder_settings.dart' show deniedMessage;

const _sheetPadding = 24.0;

/// Settings: a reminder for each daily practice. Off until turned on, set on this device, and
/// carrying no words of the reader's own. Not shown where this build cannot schedule
/// notifications.
class PracticeReminderSettings extends StatelessWidget {
  final AppState state;
  final ValueChanged<String> onMessage;
  const PracticeReminderSettings({super.key, required this.state, required this.onMessage});

  Future<void> _choose(BuildContext context, Practice practice, {required bool changing}) async {
    final denied = await showPracticeReminderSheet(context, state, practice, changing: changing);
    if (denied == true) onMessage(deniedMessage);
  }

  @override
  Widget build(BuildContext context) {
    if (state.reminderPlatform == null) return const SizedBox.shrink();
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 24),
          Text('Daily practices', style: Theme.of(context).textTheme.titleSmall),
          for (final p in Practice.values) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.title),
              subtitle: Text(p.blurb, style: muted),
              value: state.practiceReminder(p).on,
              onChanged: (on) => on
                  ? _choose(context, p, changing: false)
                  : state.turnOffPracticeReminder(p).then((_) {}),
            ),
            if (state.practiceReminder(p).on)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('At ${reminderTimeLabel(state.practiceReminder(p).minutes)}'),
                trailing: TextButton(
                  onPressed: () => _choose(context, p, changing: true),
                  child: const Text('Change'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Choose a time, then turn [practice]'s reminder on. Resolves to true when the person said no
/// to notifications, so the caller can say how to allow them.
Future<bool?> showPracticeReminderSheet(
  BuildContext context,
  AppState state,
  Practice practice, {
  required bool changing,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _PracticeReminderSheet(state: state, practice: practice, changing: changing),
);

class _PracticeReminderSheet extends StatefulWidget {
  final AppState state;
  final Practice practice;
  final bool changing;
  const _PracticeReminderSheet({
    required this.state,
    required this.practice,
    required this.changing,
  });

  @override
  State<_PracticeReminderSheet> createState() => _PracticeReminderSheetState();
}

class _PracticeReminderSheetState extends State<_PracticeReminderSheet> {
  late var _minutes = widget.changing
      ? widget.state.practiceReminder(widget.practice).minutes
      : widget.practice.defaultMinutes;
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
      on = await widget.state.turnOnPracticeReminder(widget.practice, _minutes);
    } finally {
      if (mounted) Navigator.pop(context, on ? null : true);
    }
  }

  /// The notification as it will show today, so the person sees what they are asking for.
  (String, String) _preview() {
    final m = practiceMessage(widget.practice, DateTime.now());
    return (m.title, m.body);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final times = widget.practice.times;
    final custom = !times.contains(_minutes);
    final (title, body) = _preview();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(_sheetPadding, 0, _sheetPadding, _sheetPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.practice.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'One notification a day at the time you choose. Set on this device; nothing is sent.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Text('When', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in times)
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
                Text(body, maxLines: 4, overflow: TextOverflow.ellipsis),
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
