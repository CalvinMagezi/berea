import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'attributions_screen.dart';
import 'listen.dart';
import 'listen_voice.dart';
import 'notebooks_screen.dart';
import 'terms.dart';
import 'theme.dart';

/// Decimal megabytes, as download sizes are published.
const _bytesPerMb = 1000 * 1000;

/// About what the A32 took for the script and the voice together; shown before a start.
const listenWaitWords = 'about 20 to 30 minutes on a phone, a few on a laptop';

/// A single-narrator deep dive of a notebook: the voice download, the render, and the player.
class ListenScreen extends StatefulWidget {
  final AppState state;
  final int notebookId;
  final String title;
  const ListenScreen({
    super.key,
    required this.state,
    required this.notebookId,
    required this.title,
  });

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  AppState get _s => widget.state;

  // Built once: it reads every verse's words, so a rebuild must not repeat it.
  late final StudyPacket _packet = _s.studyPacket(widget.notebookId);
  late final ListenPlan _plan = ListenWriter(
    _s.db,
    _s.systemPrompt,
    _s.settings.tier,
  ).plan(_packet);
  late final String _key = _s.listenKey(_packet);
  late final ListenStore _store = _s.listenStore(widget.notebookId);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Listen')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: ListenableBuilder(
          listenable: Listenable.merge([_s, ?_s.listenJob]),
          builder: (context, _) =>
              ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: _body(context)),
        ),
      ),
    ),
  );

  List<Widget> _body(BuildContext context) {
    if (_plan.beats.isEmpty) return const [_Muted(listenNothing)];
    final job = _s.listenJob;
    final mine = job != null && job.notebookId == widget.notebookId;
    if (mine && job.running) return [_Progress(job: job)];
    final busyWith = job != null && job.running ? job.notebookTitle : null;
    final done = _store.finished(_key);
    final player = done == null
        ? const <Widget>[]
        : [
            _Player(key: ValueKey(done.length), audio: done.audio.path, length: done.length),
            if (!done.current)
              const _Muted('Made before this notebook changed. A new deep dive replaces it.'),
            _Script(beats: done.script),
          ];
    if (done != null && done.current) {
      return [
        ...player,
        if (busyWith == null && _s.voiceReady)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _remake, child: const Text('Make it again')),
          ),
      ];
    }
    return [
      if (mine && job.stage == ListenStage.failed) _Muted(job.status, error: true),
      if (!_s.voiceReady)
        _VoiceSetup(state: _s)
      else
        _Start(
          plan: _plan,
          onStart: _start,
          resumes: _store.unfinished(_key),
          busyWith: busyWith,
          stale: done != null,
        ),
      if (player.isNotEmpty) const SizedBox(height: 24),
      ...player,
    ];
  }

  void _start() => unawaited(_s.makeDeepDive(widget.notebookId, widget.title));

  void _remake() {
    _store.clear();
    _start();
  }
}

class _Start extends StatelessWidget {
  final ListenPlan plan;
  final VoidCallback onStart;
  final bool resumes;

  /// A deep dive made before the notebook changed is kept until this one is made.
  final bool stale;

  /// The notebook a deep dive is being made for, when it is another one.
  final String? busyWith;
  const _Start({
    required this.plan,
    required this.onStart,
    required this.resumes,
    required this.busyWith,
    required this.stale,
  });

  @override
  Widget build(BuildContext context) {
    final busy = busyWith;
    final minutes = (listenWords / listenWordsPerMinute).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A deep dive of this notebook, read by one narrator, about $minutes minutes long. The '
          'helper writes it part by part from the notebook\'s passages, word studies and '
          'commentary, and every verse it quotes is checked against the Bible. Then the voice '
          'reads it aloud on this device.',
        ),
        const SizedBox(height: 8),
        _Muted(
          'Making it takes $listenWaitWords. You can keep using Berea: questions in Study are '
          'answered between parts, and the helper rests while the voice reads.',
        ),
        if (!plan.walksAll)
          _Muted(
            'This notebook is long, so the deep dive walks through ${plan.walkedVerses} of its '
            '${plural(plan.totalVerses, 'verse', 'verses')}, from the start.',
          ),
        const SizedBox(height: 16),
        if (busy != null)
          _Muted('Berea is making a deep dive of $busy. One is made at a time.')
        else
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.headphones_outlined),
            label: Text(
              resumes
                  ? 'Continue the deep dive'
                  : (stale ? 'Make a new deep dive' : 'Make the deep dive'),
            ),
          ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  final ListenJob job;
  const _Progress({required this.job});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(job.status, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      LinearProgressIndicator(value: job.fraction),
      const SizedBox(height: 12),
      _Muted(
        job.stage == ListenStage.writing
            ? 'You can keep using Berea. Questions in Study are answered between parts.'
            : 'You can keep using Berea. The helper rests until the recording is done.',
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: job.stopping ? null : job.stop, child: const Text('Stop')),
      ),
    ],
  );
}

class _VoiceSetup extends StatelessWidget {
  final AppState state;
  const _VoiceSetup({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final mb = (voiceBytes / _bytesPerMb).round();
    final received = s.voiceReceived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Listen needs a voice', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Supertonic 3 reads deep dives aloud on this device. It is a $mb MB download, once. '
          'Nothing you write leaves the device.',
        ),
        const SizedBox(height: 8),
        const _Muted(
          'The voice comes under the BigScience Open RAIL-M License. By downloading it you agree '
          'to its use restrictions, which are part of Berea\'s terms.',
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const TermsScreen())),
              child: const Text('Terms of use'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const AttributionsScreen())),
              child: const Text('Licences and sources'),
            ),
          ],
        ),
        if (s.voiceError case final e?) _Muted(e, error: true),
        const SizedBox(height: 8),
        if (received != null) ...[
          LinearProgressIndicator(value: received / voiceBytes),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${(received / _bytesPerMb).round()} of $mb MB'),
              const Spacer(),
              TextButton(onPressed: s.stopVoiceDownload, child: const Text('Pause')),
            ],
          ),
        ] else
          FilledButton(onPressed: s.downloadListenVoice, child: const Text('Agree and download')),
      ],
    );
  }
}

class _Player extends StatefulWidget {
  final String audio;
  final Duration length;
  const _Player({super.key, required this.audio, required this.length});

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<Object?>>[];
  var _at = Duration.zero;
  var _playing = false;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.onPositionChanged.listen((p) => setState(() => _at = p)))
      ..add(
        _player.onPlayerStateChanged.listen(
          (s) => setState(() => _playing = s == PlayerState.playing),
        ),
      );
  }

  /// The file is opened on the first Play, so opening the screen does not load the recording.
  var _opened = false;

  Future<void> _play() async {
    if (_opened) return _player.resume();
    _opened = true;
    await _player.play(DeviceFileSource(widget.audio), position: _at);
  }

  Future<void> _seek(Duration to) async {
    setState(() => _at = to);
    if (_opened) await _player.seek(to);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.length.inMilliseconds.toDouble();
    final at = _at.inMilliseconds.clamp(0, widget.length.inMilliseconds).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton.filled(
                  tooltip: _playing ? 'Pause' : 'Play',
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () => _playing ? _player.pause() : _play(),
                ),
                Expanded(
                  child: Slider(
                    value: at,
                    max: total,
                    onChanged: (v) => _seek(Duration(milliseconds: v.round())),
                  ),
                ),
                Text('${clockOf(_at)} / ${clockOf(widget.length)}'),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: _Muted('Machine generated: written and read aloud by Berea on this device.'),
            ),
          ],
        ),
      ),
    );
  }
}

/// [d] as minutes and seconds, such as 8:05.
String clockOf(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % Duration.secondsPerMinute).toString().padLeft(2, '0')}';

class _Script extends StatelessWidget {
  final List<ScriptBeat> beats;
  const _Script({required this.beats});

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Script'),
    subtitle: const Text('What was read, with the verses and sources it cites'),
    children: [
      for (final b in beats)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(b.text),
              if (b.sources.isNotEmpty) ...[
                const SizedBox(height: 4),
                _Muted(b.sources.join('\n')),
              ],
            ],
          ),
        ),
    ],
  );
}

class _Muted extends StatelessWidget {
  final String text;
  final bool error;
  const _Muted(this.text, {this.error = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: TextStyle(color: error ? scheme.error : scheme.onSurfaceVariant)),
    );
  }
}

/// The notebook's Listen button. While its deep dive is made a ring around it fills, and its
/// tooltip says how far along it is.
class ListenButton extends StatelessWidget {
  final AppState state;
  final int notebookId;
  final String title;
  const ListenButton({
    super.key,
    required this.state,
    required this.notebookId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, ?state.listenJob]),
    builder: (context, _) {
      final job = state.listenJob;
      final running = job != null && job.running && job.notebookId == notebookId;
      return IconButton(
        tooltip: running ? 'Listen: ${job.status}' : 'Listen',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ListenScreen(state: state, notebookId: notebookId, title: title),
          ),
        ),
        icon: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.headphones_outlined),
            if (running)
              SizedBox.square(
                dimension: _ringSize,
                child: CircularProgressIndicator(value: job.fraction, strokeWidth: _ringStroke),
              ),
          ],
        ),
      );
    },
  );
}

const _ringSize = 34.0;
const _ringStroke = 2.0;
