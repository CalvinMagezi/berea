import 'package:flutter/material.dart';

import 'app_state.dart';
import 'helper_setup.dart';
import 'models.dart';

const _panelRadius = 14.0;
const _progressHeight = 4.0;
const _noteSize = 12.0;

/// Download details, opened from the Study button while the helper downloads.
Future<void> showDownloadDetails(BuildContext context, AppState state) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: DownloadDetails(state: state),
        ),
      ),
    );

/// The helper download: what it waits for, how much is left, and the choices about it.
class DownloadDetails extends StatelessWidget {
  final AppState state;
  const DownloadDetails({super.key, required this.state});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: state, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = state.settings.deviceModel;
    final h = state.helperState;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const HelperMark(),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The helper', style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '${m.label} · ${m.sizeGb} GB',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (h is HelperDownloading) ..._downloading(context, h, m) else _settled(context, h),
        const SizedBox(height: 12),
        Text(
          'Reading never waits for this. The ring on Study fills as it comes.',
          style: TextStyle(fontSize: _noteSize, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  List<Widget> _downloading(BuildContext context, HelperDownloading h, EdgeModel m) {
    final total = h.total ?? m.publishedBytes;
    final left = total - (h.bytes ?? 0);
    return [
      _Progress(h: h, total: total, left: left),
      if (h.waitingForWifi) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: state.useMobileDataOnce,
          child: Text('Use mobile data for the ${gbOf(left)} GB left'),
        ),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Download only on Wi-Fi'),
        value: state.wifiOnly,
        onChanged: (on) => state.setWifiOnly(on),
      ),
      Row(
        children: [
          TextButton(onPressed: state.cancelDownload, child: const Text('Cancel download')),
          const Spacer(),
          h.paused
              ? TextButton(onPressed: state.resumeDownload, child: const Text('Resume'))
              : TextButton(onPressed: state.pauseDownload, child: const Text('Pause')),
        ],
      ),
    ];
  }

  Widget _settled(BuildContext context, HelperState h) => Text(switch (h) {
    HelperReady() => 'The helper is ready. Ask in Study.',
    HelperFailed(:final reason) => reason,
    HelperNotInstalled() => 'The download was cancelled. Choose a helper in Study to start again.',
    _ => 'The helper is getting ready.',
  });
}

class _Progress extends StatelessWidget {
  final HelperDownloading h;
  final int total;
  final int left;
  const _Progress({required this.h, required this.total, required this.left});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, title) = h.waitingForWifi
        ? (Icons.wifi, 'Paused, waiting for Wi-Fi')
        : h.paused
        ? (Icons.pause, 'Paused')
        : (Icons.download_outlined, 'Downloading');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${gbOf(h.bytes ?? 0)} of ${gbOf(total)} GB · ${gbOf(left)} GB to go',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: h.fraction,
            minHeight: _progressHeight,
            borderRadius: BorderRadius.circular(_progressHeight),
          ),
        ],
      ),
    );
  }
}
