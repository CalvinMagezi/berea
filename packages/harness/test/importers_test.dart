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

  test('USFM with a byte-order mark and an unclosed note keeps its verses', () {
    const usfm =
        '\uFEFF\\id JHN\n\\c 1\n\\v 1 In the beginning\\f + note never closed\n'
        '\\v 2 He was with God.\n';
    final rows = parseUsfm(usfm);
    expect(rows.map((r) => r.text), ['In the beginning + note never closed', 'He was with God.']);
  });

  test('an unclosed note never deletes the verse text after it', () {
    const usfm =
        '\\id GEN\n\\c 1\n\\v 1 In the beginning \\f + \\ft note\n'
        'God created the heavens and the earth.\n\\v 2 Now the earth was formless.\n';
    expect(parseUsfm(usfm).first.text, endsWith('God created the heavens and the earth.'));
  });

  test('OSIS with odd ids and single-quoted attributes', () {
    const xml =
        "<osis><verse osisID='Gen.1.1'>One.</verse>"
        '<verse osisID="Gen.1.2-Gen.1.3">Two and three.</verse>'
        '<verse osisID="Gen.1.4!a">Four.</verse><verse osisID="Gen.x.5">Bad.</verse></osis>';
    expect(parseOsis(xml).map((r) => '${r.verse} ${r.text}'), [
      '1 One.',
      '2 Two and three.',
      '4 Four.',
    ]);
  });

  test('a zip that lies about its size or is damaged is rejected, not inflated', () {
    final dir = Directory.systemTemp.createTempSync('berea_bomb');
    final big = File('${dir.path}/big.usfm')..writeAsBytesSync(List.filled(4 * 1024 * 1024, 0x20));
    final zip = '${dir.path}/b.zip';
    final res = Process.runSync('zip', ['-q', '-j', zip, big.path]);
    if (res.exitCode != 0) return markTestSkipped('zip tool not available');
    final bytes = File(zip).readAsBytesSync();
    // Shrink the declared uncompressed size in the central directory to 16 bytes.
    final central = _indexOf(bytes, [0x50, 0x4b, 0x01, 0x02]);
    ByteData.sublistView(bytes).setUint32(central + 24, 16, Endian.little);
    expect(() => readZip(bytes), throwsFormatException);
    expect(() => readZip(Uint8List.fromList(bytes.sublist(0, 40))), throwsFormatException);
    dir.deleteSync(recursive: true);
  });
}

int _indexOf(List<int> data, List<int> pattern) {
  for (var i = 0; i <= data.length - pattern.length; i++) {
    var ok = true;
    for (var j = 0; j < pattern.length && ok; j++) {
      ok = data[i + j] == pattern[j];
    }
    if (ok) return i;
  }
  return -1;
}
