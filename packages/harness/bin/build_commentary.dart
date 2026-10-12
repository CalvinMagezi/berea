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
const _bytesPerMb = 1024 * 1024;

/// SHA-256 of each CrossWire module zip the published packs were built from, so a republished
/// module fails the build instead of silently changing a pack.
const _moduleZipSha256 = {
  'Barnes': '9e8edc0333875c214124371b3862df118ad3a76ade7753cb2faeed3484615baf',
  'CalvinCommentaries': 'df66fc8c03537499ad006d069481d2c95b600887cdbd6ce75ec5d264b573192a',
  'Catena': 'b48c9d75bbc142a9bf4f4e078026d049e386e27a263169f26dca112dde619918',
  'Clarke': '56bb33d3bf0f50c1609f4dd10ac81e7450bb0e8aae93bf340074ccb5e207a44f',
  'JFB': '7704d71f9efa1423fb45b3caf966c78daae698bd39b5a26f9e772f12e2098265',
  'KD': 'ca3bdb6a04c0b717ee2faed71b432d58195db96f217f490ce6f7d9c36a2876f7',
  'MHC': '6bcb936873ca144e317805e5c1677940fd86e2403f7c14517752e44f25c8882b',
  'MHCC': 'e7c742e1c0154f52740e6e0af39dc506f77606bd7747e307303fd9933037dae7',
  'TDavid': 'd0081cba094f399ceb95f372e13068a4d76814de4529bc6794eab0f2ed6e89cc',
  'TSK': '6784c7099465995a8e66f02ead82b0bca66603c1bdeaf8332949774b7bfd4293',
  'Wesley': 'd4423b084bfc2a4dd00f7ed0b2004113d62010317ddb14a62c1b31801fff360e',
};

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

/// Fetches [module] at its pinned hash, checks its licence and layout, and converts it.
Future<(ConvertedModule, String)> _convert(
  String module,
  String cache,
  Versification v11n,
  int Function(int, int) versesIn,
) async {
  final zip = await _pinnedZip(module, cache);
  final dir = Directory('$cache/$module');
  // Unpacked fresh each time so no file from an older zip can be read.
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final unzip = await Process.run('unzip', ['-q', zip.path, '-d', dir.path]);
  if (unzip.exitCode != 0) {
    throw StateError('unzip $module failed: ${unzip.stderr}');
  }
  final conf = checkModuleConf(
    module,
    parseSwordConf(
      Directory('${dir.path}/mods.d').listSync().whereType<File>().single.readAsStringSync(),
    ),
  );
  final raw = [
    for (final nt in [false, true])
      ...readTestament(
        '${dir.path}/${conf.dataPath}${nt ? 'nt' : 'ot'}',
        conf.blockLetter,
        testamentSlots(v11n, newTestament: nt),
        zCom4: conf.zCom4,
      ),
  ];
  final converted = convertSwordEntries(commentaryModuleById(module)!, raw, versesIn);
  final rows = converted.entries;
  stdout.writeln(
    '$module ${conf.version}: ${rows.length} rows, '
    '${rows.where((e) => e.verseEnd > e.verseStart).length} ranged, '
    '${rows.where((e) => e.isIntroduction).length} introductions, '
    '${converted.headingDisagreements} range headings that disagree with SWORD links, '
    '${converted.clampedLinks} links cut back to the verses the comment names',
  );
  return (converted, conf.version);
}

/// The module zip from the cache, downloaded if needed, after its SHA-256 matches the pin.
Future<File> _pinnedZip(String module, String cache) async {
  final pin = _moduleZipSha256[module];
  if (pin == null) throw StateError('$module has no pinned SHA-256');
  final zip = File('$cache/$module.zip');
  if (!zip.existsSync()) {
    stdout.writeln('downloading $module');
    final r = await http.get(Uri.parse('$_rawzip/$module.zip'));
    if (r.statusCode != 200) {
      throw StateError('HTTP ${r.statusCode} for $module');
    }
    _checkZipPin(module, r.bodyBytes, pin);
    final part = File('${zip.path}.part')..writeAsBytesSync(r.bodyBytes);
    part.renameSync(zip.path);
  }
  _checkZipPin(module, zip.readAsBytesSync(), pin);
  return zip;
}

void _checkZipPin(String module, List<int> bytes, String pin) {
  final actual = sha256.convert(bytes).toString();
  if (actual == pin) return;
  throw StateError(
    '$module.zip has SHA-256 $actual, pinned $pin. CrossWire republished it: review the module, '
    'then update the pin and the pack pins.',
  );
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

String _mb(int bytes) => (bytes / _bytesPerMb).toStringAsFixed(1);
