import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'commentary_packs.dart' show bytesPerMb;
import 'theme.dart';
import 'voice.dart';

final _testVerse = Ref(bookFor('John')!, 3, 16);
final _benchmarkPassage = Ref(bookFor('Psalms')!, 23);
const _highlightAlpha = 0.28;

/// The Voice part of the settings: install the optional voice pack and try it.
class VoiceSettings extends StatelessWidget {
  final AppState state;
  final ValueChanged<String> onMessage;
  const VoiceSettings({super.key, required this.state, required this.onMessage});

  VoiceShelf get shelf => state.voice;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final progress = shelf.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Voice (experimental)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          shelf.installed
              ? 'Installed. Berea can read Scripture aloud on this device.'
              : 'Optional, about ${voicePackDownloadBytes ~/ bytesPerMb} MB: an on-device voice '
                    '(Kokoro, Apache-2.0) that reads Scripture aloud and highlights each word. '
                    'Downloaded only if you ask, from the Berea releases on GitHub, and checked '
                    'against its published fingerprint.',
          style: muted,
        ),
        if (progress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
        ] else
          Wrap(
            spacing: 8,
            children: [
              if (shelf.installed) ...[
                TextButton.icon(
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: const Text('Test voice'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => VoiceTestScreen(state: state)),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  onPressed: () => _delete(context),
                ),
              ] else ...[
                TextButton.icon(
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download'),
                  onPressed: _download,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('From files'),
                  onPressed: _installFromFiles,
                ),
              ],
            ],
          ),
      ],
    );
  }

  Future<void> _download() async {
    try {
      await shelf.download();
      onMessage('Voice installed.');
    } catch (e) {
      onMessage('The voice could not be downloaded: $e');
    }
  }

  /// The pack's files can be picked together; each is checked against its pin.
  Future<void> _installFromFiles() async {
    final picked = await FilePicker.pickFiles();
    final paths = [for (final f in picked) ?f.path];
    if (paths.isEmpty) return;
    onMessage('Checking ${paths.length} files…');
    try {
      final added = await shelf.installFromFiles(paths);
      final missing = shelf.missing.map((f) => f.name).toList();
      onMessage(
        missing.isEmpty
            ? 'Voice installed.'
            : 'Added ${added.length} of the voice files. Still needed: ${missing.join(', ')}.',
      );
    } catch (e) {
      onMessage('Voice install failed: $e');
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete the voice?'),
        content: const Text('You can download it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    shelf.delete();
    onMessage('Voice deleted.');
  }
}

/// Speaks a verse with live word highlighting, and measures how fast the voice runs.
class VoiceTestScreen extends StatefulWidget {
  final AppState state;
  const VoiceTestScreen({super.key, required this.state});

  @override
  State<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends State<VoiceTestScreen> {
  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final String _verse = _passageText(_testVerse);
  List<WordTiming> _words = const [];
  int? _current;
  File? _playing;
  String? _status;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(_player.onPositionChanged.listen(_follow))
      ..add(_player.onPlayerComplete.listen((_) => _finish()));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player.dispose();
    _deletePlaying();
    super.dispose();
  }

  String _passageText(Ref ref) => widget.state.db
      .passage(ref, translation: widget.state.settings.translation)
      .map((v) => v.text)
      .join(' ');

  /// The word being spoken is the last one that has started; between words the previous one
  /// stays lit, so the highlight never flickers off mid-phrase.
  void _follow(Duration position) {
    final ms = position.inMilliseconds;
    final i = _words.lastIndexWhere((w) => w.startMs <= ms);
    if (i != _current && mounted) setState(() => _current = i < 0 ? null : i);
  }

  void _finish() {
    _deletePlaying();
    if (mounted) setState(() => _current = null);
  }

  void _deletePlaying() {
    final f = _playing;
    _playing = null;
    if (f != null && f.existsSync()) f.deleteSync();
  }

  Future<void> _guard(Future<void> Function() job) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await job();
    } catch (e) {
      _show('$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// The screen may have closed while the voice was working.
  void _show(String status) {
    if (mounted) setState(() => _status = status);
  }

  Future<void> _speak(KokoroSpeaker speaker) => _guard(() async {
    await _player.stop();
    _finish();
    _show('Loading the voice…');
    final speech = await widget.state.withVoice((v) => v.speak(_verse, speaker));
    if (!mounted) return;
    // The platform's temporary folder is not guaranteed to exist yet (a sandboxed Mac app).
    final dir = (await getTemporaryDirectory())..createSync(recursive: true);
    final file = File('${dir.path}/berea-voice-${DateTime.now().microsecondsSinceEpoch}.wav');
    try {
      await file.writeAsBytes(wavBytes(speech.samples));
      await _debugDump(speaker, file, speech);
    } catch (_) {
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    if (!mounted) {
      file.deleteSync();
      return;
    }
    _playing = file;
    setState(() {
      _words = speech.words;
      _status =
          '${speaker.label}: ${_seconds(speech.duration)} of audio in '
          '${_seconds(speech.synthesis)}, real-time factor ${speech.realTimeFactor.toStringAsFixed(2)}.';
    });
    await _player.play(DeviceFileSource(file.path));
  });

  /// Debug builds with BEREA_VOICE_DUMP set keep the audio and word timings, so their sync
  /// can be checked against a speech recogniser outside the app.
  Future<void> _debugDump(KokoroSpeaker speaker, File wav, Speech speech) async {
    if (!kDebugMode || Platform.environment['BEREA_VOICE_DUMP'] == null) return;
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/voice-dump')
      ..createSync(recursive: true);
    await wav.copy('${dir.path}/${speaker.id}.wav');
    File('${dir.path}/${speaker.id}.json')
        .writeAsStringSync(jsonEncode([for (final w in speech.words) w.toJson()]));
    debugPrint('voice dump: ${dir.path}/${speaker.id}.wav');
  }

  /// Loads the voice cold, reads Psalm 23 in each voice and reports load time, real-time
  /// factor and memory, then closes it again.
  Future<void> _benchmark() => _guard(() async {
    await _player.stop();
    _finish();
    _show('Running the benchmark…');
    final text = _passageText(_benchmarkPassage);
    final rssBefore = ProcessInfo.currentRss;
    final clock = Stopwatch()..start();
    late final Duration load;
    var rssLoaded = 0;
    var rssSpoken = 0;
    final lines = <String>[];
    await widget.state.withVoice((v) async {
      load = clock.elapsed;
      rssLoaded = ProcessInfo.currentRss;
      for (final s in kokoroSpeakers) {
        final r = await v.speak(text, s);
        lines.add(
          '${s.label}: ${_seconds(r.duration)} audio in ${_seconds(r.synthesis)}, '
          'RTF ${r.realTimeFactor.toStringAsFixed(3)}',
        );
      }
      rssSpoken = ProcessInfo.currentRss;
    });
    final rssAfter = ProcessInfo.currentRss;
    final report = [
      'Psalm 23, ${text.split(' ').length} words. Load ${load.inMilliseconds} ms.',
      ...lines,
      'Memory: ${rssBefore ~/ bytesPerMb} MB before, ${rssLoaded ~/ bytesPerMb} MB loaded, '
          '${rssSpoken ~/ bytesPerMb} MB after speaking, ${rssAfter ~/ bytesPerMb} MB closed.',
    ].join('\n');
    debugPrint('voice benchmark\n$report');
    _show(report);
  });

  static String _seconds(Duration d) =>
      '${(d.inMilliseconds / Duration.millisecondsPerSecond).toStringAsFixed(2)} s';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontFamilyFallback: scriptureFontFallback, height: 1.6);
    return Scaffold(
      appBar: AppBar(title: const Text('Test voice')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_testVerse.label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(style: style, children: _spans(scheme.primary)),
                semanticsLabel: _verse,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in kokoroSpeakers)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text(s.label),
                      onPressed: _working ? null : () => _speak(s),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.speed),
                    label: const Text('Benchmark'),
                    onPressed: _working ? null : _benchmark,
                  ),
                ],
              ),
              if (_working)
                const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
              if (_status != null)
                Padding(padding: const EdgeInsets.only(top: 16), child: SelectableText(_status!)),
            ],
          ),
        ),
      ),
    );
  }

  /// The verse split at the spoken word's source offsets, with that word lit.
  List<TextSpan> _spans(Color accent) {
    final i = _current;
    if (i == null || i >= _words.length) return [TextSpan(text: _verse)];
    final w = _words[i];
    return [
      TextSpan(text: _verse.substring(0, w.sourceStart)),
      TextSpan(
        text: _verse.substring(w.sourceStart, w.sourceEnd),
        style: TextStyle(backgroundColor: accent.withValues(alpha: _highlightAlpha)),
      ),
      TextSpan(text: _verse.substring(w.sourceEnd)),
    ];
  }
}
