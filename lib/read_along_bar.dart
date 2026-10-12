import 'package:flutter/material.dart';

import 'narration_packs.dart';
import 'read_along.dart';

const _spinnerSize = 24.0;
const _spinnerStroke = 3.0;

String speedLabel(double speed) =>
    speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';

/// The read-along controls above the chapter bar: previous and next verse, play and pause,
/// speed, and stop, with what is reading and by whom.
class ReadAlongBar extends StatelessWidget {
  final ReadAlongState state;
  final String bookName;

  /// The verse being read, once the voice has reached one.
  final int? verse;

  /// Download progress from 0 to 1 while the narration is being fetched.
  final double? downloadProgress;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<double> onSpeed;
  final VoidCallback onClose;

  const ReadAlongBar({
    super.key,
    required this.state,
    required this.bookName,
    this.verse,
    this.downloadProgress,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeed,
    required this.onClose,
  });

  String get _where => '$bookName ${state.chapter}${verse == null ? '' : ':$verse'}';

  String get _who => state.voice == ReadAlongVoice.narration
      ? 'Narrated by $narrationCredit'
      : 'Device voice, offline';

  String get _subtitle => switch (state.status) {
    ReadAlongStatus.failed => state.error ?? 'Playback failed.',
    ReadAlongStatus.loading when downloadProgress != null =>
      'Downloading the narration of $bookName',
    _ => _who,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = state.status == ReadAlongStatus.failed;
    final ready = !failed && state.status != ReadAlongStatus.loading;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous verse',
              icon: const Icon(Icons.skip_previous),
              onPressed: ready ? onPrevious : null,
            ),
            _playButton(),
            IconButton(
              tooltip: 'Next verse',
              icon: const Icon(Icons.skip_next),
              onPressed: ready ? onNext : null,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                liveRegion: failed,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _where,
                      style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                    Text(
                      _subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: failed ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<double>(
              tooltip: 'Speed ${speedLabel(state.speed)}',
              initialValue: state.speed,
              onSelected: onSpeed,
              itemBuilder: (_) => [
                for (final s in readAlongSpeeds)
                  PopupMenuItem(value: s, child: Text(speedLabel(s))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text(speedLabel(state.speed)),
              ),
            ),
            IconButton(
              tooltip: 'Stop reading aloud',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _playButton() {
    if (state.status == ReadAlongStatus.loading) {
      final p = downloadProgress;
      return SizedBox(
        width: kMinInteractiveDimension,
        child: Center(
          child: SizedBox.square(
            dimension: _spinnerSize,
            child: CircularProgressIndicator(
              value: p,
              strokeWidth: _spinnerStroke,
              semanticsLabel: p == null ? 'Loading' : 'Downloading the narration',
              semanticsValue: p == null ? null : '${(p * 100).round()}',
            ),
          ),
        ),
      );
    }
    final playing = state.status == ReadAlongStatus.playing;
    return IconButton(
      tooltip: playing ? 'Pause' : 'Play',
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      onPressed: state.status == ReadAlongStatus.failed ? null : onPlayPause,
    );
  }
}
