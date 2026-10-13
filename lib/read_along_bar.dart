import 'package:flutter/material.dart';

import 'narration_packs.dart';
import 'read_along.dart';

const _spinnerSize = 24.0;
const _spinnerStroke = 3.0;
const _subtitleSize = 12.0;
const _subtitleLines = 2;
const _barPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
const _speedPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 12);
const _labelGap = 4.0;

String speedLabel(double speed) =>
    speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';

/// The read-along controls above the chapter bar, with what is reading and by whom.
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

  bool get _failed => state.status == ReadAlongStatus.failed;

  bool get _ready => !_failed && state.status != ReadAlongStatus.loading;

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
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: _barPadding,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous verse',
            icon: const Icon(Icons.skip_previous),
            onPressed: _ready ? onPrevious : null,
          ),
          _playButton(),
          IconButton(
            tooltip: 'Next verse',
            icon: const Icon(Icons.skip_next),
            onPressed: _ready ? onNext : null,
          ),
          const SizedBox(width: _labelGap),
          Expanded(child: _label(context)),
          _speedMenu(),
          IconButton(
            tooltip: 'Stop reading aloud',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    ),
  );

  Widget _label(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: _failed,
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
            maxLines: _subtitleLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _subtitleSize,
              color: _failed ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedMenu() => PopupMenuButton<double>(
    tooltip: 'Speed ${speedLabel(state.speed)}',
    initialValue: state.speed,
    onSelected: onSpeed,
    itemBuilder: (_) => [
      for (final s in readAlongSpeeds) PopupMenuItem(value: s, child: Text(speedLabel(s))),
    ],
    child: Padding(padding: _speedPadding, child: Text(speedLabel(state.speed))),
  );

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
            ),
          ),
        ),
      );
    }
    final playing = state.status == ReadAlongStatus.playing;
    return IconButton(
      tooltip: playing ? 'Pause' : 'Play',
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      onPressed: _failed ? null : onPlayPause,
    );
  }
}
