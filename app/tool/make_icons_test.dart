// Generates the Android launcher icons and web icons from the Nam Nagaram logo
// (assets/brand/logo.png).
//   cd app && flutter test tool/make_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

late ui.Image _logo;

Future<void> _write(String path, int px, void Function(Canvas c, double s) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  draw(canvas, px.toDouble());
  final img = await rec.endRecording().toImage(px, px);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// Draws the logo centred at [scale] of the canvas (its own white background blends in).
void _logoAt(Canvas c, double s, double scale) {
  final side = s * scale;
  final dst = Rect.fromCenter(center: Offset(s / 2, s / 2), width: side, height: side);
  c.drawImageRect(
    _logo,
    Rect.fromLTWH(0, 0, _logo.width.toDouble(), _logo.height.toDouble()),
    dst,
    Paint()..filterQuality = FilterQuality.high,
  );
}

void _whiteRounded(Canvas c, double s) =>
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22)), Paint()..color = Colors.white);

void main() {
  test('launcher + web icons', () async {
    final codec = await ui.instantiateImageCodec(File('assets/brand/logo.png').readAsBytesSync());
    _logo = (await codec.getNextFrame()).image;

    for (final e in _densities.entries) {
      // Legacy: white rounded square with the round logo
      await _write('$_res/mipmap-${e.key}/ic_launcher.png', (48 * e.value).round(), (c, s) {
        _whiteRounded(c, s);
        _logoAt(c, s, 0.92);
      });
      // Adaptive foreground: 108dp canvas, logo inside the 66dp safe zone (background is white)
      await _write('$_res/mipmap-${e.key}/ic_launcher_foreground.png', (108 * e.value).round(),
          (c, s) => _logoAt(c, s, 0.66));
    }

    void rounded(Canvas c, double s) {
      _whiteRounded(c, s);
      _logoAt(c, s, 0.92);
    }

    void fullBleed(Canvas c, double s) {
      c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = Colors.white);
      _logoAt(c, s, 0.72);
    }

    await _write('web/favicon.png', 64, rounded);
    await _write('web/icons/Icon-192.png', 192, rounded);
    await _write('web/icons/Icon-512.png', 512, rounded);
    await _write('web/icons/Icon-maskable-192.png', 192, fullBleed);
    await _write('web/icons/Icon-maskable-512.png', 512, fullBleed);
  });
}
