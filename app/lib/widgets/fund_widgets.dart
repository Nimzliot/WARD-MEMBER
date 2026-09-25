import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/format.dart';

/// Animated ring that fills to [value] (0..1) with the percentage in the middle.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 112, this.stroke = 11, this.child});

  final double value;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(v, stroke),
            child: Center(
              child: child ??
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${(v * 100).round()}%',
                        style: TextStyle(fontSize: size * 0.22, fontWeight: FontWeight.w800, color: AppColors.forestDark)),
                    Icon(_stageIcon(v), size: size * 0.16, color: AppColors.emerald),
                  ]),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke);

  final double v;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, 2 * math.pi, false,
        Paint()
          ..color = AppColors.mint
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    if (v <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      2 * math.pi * v,
      false,
      Paint()
        ..shader = const SweepGradient(
          colors: [AppColors.leaf, AppColors.emerald, AppColors.forest, AppColors.leaf],
          stops: [0, 0.4, 0.8, 1],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
    // glowing tip
    final a = -math.pi / 2 + 2 * math.pi * v;
    final tip = r.center + Offset(math.cos(a), math.sin(a)) * (r.width / 2);
    canvas.drawCircle(tip, stroke * 0.75, Paint()..color = Colors.white);
    canvas.drawCircle(tip, stroke * 0.45, Paint()..color = AppColors.emerald);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v;
}

/// Seed → sprout → plant → tree as the fund grows.
IconData _stageIcon(double v) => v >= 1
    ? Icons.forest_rounded
    : v >= 0.75
        ? Icons.park_rounded
        : v >= 0.5
            ? Icons.spa_rounded
            : v >= 0.25
                ? Icons.grass_rounded
                : Icons.eco_outlined;

/// 25/50/75/100 % milestones on a track; reached ones light up, the next pulses.
class MilestoneTrack extends StatefulWidget {
  const MilestoneTrack({super.key, required this.value});

  final double value;

  @override
  State<MilestoneTrack> createState() => _MilestoneTrackState();
}

class _MilestoneTrackState extends State<MilestoneTrack> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const marks = [0.25, 0.5, 0.75, 1.0];
    const icons = [Icons.grass_rounded, Icons.spa_rounded, Icons.park_rounded, Icons.forest_rounded];
    final v = widget.value.clamp(0.0, 1.0);
    final next = marks.indexWhere((m) => v < m);
    return SizedBox(
      height: 44,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth - 34;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 17,
            right: 17,
            top: 16,
            child: Container(height: 6, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(3))),
          ),
          Positioned(
            left: 17,
            top: 16,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: v),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) => Container(
                width: w * t,
                height: 6,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.leaf, AppColors.emerald]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          for (var i = 0; i < marks.length; i++)
            Positioned(
              left: w * marks[i],
              top: 0,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Transform.scale(scale: i == next ? 1 + 0.12 * _pulse.value : 1, child: child),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: v >= marks[i] ? AppColors.emerald : Colors.white,
                    border: Border.all(color: v >= marks[i] ? AppColors.emerald : AppColors.mintLine, width: 2),
                    boxShadow: v >= marks[i]
                        ? [BoxShadow(color: AppColors.emerald.withValues(alpha: 0.35), blurRadius: 8)]
                        : null,
                  ),
                  child: Icon(icons[i], size: 18, color: v >= marks[i] ? Colors.white : AppColors.mintLine),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

/// Overlapping supporter avatars (initials; anonymous = heart) with "+N".
class SupporterStack extends StatelessWidget {
  const SupporterStack({super.key, required this.names, required this.total, this.size = 34});

  final List<String> names;
  final int total;
  final double size;

  static const _colors = [AppColors.forest, AppColors.emerald, Color(0xFF2E9A74), Color(0xFF167050), Color(0xFF46AE86)];

  @override
  Widget build(BuildContext context) {
    final shown = names.take(5).toList();
    final extra = total - shown.length;
    final items = <Widget>[
      for (final (i, n) in shown.indexed)
        _circle(
          i,
          n == 'Anonymous'
              ? const Icon(Icons.favorite_rounded, size: 15, color: Colors.white)
              : Text(n.trim().isEmpty ? '?' : n.trim()[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          _colors[i % _colors.length],
        ),
      if (extra > 0)
        _circle(shown.length, Text('+$extra', style: const TextStyle(color: AppColors.forest, fontWeight: FontWeight.w800, fontSize: 11)),
            AppColors.mint),
    ];
    if (items.isEmpty) {
      return _circle(0, const Icon(Icons.person_add_alt_1_rounded, size: 16, color: AppColors.forest), AppColors.mint);
    }
    return SizedBox(
      width: size + (items.length - 1) * size * 0.62,
      height: size,
      child: Stack(children: [for (final (i, w) in items.indexed) Positioned(left: i * size * 0.62, child: w)]),
    );
  }

  Widget _circle(int i, Widget child, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
        child: Center(child: child),
      );
}

/// Counts up to [value] rupees.
class CountUpInr extends StatelessWidget {
  const CountUpInr({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 1500),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(inr(v.round()), style: style),
      );
}

/// Primary call-to-action that softly pulses to invite a tap.
class PulseButton extends StatefulWidget {
  const PulseButton({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.emerald.withValues(alpha: 0.45 * (1 - t)),
                      blurRadius: 4 + 18 * t,
                      spreadRadius: 6 * t,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: enabled ? AppTheme.aiGradient : null,
          color: enabled ? null : AppColors.mintLine,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onPressed,
            child: SizedBox(
              height: 54,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(widget.icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Days-left mini ring.
class DaysLeftRing extends StatelessWidget {
  const DaysLeftRing({super.key, required this.closesAt, this.totalDays = 30});

  final DateTime closesAt;
  final int totalDays;

  @override
  Widget build(BuildContext context) {
    final days = closesAt.difference(DateTime.now()).inHours / 24;
    final left = days.clamp(0, 999).ceil();
    return SizedBox.square(
      dimension: 46,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: (days / totalDays).clamp(0.0, 1.0),
          strokeWidth: 4,
          color: left <= 3 ? const Color(0xFFD08A00) : AppColors.forest,
          backgroundColor: AppColors.mint,
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$left', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1, color: AppColors.forestDark)),
          const Icon(Icons.hourglass_bottom_rounded, size: 11, color: AppColors.inkMuted),
        ]),
      ]),
    );
  }
}

/// One-shot confetti burst in the app's colours (for a successful payment).
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.child});

  final Widget child;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  final _rnd = math.Random(7);
  late final _bits = List.generate(70, (_) => _Bit(_rnd));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_bits, _c.value)),
            ),
          ),
        ),
      ]);
}

class _Bit {
  _Bit(math.Random r)
      : angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.1,
        speed = 0.45 + r.nextDouble() * 0.6,
        spin = (r.nextDouble() - 0.5) * 12,
        size = 5 + r.nextDouble() * 6,
        color = const [
          AppColors.leaf, AppColors.emerald, AppColors.forest, Color(0xFFFF9933), Color(0xFF138808), Color(0xFFFFD166),
        ][r.nextInt(6)];

  final double angle, speed, spin, size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);

  final List<_Bit> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.28);
    for (final b in bits) {
      final d = b.speed * size.height * 0.9 * t;
      final p = origin + Offset(math.cos(b.angle) * d, math.sin(b.angle) * d + 0.9 * size.height * t * t);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(b.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.55), const Radius.circular(1.5)),
        Paint()..color = b.color.withValues(alpha: (1 - t).clamp(0, 1)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
