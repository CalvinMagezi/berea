import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// The booklets Berea carries, each a plain markdown file under assets/booklets/. The text is
/// the booklet's own, shown whole. Berea adds only the labels in this file.
const bookletAssets = [
  'assets/booklets/building-the-inner-city-of-god.md',
  'assets/booklets/three-ways-we-fall.md',
];

/// Said where a booklet is shown. It claims no author: the files do not record one, and a line
/// `author:` in a booklet's front matter is shown beside this when one is added.
const bookletLabel = 'Included by Berea’s maintainer. Not Scripture, and not written by Berea.';

/// Where the prayers on the Prayer place come from.
const bookletPrayersSelector = 'Chosen by Berea’s maintainer from the booklets built in.';

const _wordsPerMinute = 200;

/// Bold (two asterisks) and italic (one) marks in a booklet's text.
final bookletInline = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
final _heading = RegExp(r'^(#{3,4})\s+(.+)$');
final _sectionId = RegExp(r'^(.*?)\s*\{#([a-z0-9-]+)\}\s*$');

/// [s] without its bold and italic marks.
String plainInline(String s) => s.replaceAllMapped(bookletInline, (m) => m[1] ?? m[2]!);

int _wordCount(String s) => s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

/// One block of a booklet's text. The shapes are the few the two booklets use.
sealed class BookletBlock {
  const BookletBlock();

  /// The block as plain text, for a notebook copy and for counting words. Empty for a note of
  /// Berea's own, which is not the booklet's text.
  String get plain;
}

/// A heading inside a section: level 3 is a part, level 4 a small label.
class BookletHeading extends BookletBlock {
  final int level;
  final String text;
  const BookletHeading(this.level, this.text);
  @override
  String get plain => plainInline(text);
}

class BookletParagraph extends BookletBlock {
  final String text;
  const BookletParagraph(this.text);
  @override
  String get plain => plainInline(text);
}

/// A quotation, usually Scripture as the booklet gives it, with the reference it names.
class BookletQuote extends BookletBlock {
  final String text;
  final String? cite;
  const BookletQuote(this.text, this.cite);
  @override
  String get plain => cite == null ? plainInline(text) : '${plainInline(text)}\n— $cite';
}

class BookletList extends BookletBlock {
  final List<String> items;
  const BookletList(this.items);
  @override
  String get plain => items.map(plainInline).join('\n');
}

/// A boxed passage with a title of its own, such as "Name it, without excuses".
class BookletCallout extends BookletBlock {
  final String title;
  final String text;
  const BookletCallout(this.title, this.text);
  @override
  String get plain => '$title\n${plainInline(text)}';
}

/// A line from Berea about how the booklet is shown. Not part of the booklet's text.
class BookletNote extends BookletBlock {
  final String text;
  const BookletNote(this.text);
  @override
  String get plain => '';
}

/// Reads the blocks of a section's body. Throws [FormatException] on a block it does not know,
/// so a mistyped marker fails a test instead of showing as stray text.
List<BookletBlock> parseBookletBlocks(String body) {
  final lines = body.split('\n');
  final out = <BookletBlock>[];
  var i = 0;
  bool special(String l) =>
      l.trim().isEmpty ||
      _heading.hasMatch(l) ||
      l.startsWith(':::') ||
      l.startsWith('>') ||
      l.startsWith('- ');
  while (i < lines.length) {
    final line = lines[i].trimRight();
    if (line.trim().isEmpty) {
      i++;
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      out.add(BookletHeading(heading[1]!.length, heading[2]!.trim()));
      i++;
    } else if (line.startsWith(':::')) {
      final kind = line.substring(3).trim();
      final inner = <String>[];
      i++;
      while (i < lines.length && lines[i].trim() != ':::') {
        inner.add(lines[i].trim());
        i++;
      }
      if (i >= lines.length) throw FormatException('A "$kind" block is never closed.');
      i++;
      final text = inner.where((l) => l.isNotEmpty).join(' ');
      if (kind == 'berea') {
        out.add(BookletNote(text));
      } else if (kind.startsWith('callout ')) {
        out.add(BookletCallout(kind.substring('callout '.length).trim(), text));
      } else {
        throw FormatException('Unknown booklet block "$kind".');
      }
    } else if (line.startsWith('>')) {
      final quoted = <String>[];
      while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
        quoted.add(lines[i].trimLeft().substring(1).trim());
        i++;
      }
      String? cite;
      if (quoted.isNotEmpty && quoted.last.startsWith('— ')) {
        cite = quoted.removeLast().substring(2).trim();
      }
      out.add(BookletQuote(quoted.join(' '), cite));
    } else if (line.startsWith('- ')) {
      final items = <String>[];
      while (i < lines.length && lines[i].startsWith('- ')) {
        items.add(lines[i].substring(2).trim());
        i++;
      }
      out.add(BookletList(items));
    } else {
      final para = <String>[];
      while (i < lines.length && !special(lines[i])) {
        para.add(lines[i].trim());
        i++;
      }
      out.add(BookletParagraph(para.join(' ')));
    }
  }
  return out;
}

class BookletSection {
  /// A short name that stays the same if the heading is reworded, so reading progress keeps.
  final String id;
  final String title;
  final List<BookletBlock> blocks;
  const BookletSection(this.id, this.title, this.blocks);

  String get plainText => [
    plainInline(title),
    for (final b in blocks)
      if (b.plain.isNotEmpty) b.plain,
  ].join('\n\n');

  int get words => _wordCount(plainText);

  /// The blocks under the level 3 heading [heading], up to the next one; null when there is no
  /// such heading.
  List<BookletBlock>? part(String heading) {
    final start = blocks.indexWhere(
      (b) => b is BookletHeading && b.level == 3 && b.text == heading,
    );
    if (start < 0) return null;
    var end = blocks.length;
    for (var i = start + 1; i < blocks.length; i++) {
      final b = blocks[i];
      if (b is BookletHeading && b.level == 3) {
        end = i;
        break;
      }
    }
    return blocks.sublist(start + 1, end);
  }
}

class Booklet {
  final String id;
  final String title;

  /// The title without its subtitle, for tight places.
  final String short;
  final String subtitle;

  /// Who wrote it, when the file says. Null when it does not.
  final String? author;
  final List<BookletSection> sections;
  const Booklet({
    required this.id,
    required this.title,
    required this.short,
    required this.subtitle,
    this.author,
    required this.sections,
  });

  /// Reads a booklet file: front matter (`key: value` lines between two `---` lines), then
  /// sections that start with `## Title {#id}`.
  factory Booklet.parse(String source) {
    final text = source.replaceAll('\r\n', '\n');
    if (!text.startsWith('---\n')) {
      throw const FormatException('A booklet starts with front matter.');
    }
    final end = text.indexOf('\n---\n', 4);
    if (end < 0) throw const FormatException('A booklet\'s front matter is never closed.');
    final meta = <String, String>{};
    for (final line in text.substring(4, end).split('\n')) {
      final at = line.indexOf(': ');
      if (at > 0) meta[line.substring(0, at).trim()] = line.substring(at + 2).trim();
    }
    for (final required in ['id', 'title', 'short', 'subtitle']) {
      if ((meta[required] ?? '').isEmpty) throw FormatException('A booklet has no $required.');
    }
    final sections = <BookletSection>[];
    String? id;
    String? title;
    var body = StringBuffer();
    void flush() {
      final t = title;
      if (t == null) return;
      sections.add(BookletSection(id!, t, parseBookletBlocks(body.toString())));
    }

    for (final line in text.substring(end + 5).split('\n')) {
      if (line.startsWith('## ')) {
        flush();
        final m = _sectionId.firstMatch(line.substring(3).trim());
        if (m == null) throw FormatException('A section has no id: $line');
        title = m[1]!.trim();
        id = m[2]!;
        body = StringBuffer();
      } else {
        body.writeln(line);
      }
    }
    flush();
    final ids = sections.map((s) => s.id).toList();
    if (ids.toSet().length != ids.length) {
      throw FormatException('Two sections share an id in ${meta['id']}.');
    }
    if (sections.isEmpty) throw FormatException('${meta['id']} has no sections.');
    return Booklet(
      id: meta['id']!,
      title: meta['title']!,
      short: meta['short']!,
      subtitle: meta['subtitle']!,
      author: meta['author'],
      sections: sections,
    );
  }

  /// The booklet's own words as plain text, for a notebook source: the title, the subtitle and
  /// every section. Berea's notes are left out.
  String get plainText => [title, subtitle, for (final s in sections) s.plainText].join('\n\n');

  int get words => sections.fold(0, (n, s) => n + s.words);

  /// Reading time at 200 words a minute, rounded up.
  int get minutes => (words / _wordsPerMinute).ceil();

  BookletSection? section(String id) => sections.where((s) => s.id == id).firstOrNull;

  /// The line a notebook source keeps under its title, saying where the words came from.
  String get origin => '$short · $bookletLabel';
}

/// The booklets Berea carries, read from the app's assets. A file that does not read is left
/// out and reported to the console, so a bad file never stops Berea opening.
Future<List<Booklet>> loadBooklets([AssetBundle? bundle]) async {
  final source = bundle ?? rootBundle;
  final out = <Booklet>[];
  for (final path in bookletAssets) {
    try {
      out.add(Booklet.parse(await source.loadString(path)));
    } on Object catch (e) {
      debugPrint('A booklet did not load: $path: $e');
    }
  }
  return out;
}

/// A prayer taken from a booklet: a whole section, or the part of one under a level 3 heading.
/// The words are the booklet's; this only says which stretch of them.
class BookletPrayerRef {
  final String booklet;
  final String section;
  final String? part;
  const BookletPrayerRef(this.booklet, this.section, [this.part]);
}

/// The prayers on the Prayer place, chosen by Berea's maintainer: the booklet that has a prayer
/// section, and the stretches of the other that give words to say or a daily rhythm of prayer.
const bookletPrayerRefs = [
  BookletPrayerRef('three-ways', 'prayer'),
  BookletPrayerRef('inner-city', 'surveying-the-land', 'Simple Everyday Practice'),
  BookletPrayerRef(
    'inner-city',
    'stage-5',
    '12. Keeping the Sanctuary Fire Ablaze: A Simple Daily & Lifetime Maintenance Rhythm',
  ),
];

class BookletPrayer {
  final Booklet booklet;
  final BookletSection section;
  final String? part;
  const BookletPrayer(this.booklet, this.section, this.part);

  /// The booklet's own heading for it.
  String get title => part ?? section.title;

  /// Where it sits in the booklet.
  String get where => part == null ? booklet.short : '${booklet.short} · ${section.title}';

  List<BookletBlock> get blocks => part == null ? section.blocks : section.part(part!)!;
}

/// The prayers whose booklet and place are found, in the order of [bookletPrayerRefs].
List<BookletPrayer> bookletPrayers(List<Booklet> booklets) => [
  for (final r in bookletPrayerRefs)
    if (booklets.where((b) => b.id == r.booklet).firstOrNull case final b?)
      if (b.section(r.section) case final s?)
        if (r.part == null || s.part(r.part!) != null) BookletPrayer(b, s, r.part),
];

/// Which sections of each booklet have been read, and which booklets are being read as plans.
/// Kept in the app's preferences: on this device only, and not in a backup.
class BookletReading extends ChangeNotifier {
  final SharedPreferences prefs;
  BookletReading(this.prefs);

  static const _startedKey = 'bookletsStarted';
  static String _readKey(String id) => 'bookletRead:$id';

  List<String> get started => prefs.getStringList(_startedKey) ?? const [];

  bool isStarted(String id) => started.contains(id);

  /// Section ids read in booklet [id].
  Set<String> read(String id) => {...?prefs.getStringList(_readKey(id))};

  bool isRead(String booklet, String section) => read(booklet).contains(section);

  /// Sections of [b] read, counting only sections the booklet still has.
  int readCount(Booklet b) {
    final done = read(b.id);
    return b.sections.where((s) => done.contains(s.id)).length;
  }

  /// The first section not yet read, in the booklet's order; null once every one is.
  BookletSection? next(Booklet b) {
    final done = read(b.id);
    return b.sections.where((s) => !done.contains(s.id)).firstOrNull;
  }

  /// Starting keeps sections already read, as stopping a Bible plan keeps its ticks.
  void start(String id) {
    if (!isStarted(id)) unawaited(prefs.setStringList(_startedKey, [...started, id]));
    notifyListeners();
  }

  void stop(String id) {
    unawaited(prefs.setStringList(_startedKey, [...started.where((s) => s != id)]));
    notifyListeners();
  }

  /// Clears what was read and begins again from the first section.
  void startOver(String id) {
    unawaited(prefs.remove(_readKey(id)));
    start(id);
  }

  void setRead(String booklet, String section, bool done) {
    final now = read(booklet);
    if (done ? !now.add(section) : !now.remove(section)) return;
    unawaited(prefs.setStringList(_readKey(booklet), now.toList()));
    notifyListeners();
  }
}
