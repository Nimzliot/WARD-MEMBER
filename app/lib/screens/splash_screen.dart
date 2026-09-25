import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/civic.dart';

/// Becomes true when the intro animation has finished. The router keeps the
/// app on /splash until then, so the intro always plays in full.
final introDone = ValueNotifier<bool>(false);

/// Animated intro: ripples → ballot tile springs in → a vote drops in →
/// verified tick → hash chain links up → title and tagline rise.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) introDone.value = true;
    })
    ..forward();
  late final AnimationController _ripple = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  /// [begin]..[end] slice of the intro timeline, eased.
  Animation<double> _seg(double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(begin, end, curve: curve));

  late final _tile = _seg(0.02, 0.34, Curves.elasticOut);
  late final _tileFade = _seg(0.02, 0.14);
  late final _drop = _seg(0.22, 0.42, Curves.bounceOut);
  late final _tick = _seg(0.40, 0.52, Curves.easeOutBack);
  late final _chain = _seg(0.40, 0.74, Curves.easeInOut);
  late final _title = _seg(0.50, 0.80);
  late final _tagline = _seg(0.68, 0.92);
  late final _footer = _seg(0.82, 1.0);

  @override
  void dispose() {
    _intro.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Stack(
          children: [
            // Kolam texture over the whole screen, fading in with the logo
            Positioned.fill(
              child: FadeTransition(
                opacity: _tileFade,
                child: CustomPaint(painter: KolamPatternPainter(opacity: 0.045, cell: 30)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.paddingOf(context).top,
              child: const TricolourStrip(),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.paddingOf(context).bottom + 18,
              child: FadeTransition(opacity: _footer, child: const PrototypeNotice(onDark: true)),
            ),
            // Soft ripples spreading from behind the logo, forever.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge([_ripple, _tileFade]),
                builder: (_, _) => CustomPaint(
                  painter: _RipplePainter(progress: _ripple.value, opacity: _tileFade.value),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: AnimatedBuilder(
                    animation: _intro,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _logo(),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: 180,
                          height: 18,
                          child: CustomPaint(painter: _ChainPainter(_chain.value)),
                        ),
                        const SizedBox(height: 20),
                        // authority line: the kolam mark draws itself, then the text fades in
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          KolamMark(size: 20, color: AppColors.leaf, progress: _chain.value),
                          const SizedBox(width: 8),
                          Opacity(
                            opacity: _title.value,
                            child: Text(kAuthorityLine,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                )),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        _StaggeredTitle(
                          text: kAppName,
                          progress: _title.value,
                          style: theme.textTheme.headlineLarge!
                              .copyWith(fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.8),
                        ),
                        const SizedBox(height: 8),
                        _tagLine(theme),
                        const SizedBox(height: 18),
                        Opacity(
                          opacity: _footer.value,
                          child: Transform.translate(offset: Offset(0, 8 * (1 - _footer.value)), child: _sdgPill()),
                        ),
                        const SizedBox(height: 44),
                        SizedBox(height: 96, child: _bottom(auth)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// White ballot-box tile; a vote card drops into the slot, then a tick pops.
  Widget _logo() {
    final scale = _tile.value.clamp(0.0, 1.2);
    return Opacity(
      opacity: _tileFade.value,
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: 112,
          height: 112,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            // glow
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: AppColors.leaf.withValues(alpha: 0.35 * _tileFade.value), blurRadius: 40, spreadRadius: 4),
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 24, offset: const Offset(0, 12)),
                ],
              ),
            ),
            // the tile (clips the falling vote so it "enters" the box)
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 104,
                height: 104,
                color: Colors.white,
                child: Stack(alignment: Alignment.center, children: [
                  Transform.translate(
                    offset: Offset(0, -70 * (1 - _drop.value)),
                    child: Opacity(
                      opacity: _drop.value.clamp(0.0, 1.0),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: AppLogo(size: 64),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            // verified tick
            Positioned(
              right: -2,
              bottom: -2,
              child: Transform.scale(
                scale: _tick.value,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(Icons.check_rounded, size: 19, color: Colors.white),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// "Your ward. Your money. Your vote." — word by word, last word highlighted.
  Widget _tagLine(ThemeData theme) {
    const words = ['Your ward.', 'Your money.', 'Your vote.'];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      children: [
        for (var i = 0; i < words.length; i++)
          Builder(builder: (_) {
            final t = ((_tagline.value - i * 0.25) / 0.5).clamp(0.0, 1.0);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - t)),
                child: Text(
                  words[i],
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: i == words.length - 1 ? AppColors.leaf : Colors.white.withValues(alpha: 0.88),
                    fontWeight: i == words.length - 1 ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _sdgPill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_city, size: 16, color: AppColors.leaf),
          SizedBox(width: 6),
          Text('SDG 11 · Sustainable Cities',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      );

  /// Thin progress line while loading; retry on error.
  Widget _bottom(AuthProvider auth) {
    if (auth.stage == AuthStage.error) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text(auth.loadError ?? 'Could not load your profile',
            textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.forest),
            onPressed: auth.loadProfile,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
          TextButton(onPressed: auth.signOut, child: const Text('Sign out', style: TextStyle(color: Colors.white))),
        ]),
      ]);
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Opacity(
        opacity: _footer.value,
        child: SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: auth.stage == AuthStage.loading ? null : _intro.value,
              minHeight: 4,
              color: AppColors.leaf,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title letters rise and fade in one after another.
class _StaggeredTitle extends StatelessWidget {
  const _StaggeredTitle({required this.text, required this.progress, required this.style});

  final String text;
  final double progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final n = text.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++)
          Builder(builder: (_) {
            final t = Curves.easeOutBack.transform(((progress * (n + 4) - i) / 5).clamp(0.0, 1.0));
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: Text(text[i], style: style)),
            );
          }),
      ],
    );
  }
}

/// Expanding rings from the logo — like a vote rippling through the ward.
class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.progress, required this.opacity});

  final double progress; // 0..1, repeating
  final double opacity; // fades the whole effect in

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.33); // behind the logo
    final maxR = math.sqrt(size.width * size.width + size.height * size.height) * 0.55;
    for (var k = 0; k < 3; k++) {
      final t = (progress + k / 3) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26 * (1 - t) + 2
        ..color = Colors.white.withValues(alpha: 0.07 * (1 - t) * opacity);
      canvas.drawCircle(center, 60 + t * maxR, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.progress != progress || old.opacity != opacity;
}

/// Five blocks linking up left to right — the tamper-evident hash chain.
class _ChainPainter extends CustomPainter {
  _ChainPainter(this.progress);

  final double progress; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    const n = 5;
    const block = 14.0;
    final gap = (size.width - n * block) / (n - 1);
    final y = size.height / 2;
    final link = Paint()
      ..color = AppColors.leaf.withValues(alpha: 0.85)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < n; i++) {
      final appear = ((progress * n) - i).clamp(0.0, 1.0);
      if (appear <= 0) break;
      final x = i * (block + gap);
      // link from the previous block draws across
      if (i > 0) {
        final from = Offset(x - gap, y);
        canvas.drawLine(from, Offset.lerp(from, Offset(x, y), appear)!, link);
      }
      final s = block * Curves.easeOutBack.transform(appear);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x + block / 2, y), width: s, height: s),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, Paint()..color = (i == n - 1 ? AppColors.leaf : Colors.white).withValues(alpha: appear));
    }
  }

  @override
  bool shouldRepaint(_ChainPainter old) => old.progress != progress;
}
