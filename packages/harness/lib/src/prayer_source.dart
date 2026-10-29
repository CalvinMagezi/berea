import 'dart:io';

import 'package:yaml/yaml.dart';

import 'books.dart';
import 'prayer_content.dart';
import 'prayer_check.dart';

/// The prayer content as authored in content/prayers, with the flags a release looks at.
class PrayerSource {
  final PrayerContent content;

  /// Names of the units whose `reviewed` flag is not true: topics, plans, chapter books and the
  /// daily lines. A release refuses to ship while this is not empty.
  final List<String> unreviewed;
  const PrayerSource(this.content, this.unreviewed);
}

/// Reads every file under [dir]. Throws [FormatException] naming the file and key when the
/// shape is wrong; whether the lines are acceptable is [checkPrayerContent]'s job.
PrayerSource loadPrayerSource(Directory dir) {
  final unreviewed = <String>[];
  Map<String, Object?> read(File f) {
    final doc = _plain(loadYaml(f.readAsStringSync()));
    if (doc is! Map<String, Object?>) throw FormatException('${f.path}: expected a mapping');
    return doc;
  }

  List<File> files(String sub, [String prefix = '']) {
    final d = sub.isEmpty ? dir : Directory('${dir.path}/$sub');
    if (!d.existsSync()) return [];
    return [
      for (final f in d.listSync().whereType<File>())
        if (f.path.endsWith('.yaml') && f.uri.pathSegments.last.startsWith(prefix)) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  void flag(String name, Map<String, Object?> doc) {
    if (doc['reviewed'] != true) unreviewed.add(name);
  }

  final topics = <PrayerTopic>[];
  final topicsFile = File('${dir.path}/topics.yaml');
  for (final t in _list(read(topicsFile), 'topics', topicsFile.path)) {
    final id = _str(t, 'id');
    flag('topic $id', t);
    topics.add(
      PrayerTopic(id, _str(t, 'group'), _str(t, 'title'), _strList(t, 'words'), _pointList(t)),
    );
  }

  final bibleFile = File('${dir.path}/bible-prayers.yaml');
  final bible = [
    for (final b in _list(read(bibleFile), 'prayers', bibleFile.path))
      BiblePrayer(_str(b, 'id'), _str(b, 'title'), _ref(_str(b, 'ref'))),
  ];

  final chapters = <String, List<PrayerPoint>>{};
  for (final f in files('chapters')) {
    final doc = read(f);
    final book = bookFor(_str(doc, 'book'));
    if (book == null) throw FormatException('${f.path}: unknown book ${doc['book']}');
    flag('chapters ${book.name}', doc);
    final byChapter = doc['chapters'];
    if (byChapter is! Map<String, Object?>) {
      throw FormatException('${f.path}: chapters must be a mapping');
    }
    for (final e in byChapter.entries) {
      final key = PrayerContent.chapterKey(book, int.parse(e.key));
      chapters[key] = _points(e.value, '${f.path} ${e.key}');
    }
  }

  final daily = <String, String>{};
  for (final f in files('', 'daily')) {
    final doc = read(f);
    flag('daily ${f.uri.pathSegments.last}', doc);
    for (final l in _list(doc, 'lines', f.path)) {
      daily[_ref(_str(l, 'ref'))] = _str(l, 'text');
    }
  }

  final plans = <PrayerPlan>[];
  for (final f in files('plans')) {
    final doc = read(f);
    final id = _str(doc, 'id');
    flag('plan $id', doc);
    plans.add(
      PrayerPlan(id, _str(doc, 'title'), _str(doc, 'summary'), doc['fasting'] == true, [
        for (final d in _list(doc, 'days', f.path))
          PlanDay(_str(d, 'title'), _ref(_str(d, 'ref')), d['points'] == null ? [] : _pointList(d)),
      ]),
    );
  }

  return PrayerSource(
    PrayerContent(
      topics: topics,
      biblePrayers: bible,
      chapters: chapters,
      daily: daily,
      plans: plans,
    ),
    unreviewed,
  );
}

/// The compiled file the app bundles, written the same way every time so a stale copy is a diff.
String compilePrayerContent(PrayerContent content) {
  final json = content.toJson();
  return '${_encode(json)}\n';
}

String _encode(Object? v) {
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort(_numeric);
    return '{${[for (final k in keys) '${_encode(k)}:${_encode(v[k])}'].join(',')}}';
  }
  if (v is List) return '[${v.map(_encode).join(',')}]';
  if (v is String) return _quote(v);
  return '$v';
}

int _numeric(String a, String b) {
  final x = a.split('.').map(int.tryParse).toList();
  final y = b.split('.').map(int.tryParse).toList();
  if (x.every((n) => n != null) && y.every((n) => n != null)) {
    for (var i = 0; i < x.length && i < y.length; i++) {
      if (x[i] != y[i]) return x[i]!.compareTo(y[i]!);
    }
    return x.length.compareTo(y.length);
  }
  return a.compareTo(b);
}

String _quote(String s) {
  final b = StringBuffer('"');
  for (final r in s.runes) {
    b.write(switch (r) {
      0x22 => r'\"',
      0x5C => r'\\',
      0x0A => r'\n',
      < 0x20 => '\\u${r.toRadixString(16).padLeft(4, '0')}',
      _ => String.fromCharCode(r),
    });
  }
  return (b..write('"')).toString();
}

/// The canonical label for a written reference, or the text as written when it is not one, so
/// the check can name it.
String _ref(String written) => parseSingleRef(written)?.label ?? written;

Object? _plain(Object? n) {
  if (n is YamlMap) return {for (final e in n.entries) '${e.key}': _plain(e.value)};
  if (n is YamlList) return [for (final v in n) _plain(v)];
  return n;
}

String _str(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! String || v.trim().isEmpty) throw FormatException('missing $key in $m');
  return v.trim();
}

List<String> _strList(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! List) throw FormatException('missing list $key in $m');
  return [for (final s in v) '$s'.trim()];
}

List<Map<String, Object?>> _list(Map<String, Object?> m, String key, String where) {
  final v = m[key];
  if (v is! List) throw FormatException('$where: missing list $key');
  return [for (final e in v) (e as Map).cast<String, Object?>()];
}

List<PrayerPoint> _pointList(Map<String, Object?> m) => _points(m['points'], '${m['id'] ?? m}');

List<PrayerPoint> _points(Object? v, String where) {
  if (v is! List) throw FormatException('$where: points must be a list');
  return [
    for (final p in v)
      PrayerPoint(
        _str((p as Map).cast<String, Object?>(), 'text'),
        _ref(_str(p.cast<String, Object?>(), 'ref')),
      ),
  ];
}
