// Builds the optional topics pack: Nave's Topical Bible (1903) and Torrey's New Topical Textbook
// (1897) from their CrossWire SWORD modules, each topic a list of passages under its author's
// name. Both modules state "Public Domain" in their own conf files. Not bundled; the app downloads
// it when the user asks.
// Usage: dart run bin/build_topics_pack.dart [--out ../../build/topics.sqlite] [--cache .cache]
import 'dart:io';

import 'package:berea_harness/src/topics.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

const _naveZip =
    'https://crosswire.org/ftpmirror/pub/sword/packages/rawzip/Nave.zip';
const _naveSha256 =
    '52d9b7cde04c2abb5187ae804bcb97d93c7344a1358539f50ebc178ac0c945f0';
const _torreyZip =
    'https://crosswire.org/ftpmirror/pub/sword/packages/rawzip/Torrey.zip';
const _torreySha256 =
    '9db6e3f1720f868cc9d68cf030db53d157f9726883f0afd49553d05ab4cb7c80';

/// Entries a build may fail to read before it stops: a single odd reference is reported, a parser
/// that has stopped understanding the file is not.
const _maxUnreadShare = 0.002;

Future<void> main(List<String> args) async {
  final out = _arg(args, '--out') ?? '../../build/topics.sqlite';
  final cache = _arg(args, '--cache') ?? '.cache';
  Directory(cache).createSync(recursive: true);
  final nave = await _unzip('$cache/Nave', _naveZip, _naveSha256);
  final torrey = await _unzip('$cache/Torrey', _torreyZip, _torreySha256);

  final topics = <(String, Topic)>[];
  final unread = <String>[];
  for (final e in readZLd('$nave/modules/lexdict/zld/nave/dict').entries) {
    final r = parseNave(e.key, e.value);
    unread.addAll(r.unread);
    for (final t in r.topics) {
      if (t.lines.isNotEmpty) topics.add(('Nave', t));
    }
  }
  final base = '$torrey/modules/lexdict/rawld/torrey/torrey';
  for (final entry in readRawLd('$base.idx', '$base.dat')) {
    final r = parseTorrey(entry);
    unread.addAll(r.unread);
    for (final t in r.topics) {
      if (t.lines.isNotEmpty) topics.add(('Torrey', t));
    }
  }

  var refs = 0;
  for (final (_, t) in topics) {
    for (final l in t.lines) {
      refs += l.refs.length;
    }
  }
  stdout.writeln(
    'topics: ${topics.length}, passages: $refs, not read: ${unread.length}',
  );
  for (final u in unread.take(15)) {
    stdout.writeln('  not read: $u');
  }
  if (unread.length > refs * _maxUnreadShare) {
    throw StateError(
      'Too many references could not be read (${unread.length} of $refs).',
    );
  }

  Directory(File(out).parent.path).createSync(recursive: true);
  if (File(out).existsSync()) File(out).deleteSync();
  final db = sqlite3.open(out);
  db.execute('''
    CREATE TABLE topics(id INTEGER PRIMARY KEY, work TEXT, name TEXT);
    CREATE INDEX topics_name ON topics(name COLLATE NOCASE);
    CREATE TABLE topic_lines(topic_id INTEGER, ord INTEGER, label TEXT, refs TEXT, PRIMARY KEY(topic_id, ord)) WITHOUT ROWID;
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  ''');
  final addTopic = db.prepare('INSERT INTO topics(work, name) VALUES (?, ?)');
  final addLine = db.prepare('INSERT INTO topic_lines VALUES (?, ?, ?, ?)');
  db.execute('BEGIN');
  for (final (work, t) in topics) {
    addTopic.execute([work, _titleCase(t.name)]);
    final id = db.lastInsertRowId;
    for (var i = 0; i < t.lines.length; i++) {
      addLine.execute([
        id,
        i,
        t.lines[i].label,
        encodeTopicRefs(t.lines[i].refs),
      ]);
    }
  }
  db.execute('COMMIT');
  addTopic.dispose();
  addLine.dispose();
  const meta = {
    'nave':
        "Nave's Topical Bible, Orville J. Nave, 1903. SWORD module Nave 3.0 (CrossWire), Public Domain.",
    'torrey':
        "Torrey's New Topical Textbook, R. A. Torrey, 1897. SWORD module Torrey 1.3 (CrossWire), Public Domain.",
    'changes':
        'Tags removed and each reference parsed into a book, chapter and verses by Berea; the authors\' words are as the modules print them.',
  };
  for (final e in meta.entries) {
    db.execute('INSERT INTO meta VALUES (?, ?)', [e.key, e.value]);
  }
  db.execute('VACUUM');
  db.dispose();
  stdout.writeln('wrote $out (${(File(out).lengthSync() / 1024).round()} KB)');
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

String _titleCase(String s) => s
    .split(' ')
    .map(
      (w) =>
          w.length <= 3 &&
              w == w.toUpperCase() &&
              !RegExp(r'^[IVX]+$').hasMatch(w)
          ? w.toLowerCase()
          : (w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()),
    )
    .join(' ');

Future<String> _unzip(String dir, String url, String sha) async {
  final zip = File('$dir.zip');
  if (!zip.existsSync()) {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} for $url');
    zip.writeAsBytesSync(r.bodyBytes);
  }
  final got = (await Process.run('shasum', [
    '-a',
    '256',
    zip.path,
  ])).stdout.toString().split(' ').first;
  if (got != sha) {
    throw StateError('SHA-256 mismatch for ${zip.path}: pinned $sha, got $got');
  }
  if (!Directory(dir).existsSync()) {
    final u = await Process.run('unzip', ['-o', '-q', zip.path, '-d', dir]);
    if (u.exitCode != 0) throw StateError('unzip failed: ${u.stderr}');
  }
  return dir;
}
