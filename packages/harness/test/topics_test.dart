import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    "Torrey's references: a book carries over, a bare number after a comma is a verse",
    () {
      final unread = <String>[];
      final refs = parseTorreyRefs(
        'Joh 10:7,9; 14:6; Ro 5:2; Ps 23; Jude 5; Isa 1:1-2:3',
        unread,
        'T',
      );
      String show(TopicRef r) => topicRefLabel(r);
      expect(refs.map(show), [
        'John 10:7',
        'John 10:9',
        'John 14:6',
        'Romans 5:2',
        'Psalms 23',
        'Jude 1:5',
        'Isaiah 1:1-2:3',
      ]);
      expect(unread, isEmpty);
    },
  );

  test(
    'a reference nobody can read is reported and does not stop the topic',
    () {
      final unread = <String>[];
      final refs = parseTorreyRefs('Ro 5:2; Zz 1:1', unread, 'T');
      expect(refs, hasLength(1));
      expect(unread, ['T: Zz 1:1']);
    },
  );

  test("Nave's lines keep the author's subheading and the passages after it", () {
    final r = parseNave(
      'ABANA',
      '<entryFree n="ABANA">\n<def>\n<lb/>→ River of Damascus <ref osisRef="2Kgs.5.12">2Ki 5:12</ref>'
          '<lb/>→ Children of <ref osisRef="Exod.6.23">Ex 6:23</ref>,<ref osisRef="1Chr.6.3-1Chr.6.15">1Ch 6:3-15</ref>'
          '<lb/>See CARE </def>\n</entryFree>',
    );
    final lines = r.topics.single.lines;
    expect(lines.map((l) => l.label), [
      'River of Damascus',
      'Children of',
      'See CARE',
    ]);
    expect(lines[0].refs.single, (
      book: 12,
      chapter: 5,
      verse: 12,
      verseEnd: 12,
      chapterEnd: 5,
    ));
    expect(lines[1].refs.map(topicRefLabel), [
      'Exodus 6:23',
      '1 Chronicles 6:3-15',
    ]);
    expect(lines[2].refs, isEmpty);
    expect(r.unread, isEmpty);
  });

  test("a Nave line with several items becomes one line for each, with only the author's words", () {
    final r = parseNave(
      'X',
      '<entryFree n="X"><def><lb/>INSTANCES OF Esau forgives Jacob <ref osisRef="Gen.33.4">Ge 33:4</ref>,'
      '<ref osisRef="Gen.33.11">11</ref>; Joseph forgives his brothers <ref osisRef="Gen.50.15">Ge 50:15</ref>;'
      ' </def></entryFree>',
    );
    final lines = r.topics.single.lines;
    expect(lines.map((l) => l.label), ['INSTANCES OF Esau forgives Jacob', 'Joseph forgives his brothers']);
    expect(lines.map((l) => l.refs.length), [2, 1]);
  });

  test(
    'a topics pack attaches, is searched by the words of a name, and is read back line by line',
    () {
      final raw = sqlite3.openInMemory();
      final dir = Directory.systemTemp.createTempSync('berea_topics');
      addTearDown(() => dir.deleteSync(recursive: true));
      sqlite3.open('${dir.path}/t.sqlite')
        ..execute('''
        CREATE TABLE topics(id INTEGER PRIMARY KEY, work TEXT, name TEXT);
        CREATE TABLE topic_lines(topic_id INTEGER, ord INTEGER, label TEXT, refs TEXT, PRIMARY KEY(topic_id, ord));
        INSERT INTO topics VALUES (1, 'Nave', 'Fear'), (2, 'Torrey', 'Fear of God'), (3, 'Nave', 'Anxiety'), (4, 'Nave', 'Godly Fear');
        INSERT INTO topic_lines VALUES (1, 0, 'See COWARDICE', ''), (1, 1, 'Fear of the wicked', '19:14:1:1:14'),
          (2, 0, 'Is a duty', '5:6:2:2:6;19:111:10:10:111');
      ''')
        ..dispose();
      final db = BibleDb(raw);
      expect(db.searchTopics('fear'), isEmpty, reason: 'nothing attached yet');
      expect(db.attachTopics('${dir.path}/t.sqlite'), isTrue);
      expect(db.searchTopics('fear').map((t) => t.name), [
        'Fear',
        'Fear of God',
        'Godly Fear',
      ]);
      expect(db.searchTopics('fear of').map((t) => t.name), ['Fear of God']);
      expect(db.searchTopics('anx').single.name, 'Anxiety');
      expect(db.searchTopics('zzz'), isEmpty);
      final lines = db.topicLines(2);
      expect(lines.single.label, 'Is a duty');
      expect(lines.single.refs.map(topicRefLabel), [
        'Deuteronomy 6:2',
        'Psalms 111:10',
      ]);
      expect(db.topicsNamed('FEAR').map((t) => t.work), ['Nave']);
      expect(
        db.searchTopics('fear').first.lines,
        1,
        reason: 'one line of Fear has passages',
      );
    },
  );
}
