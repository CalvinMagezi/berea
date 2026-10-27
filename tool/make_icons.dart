// Regenerates every platform launcher icon from the Berea mark in site/index.html.
// Run from the repository root: flutter test tool/make_icons.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// The favicon's own colours, not the app theme's, so the mark does not move when the theme does.
const _tileColor = ui.Color(0xFF9E7628);
const _strokeColor = ui.Color(0xFFF6F1E8);

const _unit = 32.0;
const _strokeWidth = 2.4;
const _tileRadius = 7.0;
const _markPathData = 'M9 8h9a5 5 0 0 1 0 10H9zM9 18h10a5 5 0 0 1 0 10H9z';

/// Apple's macOS template: the tile is 824 of 1024 px, centred on a transparent canvas.
const _macosMargin = 100 / 1024;

const _androidViewport = 108.0;

/// Keeps the stroked mark inside the 66dp circle that launcher masks never crop.
const _androidMarkScale = 2.2;
const _androidLegacySizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
const _icoSizes = [16, 24, 32, 48, 64, 128, 256];

const _androidRes = 'android/app/src/main/res';
const _iosSet = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _macosSet = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
const _windowsIco = 'windows/runner/resources/app_icon.ico';

/// square: full bleed, opaque, for iOS (the OS rounds it). rounded: the favicon tile. macos: inset tile.
enum _Shape { square, rounded, macos }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('regenerate launcher icons', () async {
    final mark = _parseMark(_markPathData);
    final cache = <(int, _Shape), Uint8List>{};

    Future<Uint8List> render(int px, _Shape shape) async =>
        cache[(px, shape)] ??= await _rgba(mark, px, shape);

    Future<void> writePng(String path, int px, _Shape shape, {required bool alpha}) async {
      final png = _png(await render(px, shape), px, alpha: alpha);
      File(path).writeAsBytesSync(png);
    }

    for (final (set, shape, alpha) in [
      (_iosSet, _Shape.square, false),
      (_macosSet, _Shape.macos, true),
    ]) {
      for (final image in _catalogImages(set)) {
        await writePng('$set/${image.file}', image.px, shape, alpha: alpha);
      }
    }

    for (final MapEntry(:key, :value) in _androidLegacySizes.entries) {
      await writePng(
        '$_androidRes/mipmap-$key/ic_launcher.png',
        value,
        _Shape.rounded,
        alpha: true,
      );
    }
    _writeAndroidAdaptive(mark);

    final icoImages = [
      for (final px in _icoSizes) (px, _png(await render(px, _Shape.rounded), px, alpha: true)),
    ];
    File(_windowsIco).writeAsBytesSync(_ico(icoImages));
  });
}

typedef _CatalogImage = ({String file, int px});

/// Files an asset catalog expects, with their pixel size (points times scale).
List<_CatalogImage> _catalogImages(String set) {
  final contents =
      jsonDecode(File('$set/Contents.json').readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final image in contents['images'] as List<dynamic>)
      if (image['filename'] case final String file)
        (
          file: file,
          px:
              (double.parse((image['size'] as String).split('x').first) *
                      int.parse((image['scale'] as String).replaceAll('x', '')))
                  .round(),
        ),
  ];
}

/// Reads the path commands the mark uses (M, h, H, a, z) so the SVG string stays the one source.
ui.Path _parseMark(String data) {
  final tokens = RegExp(r'[MhHaz]|-?\d+(?:\.\d+)?').allMatches(data).map((m) => m[0]!).toList();
  final path = ui.Path();
  var i = 0;
  double number() => double.parse(tokens[i++]);
  var x = 0.0;
  var y = 0.0;
  while (i < tokens.length) {
    switch (tokens[i++]) {
      case 'M':
        x = number();
        y = number();
        path.moveTo(x, y);
      case 'h':
        x += number();
        path.lineTo(x, y);
      case 'H':
        x = number();
        path.lineTo(x, y);
      case 'a':
        final rx = number();
        final ry = number();
        final rotation = number();
        final largeArc = number() == 1;
        final sweep = number() == 1;
        x += number();
        y += number();
        path.arcToPoint(
          ui.Offset(x, y),
          radius: ui.Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: largeArc,
          clockwise: sweep,
        );
      case 'z':
        path.close();
      case final command:
        throw FormatException('Unsupported path command $command');
    }
  }
  return path;
}

Future<Uint8List> _rgba(ui.Path mark, int px, _Shape shape) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final inset = shape == _Shape.macos ? px * _macosMargin : 0.0;
  final side = px - 2 * inset;
  final scale = side / _unit;
  final tile = ui.Rect.fromLTWH(inset, inset, side, side);
  final fill = ui.Paint()..color = _tileColor;
  if (shape == _Shape.square) {
    canvas.drawRect(tile, fill);
  } else {
    canvas.drawRRect(ui.RRect.fromRectXY(tile, _tileRadius * scale, _tileRadius * scale), fill);
  }
  canvas
    ..translate(inset, inset)
    ..scale(scale)
    ..drawPath(
      mark,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeJoin = ui.StrokeJoin.miter
        ..color = _strokeColor,
    );
  final image = await recorder.endRecording().toImage(px, px);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return data!.buffer.asUint8List();
}

void _writeAndroidAdaptive(ui.Path mark) {
  final center = mark.getBounds().center;
  final dx = _androidViewport / 2 - center.dx * _androidMarkScale;
  final dy = _androidViewport / 2 - center.dy * _androidMarkScale;
  final stroke = _hex(_strokeColor);
  final foreground =
      '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/make_icons.dart. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="${_androidViewport.round()}dp"
    android:height="${_androidViewport.round()}dp"
    android:viewportWidth="$_androidViewport"
    android:viewportHeight="$_androidViewport">
    <group
        android:scaleX="$_androidMarkScale"
        android:scaleY="$_androidMarkScale"
        android:translateX="${dx.toStringAsFixed(2)}"
        android:translateY="${dy.toStringAsFixed(2)}">
        <path
            android:pathData="$_markPathData"
            android:strokeColor="$stroke"
            android:strokeWidth="$_strokeWidth" />
    </group>
</vector>
''';
  const adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/make_icons.dart. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
''';
  final background =
      '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/make_icons.dart. -->
<resources>
    <color name="ic_launcher_background">${_hex(_tileColor)}</color>
</resources>
''';
  Directory('$_androidRes/mipmap-anydpi-v26').createSync(recursive: true);
  File('$_androidRes/drawable/ic_launcher_foreground.xml').writeAsStringSync(foreground);
  File('$_androidRes/mipmap-anydpi-v26/ic_launcher.xml').writeAsStringSync(adaptive);
  File('$_androidRes/values/ic_launcher_background.xml').writeAsStringSync(background);
}

String _hex(ui.Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// A PNG writer so iOS icons can drop the alpha channel, which `dart:ui` always keeps.
Uint8List _png(Uint8List rgba, int px, {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  final rowBytes = 1 + px * channels;
  final raw = Uint8List(px * rowBytes);
  for (var y = 0; y < px; y++) {
    var pos = y * rowBytes + 1;
    for (var x = 0; x < px; x++) {
      final i = (y * px + x) * 4;
      for (var c = 0; c < channels; c++) {
        raw[pos++] = rgba[i + c];
      }
    }
  }
  final out = BytesBuilder()..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(body)
      ..add((ByteData(4)..setUint32(0, _crc(body))).buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, px)
    ..setUint32(4, px)
    ..setUint8(8, 8)
    ..setUint8(9, alpha ? 6 : 2);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder(level: 9).convert(raw));
  chunk('IEND', const []);
  return out.toBytes();
}

/// An ICO container holding PNG payloads, which Windows 10 and later read at every size.
Uint8List _ico(List<(int, Uint8List)> images) {
  const headerSize = 6;
  const entrySize = 16;
  final out = BytesBuilder();
  final header = ByteData(headerSize)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  out.add(header.buffer.asUint8List());
  var offset = headerSize + entrySize * images.length;
  for (final (px, png) in images) {
    final entry = ByteData(entrySize)
      ..setUint8(0, px >= 256 ? 0 : px)
      ..setUint8(1, px >= 256 ? 0 : px)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, png.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    out.add(entry.buffer.asUint8List());
    offset += png.length;
  }
  for (final (_, png) in images) {
    out.add(png);
  }
  return out.toBytes();
}
