// Builds the commentary packs from public domain CrossWire SWORD modules. The modules are read
// by a pure Dart zCom reader (lib/src/sword.dart); libsword (GPL) is never used. Each pack is a
// SQLite file, gzipped for download, listed in manifest.json with its SHA-256.
// Usage: dart run bin/build_commentary.dart [--packs core,mhc] [--out ../../build/commentary]
//        [--bible ../../assets/berea.sqlite] [--cache .cache/sword]
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/src/commentary.dart';
import 'package:berea_harness/src/sword.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

const _rawzip = 'https://crosswire.org/ftpmirror/pub/sword/packages/rawzip';
const _kjvChapters = 1189;
const _kjvVerses = 31102;
const _gzipLevel = 9;
const _blockLetters = {'BOOK': 'b', 'CHAPTER': 'c', 'VERSE': 'v'};

/// SWORD's default when a conf has no BlockType.
const _defaultBlockType = 'CHAPTER';

Future<void> main(List<String> args) async {
  var out = '../../build/commentary';
  var bible = '../../assets/berea.sqlite';
  var cache = '.cache/sword';
  var packs = [for (final p in commentaryPackSpecs) p.id];
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--out') out = args[i + 1];
    if (args[i] == '--bible') bible = args[i + 1];
    if (args[i] == '--cache') cache = args[i + 1];
    if (args[i] == '--packs') packs = args[i + 1].split(',');
  }
  Directory(out).createSync(recursive: true);
  Directory(cache).createSync(recursive: true);
  final v11n = _kjvVersification(bible);
  int versesIn(int book, int chapter) => v11n[book - 1][chapter - 1];

  final manifest = <Map<String, Object>>[];
  for (final id in packs) {
    final spec = commentaryPackSpecs.firstWhere(
      (p) => p.id == id,
      orElse: () => throw ArgumentError('Unknown pack $id'),
    );
    final modules = <String, (ConvertedModule, String)>{};
    for (final m in spec.modules) {
      modules[m] = await _convert(m, cache, v11n, versesIn);
    }
    manifest.add(_writePack('$out/${spec.fileName}', spec, modules));
  }
  File('$out/manifest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'format': commentaryPackFormat, 'packs': manifest}),
  );
  stdout.writeln('wrote $out/manifest.json');
}

/// Verse counts per chapter from the KJV in the Bible database; SWORD modules are KJV keyed.
Versification _kjvVersification(String path) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final v11n = [
      for (var b = 1; b <= otBookCount + ntBookCount; b++)
        [
          for (final r in db.select(
            "SELECT COUNT(*) AS n FROM verses WHERE translation = 'KJV' AND book = ? "
            'GROUP BY chapter ORDER BY chapter',
            [b],
          ))
            r['n'] as int,
        ],
    ];
    final chapters = v11n.fold<int>(0, (n, b) => n + b.length);
    final verses = v11n.fold<int>(0, (n, b) => n + b.fold<int>(0, (m, c) => m + c));
    if (chapters != _kjvChapters || verses != _kjvVerses) {
      throw StateError('$path has $chapters KJV chapters and $verses verses; run build_db first.');
    }
    return v11n;
  } finally {
    db.dispose();
  }
}

/// Downloads and unpacks [module], checks its licence and layout, and converts it. Returns the
/// rows with the module's version.
Future<(ConvertedModule, String)> _convert(
  String module,
  String cache,
  Versification v11n,
  int Function(int, int) versesIn,
) async {
  final dir = '$cache/$module';
  final zip = File('$cache/$module.zip');
  if (!zip.existsSync()) {
    stdout.writeln('downloading $module');
    final r = await http.get(Uri.parse('$_rawzip/$module.zip'));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} for $module');
    zip.writeAsBytesSync(r.bodyBytes);
  }
  final unzip = await Process.run('unzip', ['-o', '-q', zip.path, '-d', dir]);
  if (unzip.exitCode != 0) throw StateError('unzip $module failed: ${unzip.stderr}');
  final conf = parseSwordConf(
    Directory('$dir/mods.d').listSync().whereType<File>().single.readAsStringSync(),
  );
  final licence = conf['DistributionLicense'];
  if (licence != 'Public Domain') throw StateError('$module is "$licence", not Public Domain');
  final v = conf['Versification'] ?? 'KJV';
  if (v != 'KJV') throw StateError('$module uses $v versification, not KJV');
  final driver = (conf['ModDrv'] ?? '').toLowerCase();
  if (driver != 'zcom' && driver != 'zcom4') throw StateError('$module uses $driver, not zCom');
  final letter = _blockLetters[(conf['BlockType'] ?? _defaultBlockType).toUpperCase()]!;
  final data = '$dir/${conf['DataPath']!.replaceFirst(RegExp(r'^\./'), '')}';
  final raw = [
    for (final nt in [false, true])
      ...readTestament(
        '$data${nt ? 'nt' : 'ot'}',
        letter,
        testamentSlots(v11n, newTestament: nt),
        zCom4: driver == 'zcom4',
      ),
  ];
  final converted = convertSwordEntries(commentaryModuleById(module)!, raw, versesIn);
  final rows = converted.entries;
  stdout.writeln(
    '$module ${conf['Version']}: ${rows.length} rows, '
    '${rows.where((e) => e.verseEnd > e.verseStart).length} ranged, '
    '${rows.where((e) => e.isIntroduction).length} introductions, '
    '${converted.headingDisagreements} range headings that disagree with SWORD links, '
    '${converted.clampedLinks} links cut back to the verses the comment names',
  );
  return (converted, conf['Version'] ?? '');
}

/// Writes one pack, gzips it, and returns its manifest entry. Nothing time-dependent goes in,
/// so the same sources always give the same bytes and the published SHA-256 can be rebuilt.
Map<String, Object> _writePack(
  String path,
  CommentaryPackSpec spec,
  Map<String, (ConvertedModule, String)> modules,
) {
  if (File(path).existsSync()) File(path).deleteSync();
  final db = sqlite3.open(path);
  db.execute('PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;');
  db.execute(commentaryPackSchema);
  final addModule = db.prepare('INSERT INTO modules VALUES (?, ?, ?, ?, ?, ?)');
  final addEntry = db.prepare(
    'INSERT INTO entries(module, book, chapter, verse_start, verse_end, html_or_text) '
    'VALUES (?, ?, ?, ?, ?, ?)',
  );
  var count = 0;
  db.execute('BEGIN');
  for (final MapEntry(key: id, value: (converted, version)) in modules.entries) {
    final m = commentaryModuleById(id)!;
    final source = '${m.source} $id $version, $_rawzip/$id.zip';
    addModule.execute([id, m.title, m.author, m.licence, source, commentaryModules.indexOf(m)]);
    for (final e in converted.entries) {
      addEntry.execute([e.module, e.book, e.chapter, e.verseStart, e.verseEnd, e.text]);
      count++;
    }
  }
  db.execute('COMMIT');
  addModule.dispose();
  addEntry.dispose();
  db.execute("INSERT INTO entries_fts(entries_fts) VALUES('rebuild')");
  final versions = [for (final e in modules.entries) '${e.key} ${e.value.$2}'].join(', ');
  db.execute('INSERT INTO meta VALUES (?, ?), (?, ?), (?, ?)', [
    'format',
    commentaryPackFormat,
    'pack',
    spec.id,
    'sources',
    versions,
  ]);
  db.execute('VACUUM');
  db.dispose();

  final raw = File(path).readAsBytesSync();
  final gz = GZipCodec(level: _gzipLevel).encode(raw);
  File('$path.gz').writeAsBytesSync(gz);
  final sha = sha256.convert(gz).toString();
  stdout.writeln(
    '${spec.fileName}: $count entries, ${_mb(raw.length)} MB, '
    '${_mb(gz.length)} MB gzipped, sha256 $sha',
  );
  return {
    'id': spec.id,
    'title': spec.title,
    'modules': spec.modules,
    'file': '${spec.fileName}.gz',
    'bytes': gz.length,
    'unpacked_bytes': raw.length,
    'entries': count,
    'sha256': sha,
    'sources': versions,
  };
}

String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);
