import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Civic look for Tamil Nadu: tricolour strip, kolam patterns and the app's own
/// kolam mark. Deliberately NOT the state emblem — this is a prototype, not an
/// official Government of Tamil Nadu service (see [PrototypeNotice]).

const kAuthorityLine = 'NAM NAGARAM · PARTICIPATORY BUDGETING';

/// Thin saffron / white / green strip, as on Indian public-service portals.
class TricolourStrip extends StatelessWidget {
  const TricolourStrip({super.key, this.height = 4});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: const Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: ColoredBox(color: Color(0xFFFF9933))),
          Expanded(child: ColoredBox(color: Colors.white)),
          Expanded(child: ColoredBox(color: Color(0xFF138808))),
        ]),
      );
}

/// Pulli kolam: a dot grid with loops drawn around the dots, tiled as a
/// background texture (white, very low contrast on the green headers).
class KolamPatternPainter extends CustomPainter {
  KolamPatternPainter({this.color = Colors.white, this.opacity = 0.09, this.cell = 26});

  final Color color;
  final double opacity;
  final double cell; // distance between dots

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = color.withValues(alpha: opacity * 1.6);
    final line = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final r = cell / 2;
    for (var y = 0.0; y < size.height + cell; y += cell) {
      for (var x = 0.0; x < size.width + cell; x += cell) {
        final c = Offset(x, y);
        canvas.drawCircle(c, 1.6, dot);
        // alternate loops: diamond petals around even dots, circles around odd ones
        final odd = ((x / cell).round() + (y / cell).round()).isOdd;
        if (odd) {
          canvas.drawCircle(c, r * 0.62, line);
        } else {
          final p = Path()
            ..moveTo(x, y - r)
            ..quadraticBezierTo(x + r * 0.15, y - r * 0.15, x + r, y)
            ..quadraticBezierTo(x + r * 0.15, y + r * 0.15, x, y + r)
            ..quadraticBezierTo(x - r * 0.15, y + r * 0.15, x - r, y)
            ..quadraticBezierTo(x - r * 0.15, y - r * 0.15, x, y - r);
          canvas.drawPath(p, line);
        }
      }
    }
  }

  @override
  bool shouldRepaint(KolamPatternPainter old) => old.opacity != opacity || old.color != color || old.cell != cell;
}

/// The app's own mark: a 3×3 pulli kolam inside a ring. [progress] 0..1 draws
/// it stroke by stroke (used by the intro); 1 = complete.
class KolamMark extends StatelessWidget {
  const KolamMark({super.key, this.size = 22, this.color = Colors.white, this.progress = 1});

  final double size;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _KolamMarkPainter(color: color, progress: progress));
}

class _KolamMarkPainter extends CustomPainter {
  _KolamMarkPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, s * 0.055);

    // outer ring
    final ringT = (progress / 0.35).clamp(0.0, 1.0);
    canvas.drawArc(Rect.fromCircle(center: c, radius: s * 0.46), -math.pi / 2, 2 * math.pi * ringT, false, stroke);

    // 3×3 dots
    final g = s * 0.2;
    final dotsT = ((progress - 0.25) / 0.25).clamp(0.0, 1.0);
    final dot = Paint()..color = color.withValues(alpha: dotsT);
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        canvas.drawCircle(c + Offset(i * g, j * g), s * 0.035 * dotsT + 0.01, dot);
      }
    }

    // one continuous loop weaving around the dots (a diamond of four petals)
    final loopT = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);
    if (loopT > 0) {
      final k = g * 1.45;
      final path = Path()
        ..moveTo(c.dx, c.dy - k)
        ..quadraticBezierTo(c.dx + g * 0.9, c.dy - g * 0.9, c.dx + k, c.dy)
        ..quadraticBezierTo(c.dx + g * 0.9, c.dy + g * 0.9, c.dx, c.dy + k)
        ..quadraticBezierTo(c.dx - g * 0.9, c.dy + g * 0.9, c.dx - k, c.dy)
        ..quadraticBezierTo(c.dx - g * 0.9, c.dy - g * 0.9, c.dx, c.dy - k)
        ..addOval(Rect.fromCircle(center: c, radius: g * 0.55));
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * loopT), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_KolamMarkPainter old) => old.progress != progress || old.color != color;
}

/// Small print that keeps the prototype honest.
class PrototypeNotice extends StatelessWidget {
  const PrototypeNotice({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 13, color: onDark ? Colors.white60 : AppColors.inkMuted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'SDG 11 prototype · not an official Government of Tamil Nadu service',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: onDark ? Colors.white60 : AppColors.inkMuted),
            ),
          ),
        ],
      );
}
