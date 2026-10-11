import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

void main() {
  test('USFM: strips notes, word attributes, headings and joins contractions', () {
    const usfm = r'''
\id JHN 43-JHN-web.sfm World English Bible
\h John
\mt1 John
\c 1
\s1 The Word
\p
\v 1 \w In|strong="G1722"\w* the beginning was the \w Word|strong="G3056"\w*.
\v 2 The darkness hasn’\w t|strong="G3588"\w* overcome\f + \fr 1:5 \ft a note \f* it.
\v 3-4 Joined verses \wj spoken\wj*.
\c 2
\v 1 Second chapter.
''';
    final rows = parseUsfm(usfm);
    expect(rows.map((r) => '${r.book.name} ${r.chapter}:${r.verse} ${r.text}'), [
      'John 1:1 In the beginning was the Word.',
      'John 1:2 The darkness hasn’t overcome it.',
      'John 1:3 Joined verses spoken.',
      'John 2:1 Second chapter.',
    ]);
    expect(
      parseUsfm(
        r'\id TOB Tobit'
        '\n'
        r'\c 1'
        '\n'
        r'\v 1 x',
      ),
      isEmpty,
    );
  });

  test('OSIS container and milestone verses, notes skipped', () {
    const container =
        '<osis><div><verse osisID="Gen.1.1">In the <note>n</note>beginning.</verse>'
        '<verse osisID="Gen.1.2">Void &amp; dark.</verse></div></osis>';
    const milestone =
        '<osis><verse sID="Gen.1.1" osisID="Gen.1.1"/>In the beginning.'
        '<verse eID="Gen.1.1"/><verse sID="Gen.1.2" osisID="Gen.1.2"/>Void.<verse eID="Gen.1.2"/></osis>';
    expect(parseOsis(container).map((r) => r.text), ['In the beginning.', 'Void & dark.']);
    expect(parseOsis(milestone).map((r) => '${r.chapter}:${r.verse} ${r.text}'), [
      '1:1 In the beginning.',
      '1:2 Void.',
    ]);
  });

  test('Zefania', () {
    const xml =
        '<XMLBIBLE><BIBLEBOOK bnumber="43" bname="John"><CHAPTER cnumber="3">'
        '<VERS vnumber="16">For God so loved<NOTE>x</NOTE> the world.</VERS></CHAPTER></BIBLEBOOK></XMLBIBLE>';
    final r = parseZefania(xml).single;
    expect(
      '${r.book.name} ${r.chapter}:${r.verse} ${r.text}',
      'John 3:16 For God so loved the world.',
    );
  });

  test('zip with deflated USFM entries', () {
    final dir = Directory.systemTemp.createTempSync('berea_zip');
    File(
      '${dir.path}/43-JHNtest.usfm',
    ).writeAsStringSync('\\id JHN\n\\c 1\n\\v 1 In the beginning.\n');
    final zip = '${dir.path}/b.zip';
    final res = Process.runSync('zip', ['-q', '-j', zip, '${dir.path}/43-JHNtest.usfm']);
    if (res.exitCode != 0) return markTestSkipped('zip tool not available');
    final rows = parseBibleFile('b.zip', Uint8List.fromList(File(zip).readAsBytesSync()));
    expect(rows.single.text, 'In the beginning.');
    expect(utf8.decode(readZip(File(zip).readAsBytesSync()).values.single), contains(r'\id JHN'));
    dir.deleteSync(recursive: true);
  });
}
