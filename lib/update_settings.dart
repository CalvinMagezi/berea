import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'app_update.dart';

/// Settings: the update check. Shown on Android only, where Berea can install what it finds.
class UpdateSettingsSection extends StatefulWidget {
  final AppState state;
  final ValueChanged<String> onMessage;
  const UpdateSettingsSection({super.key, required this.state, required this.onMessage});

  @override
  State<UpdateSettingsSection> createState() => _UpdateSettingsSectionState();
}

class _UpdateSettingsSectionState extends State<UpdateSettingsSection> {
  var _checking = false;

  UpdateService get _updates => widget.state.updates;

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final said = await _updates.check();
    if (!mounted) return;
    setState(() => _checking = false);
    widget.onMessage(said);
  }

  @override
  Widget build(BuildContext context) {
    if (!_updates.supported) return const SizedBox.shrink();
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: _updates,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 24),
          Text('Updates', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Look for a new version when Berea opens'),
            subtitle: Text(
              'Asks GitHub for the newest release, at most once a day. Nothing about you is sent. '
              'A bar appears when one is out; nothing downloads until you tap Update.',
              style: muted,
            ),
            value: _updates.checkOnOpen,
            onChanged: _updates.setCheckOnOpen,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _checking ? null : _checkNow,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_checking ? 'Looking…' : 'Check now'),
            ),
          ),
        ],
      ),
    );
  }
}
