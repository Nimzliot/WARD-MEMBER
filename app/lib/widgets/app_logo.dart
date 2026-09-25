import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// App name, used on the intro, login and headers.
const kAppName = 'Makkal Budget';

/// Makkal Budget mark: a temple-style arched gateway (thoranam) over a ballot
/// box, with a vote going in and three kolam dots in the arch.
/// Original artwork — deliberately not the Tamil Nadu state emblem.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 56,
    this.color = AppColors.forest,
    this.accent = AppColors.emerald,
    this.background = Colors.white,
  });

  final double size;
  final Color color; // arch + ballot box
  final Color accent; // vote card + kolam dots
  final Color background; // the ballot-box slot is cut out in this colour

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: AppLogoPainter(color: color, accent: accent, background: background),
      );
}

class AppLogoPainter extends CustomPainter {
  AppLogoPainter({required this.color, required this.accent, required this.background});

  final Color color;
  final Color accent;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;

    // Mandapam gateway: two pillars joined by a rounded arch.
    final arch = Path()
      ..moveTo(0.17 * w, 0.84 * h)
      ..lineTo(0.17 * w, 0.42 * h)
      ..arcTo(Rect.fromLTRB(0.17 * w, 0.22 * h, 0.83 * w, 0.62 * h), math.pi, math.pi, false)
      ..lineTo(0.83 * w, 0.84 * h)
      ..lineTo(0.73 * w, 0.84 * h)
      ..lineTo(0.73 * w, 0.42 * h)
      ..arcTo(Rect.fromLTRB(0.27 * w, 0.31 * h, 0.73 * w, 0.53 * h), 0, -math.pi, false)
      ..lineTo(0.27 * w, 0.84 * h)
      ..close();
    canvas.drawPath(arch, fill);

    // Pillar capitals
    for (final x in [0.14, 0.70]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x * w, 0.44 * h, 0.16 * w, 0.04 * h), Radius.circular(0.012 * w)),
        fill,
      );
    }

    // Cornice over the arch
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(0.11 * w, 0.17 * h, 0.89 * w, 0.235 * h), Radius.circular(0.02 * w)),
      fill,
    );

    // Three kalasam pots on the cornice (centre one taller)
    for (final (x, big) in [(0.28, false), (0.5, true), (0.72, false)]) {
      final r = (big ? 0.042 : 0.032) * w;
      final base = 0.17 * h;
      canvas.drawCircle(Offset(x * w, base - r * 0.8), r, fill);
      final tip = Path()
        ..moveTo(x * w - r * 0.55, base - r * 1.3)
        ..lineTo(x * w, base - r * (big ? 3.1 : 2.7))
        ..lineTo(x * w + r * 0.55, base - r * 1.3)
        ..close();
      canvas.drawPath(tip, fill);
    }

    // Base step
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(0.1 * w, 0.84 * h, 0.9 * w, 0.9 * h), Radius.circular(0.02 * w)),
      fill,
    );

    // Three kolam dots inside the arch
    final dot = Paint()..color = accent;
    for (final x in [0.42, 0.5, 0.58]) {
      canvas.drawCircle(p(x, 0.44), 0.022 * w, dot);
    }

    // Vote card entering the box (drawn first so the box covers its lower half)
    canvas.save();
    canvas.translate(0.5 * w, 0.57 * h);
    canvas.rotate(-math.pi / 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 0.16 * w, height: 0.13 * h), Radius.circular(0.018 * w)),
      Paint()..color = accent,
    );
    canvas.restore();

    // Ballot box with its slot
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(0.34 * w, 0.61 * h, 0.66 * w, 0.8 * h), Radius.circular(0.03 * w)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(0.4 * w, 0.645 * h, 0.6 * w, 0.67 * h), Radius.circular(0.01 * w)),
      Paint()..color = background,
    );
  }

  @override
  bool shouldRepaint(AppLogoPainter old) =>
      old.color != color || old.accent != accent || old.background != background;
}
