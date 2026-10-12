import 'dart:io';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

/// Every chunk is exactly the slice its offsets name, in order, within the size limit.
void expectWellFormed(ChunkedText c) {
  var previousEnd = 0;
  for (var i = 0; i < c.chunks.length; i++) {
    final chunk = c.chunks[i];
    expect(chunk.ordinal, i);
    expect(chunk.start, greaterThanOrEqualTo(previousEnd));
    expect(c.text.substring(chunk.start, chunk.end), chunk.text);
    expect(chunk.text.length, lessThanOrEqualTo(notebookChunkChars));
    expect(chunk.text.trim(), chunk.text);
    expect(chunk.text, isNotEmpty);
    previousEnd = chunk.end;
  }
}

void main() {
  test('short text is one chunk with offsets into the normalised text', () {
    final c = chunkSections(['  In the beginning\r\nwas   the Word.  \r\n\r\n\r\n\r\nAmen. ']);
    expect(c.text, 'In the beginning\nwas the Word.\n\nAmen.');
    expect(c.chunks.single.start, 0);
    expect(c.chunks.single.end, c.text.length);
    expect(c.chunks.single.page, isNull);
  });

  test('long text breaks at paragraphs, then sentences, then spaces, never mid word', () {
    final sentence = 'The steadfast love of the Lord never ceases. ';
    final paragraphs = List.filled(12, sentence * 6).join('\n\n');
    final c = chunkSections([paragraphs]);
    expectWellFormed(c);
    expect(c.chunks.length, greaterThan(1));
    expect(c.chunks.every((k) => k.text.endsWith('.')), isTrue);
    final words = chunkSections([List.filled(800, 'mercy').join(' ')]);
    expectWellFormed(words);
    expect(words.chunks.every((k) => k.text.split(' ').every((w) => w == 'mercy')), isTrue);
    final stream = chunkSections(['x' * 3000]);
    expectWellFormed(stream);
    expect(stream.chunks.map((k) => k.text.length), [1200, 1200, 600]);
  });

  test('a cut never splits a surrogate pair', () {
    final c = chunkSections(['a${'😀' * 1000}']);
    expectWellFormed(c);
    for (final k in c.chunks) {
      expect(k.text.runes.every((r) => r != 0xFFFD && (r < 0xD800 || r > 0xDFFF)), isTrue);
    }
  });

  test('pages keep their numbers, empty pages count, and no chunk crosses a page', () {
    final page = List.filled(40, 'Grace upon grace.').join(' ');
    final c = chunkSections([page, '   ', 'Third page.', page], paged: true);
    expectWellFormed(c);
    expect(c.chunks.map((k) => k.page).toSet(), {1, 3, 4});
    final third = c.chunks.singleWhere((k) => k.page == 3);
    expect(third.text, 'Third page.');
    for (final k in c.chunks.where((k) => k.page == 1)) {
      expect(k.end, lessThanOrEqualTo(c.text.indexOf('Third')));
    }
  });

  test('empty and oversized sources are refused', () {
    expect(() => chunkSections(['  ', '\n']), throwsFormatException);
    expect(() => chunkSections([]), throwsFormatException);
    final big = 'word ' * (maxNotebookSourceChars ~/ 5);
    expect(() => chunkSections([big, big]), throwsFormatException);
  });

  test('HTML becomes plain text with breaks at blocks', () {
    const html =
        '<html><head><title>T</title><style>p{}</style></head><body>'
        '<h1>Romans&#160;8</h1><p>No <i>condemnation</i> &amp; no fear.</p><!-- x -->'
        '<script>alert(1)</script><ul><li>One</li><li>Two</li></ul></body></html>';
    expect(htmlPlainText(html), 'Romans 8\n\nNo condemnation & no fear.\n\nOne\n\nTwo');
  });

  test('EPUB sections follow the spine, resolve relative paths and skip encrypted files', () {
    final dir = Directory.systemTemp.createTempSync('berea_epub');
    addTearDown(() => dir.deleteSync(recursive: true));
    void write(String path, String text) => File('${dir.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    write('mimetype', 'application/epub+zip');
    write(
      'META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OEBPS/content.opf" '
          'media-type="application/oebps-package+xml"/></rootfiles></container>',
    );
    write(
      'OEBPS/content.opf',
      '<package><manifest>'
          '<item id="c2" href="text/ch%202.xhtml" media-type="application/xhtml+xml"/>'
          '<item href="text/ch1.xhtml#top" id="c1" media-type="application/xhtml+xml"/>'
          '<item id="locked" href="../locked.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c1"/>'
          '<itemref idref="locked"/><itemref idref="missing"/></spine></package>',
    );
    write('OEBPS/text/ch1.xhtml', '<html><body><p>Chapter one.</p></body></html>');
    write('OEBPS/text/ch 2.xhtml', '<html><body><p>Chapter two.</p></body></html>');
    write('locked.xhtml', 'ciphertext');
    write(
      'META-INF/encryption.xml',
      "<encryption><CipherReference URI='locked.xhtml'/><CipherReference URI=\"X/OEBPS/text/ch 2.xhtml\"/>",
    );
    final zip = '${dir.path}/book.epub';
    final res = Process.runSync('zip', [
      '-q',
      '-r',
      zip,
      'mimetype',
      'META-INF',
      'OEBPS',
      'locked.xhtml',
    ], workingDirectory: dir.path);
    if (res.exitCode != 0) return markTestSkipped('zip tool not available');
    final bytes = Uint8List.fromList(File(zip).readAsBytesSync());
    expect(epubSections(bytes), ['Chapter one.', 'Chapter two.']);
    expect(() => epubSections(Uint8List.fromList('not a zip'.codeUnits)), throwsFormatException);
  });

  test('search queries quote every word, keep Bible names and accents, and defuse operators', () {
    expect(notebookFtsQuery('God so loved'), '"god" OR "so" OR "loved"');
    expect(notebookFtsQuery('Ἰησοῦς χάρις café'), '"ἰησοῦς" OR "χάρις" OR "café"');
    expect(notebookFtsQuery('"AND" (NEAR -x*'), '"and" OR "near" OR "x"');
    expect(notebookFtsQuery('  ?! '), isNull);
    expect(notebookFtsQuery('שָׁלוֹם'), '"שָׁלוֹם"');
    expect(
      notebookFtsQuery(List.generate(40, (i) => 'w$i').join(' '))!.split(' OR ').length,
      maxNotebookQueryTerms,
    );
  });

  test('hostile markup is stripped in linear time', () {
    const size = 400000;
    final watch = Stopwatch()..start();
    for (final unit in ['<', '<item ', '<!--', '<nav>', '<script x="', '<p ']) {
      htmlPlainText(unit * (size ~/ unit.length));
    }
    // Quadratic matching took seconds for a fiftieth of this input.
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(htmlPlainText('<p>Kept</p><script>never closed <p>gone?'), 'Kept\nnever closed\ngone?');
    expect(htmlPlainText('a<!-- open comment b'), 'a');
    expect(
      htmlPlainText('<body><script src="a.js"/><p>Real text</p><script>var x;</script></body>'),
      'Real text',
    );
  });

  test('EPUB with odd hrefs and look-alike attributes reads what it can', () {
    final dir = Directory.systemTemp.createTempSync('berea_epub_odd');
    addTearDown(() => dir.deleteSync(recursive: true));
    void write(String path, String text) => File('${dir.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    write('META-INF/container.xml', "<container><rootfile full-path='content.opf'/></container>");
    write(
      'content.opf',
      '<package><manifest>'
          '<item data-id="x" id="good" href="good.xhtml"/>'
          '<item id="bad" href="bad%zz.xhtml"/>'
          '</manifest><spine><itemref idref="bad"/><itemref idref="good"/></spine></package>',
    );
    write('good.xhtml', '<p>Readable.</p>');
    write('cover.png', 'not text, never inflated');
    final zip = '${dir.path}/odd.epub';
    final res = Process.runSync('zip', [
      '-q',
      '-r',
      zip,
      'META-INF',
      'content.opf',
      'good.xhtml',
      'cover.png',
    ], workingDirectory: dir.path);
    if (res.exitCode != 0) return markTestSkipped('zip tool not available');
    expect(epubSections(Uint8List.fromList(File(zip).readAsBytesSync())), ['Readable.']);
  });

  test('an EPUB document too large for a source is refused before it is decoded', () {
    final dir = Directory.systemTemp.createTempSync('berea_epub_big');
    addTearDown(() => dir.deleteSync(recursive: true));
    void write(String path, String text) => File('${dir.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    write('META-INF/container.xml', '<rootfile full-path="book.opf"/>');
    write('book.opf', '<item id="big" href="big.xhtml"/><itemref idref="big"/>');
    write('big.xhtml', 'a' * (maxEpubDocumentBytes + 1));
    final zip = '${dir.path}/big.epub';
    final res = Process.runSync('zip', [
      '-q',
      '-r',
      zip,
      'META-INF',
      'book.opf',
      'big.xhtml',
    ], workingDirectory: dir.path);
    if (res.exitCode != 0) return markTestSkipped('zip tool not available');
    expect(
      () => epubSections(Uint8List.fromList(File(zip).readAsBytesSync())),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('too large'))),
    );
  });
}
