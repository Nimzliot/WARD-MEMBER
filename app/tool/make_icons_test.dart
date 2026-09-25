// Generates the Android launcher icons from AppLogoPainter.
//   cd app && flutter test tool/make_icons_test.dart
// Writes mipmap-*/ic_launcher.png (legacy, rounded square) and
// mipmap-*/ic_launcher_foreground.png (adaptive icon foreground).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_budget/theme.dart';
import 'package:ward_budget/widgets/app_logo.dart';

const _res = 'android/app/src/main/res';
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

const _bg = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.forest, AppColors.forestDark],
);

final _logo = AppLogoPainter(color: Colors.white, accent: AppColors.leaf, background: AppColors.forest);

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

void _logoAt(Canvas c, double s, double scale) {
  final side = s * scale;
  c.save();
  c.translate((s - side) / 2, (s - side) / 2);
  _logo.paint(c, Size.square(side));
  c.restore();
}

void main() {
  test('launcher icons', () async {
    for (final e in _densities.entries) {
      // Legacy: green rounded square, logo filling ~70%
      final legacy = (48 * e.value).round();
      await _write('$_res/mipmap-${e.key}/ic_launcher.png', legacy, (c, s) {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22));
        c.drawRRect(
          r,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.forest, AppColors.forestDark],
            ).createShader(Rect.fromLTWH(0, 0, s, s)),
        );
        _logoAt(c, s, 0.7);
      });
      // Adaptive foreground: 108dp canvas, logo inside the 66dp safe zone
      final fg = (108 * e.value).round();
      await _write('$_res/mipmap-${e.key}/ic_launcher_foreground.png', fg, (c, s) => _logoAt(c, s, 0.54));
    }

    // Web: favicon + install icons (rounded) + maskable (full-bleed, logo in the safe zone)
    void rounded(Canvas c, double s) {
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22)),
        Paint()..shader = _bg.createShader(Rect.fromLTWH(0, 0, s, s)),
      );
      _logoAt(c, s, 0.7);
    }

    void fullBleed(Canvas c, double s) {
      c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..shader = _bg.createShader(Rect.fromLTWH(0, 0, s, s)));
      _logoAt(c, s, 0.56);
    }

    await _write('web/favicon.png', 64, rounded);
    await _write('web/icons/Icon-192.png', 192, rounded);
    await _write('web/icons/Icon-512.png', 512, rounded);
    await _write('web/icons/Icon-maskable-192.png', 192, fullBleed);
    await _write('web/icons/Icon-maskable-512.png', 512, fullBleed);
  });
}
