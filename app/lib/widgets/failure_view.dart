import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/failure.dart';
import '../utils/format.dart';
import 'ballot_widgets.dart';
import 'app_logo.dart';
import 'civic.dart';

/// Opens the full-page error screen for [error], unless it is a small input
/// mistake. Returns true if a page was shown (so the caller shows nothing else).
Future<bool> showFailure(BuildContext context, Object error, {StackTrace? stack, VoidCallback? onRetry}) async {
  final f = AppFailure.from(error, stack);
  if (!f.isPage) return false;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => FailureScreen(failure: f, onRetry: onRetry)),
  );
  return true;
}

/// Full-screen failure page (pushed on top, or used as a route's error page).
class FailureScreen extends StatelessWidget {
  const FailureScreen({super.key, required this.failure, this.onRetry});

  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(children: [
        Positioned(
            left: 0, right: 0, top: MediaQuery.paddingOf(context).top, child: const TricolourStrip(height: 3)),
        SafeArea(
          child: Column(children: [
            SizedBox(
              height: 52,
              child: Row(children: [
                if (canPop)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                else
                  const SizedBox(width: 16),
                const LogoBadge(size: 22),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(kAuthorityLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.inkMuted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ),
              ]),
            ),
            Expanded(
              child: FailureView(
                failure: failure,
                onRetry: onRetry == null
                    ? null
                    : () {
                        if (canPop) Navigator.of(context).pop();
                        onRetry!();
                      },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The failure content: illustration, title, message, countdown, actions and
/// technical details. Used full-page and in place of a screen that failed to load.
class FailureView extends StatefulWidget {
  const FailureView({super.key, required this.failure, this.onRetry});

  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  State<FailureView> createState() => _FailureViewState();
}

class _FailureViewState extends State<FailureView> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  Timer? _auto;
  int _autoLeft = 0;
  static const _autoEvery = 10; // seconds between automatic retries

  AppFailure get f => widget.failure;
  bool get _autoRetries =>
      widget.onRetry != null && (f.kind == FailureKind.offline || f.kind == FailureKind.serverDown);

  @override
  void initState() {
    super.initState();
    if (_autoRetries) _startAuto();
  }

  void _startAuto() {
    _auto?.cancel();
    _autoLeft = _autoEvery;
    _auto = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _autoLeft--);
      if (_autoLeft <= 0) {
        t.cancel();
        widget.onRetry?.call();
        if (mounted) _startAuto(); // still on this page → keep trying
      }
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _enter.dispose();
    _spin.dispose();
    super.dispose();
  }

  Animation<double> _seg(double a, double b, [Curve c = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _enter, curve: Interval(a, b, curve: c));

  /// Badge colour: red = something broke, amber = wait, green = just information.
  Color get _tone => switch (f.kind) {
        FailureKind.alreadyVoted || FailureKind.votingClosed => AppColors.emerald,
        FailureKind.votingNotOpen ||
        FailureKind.rateLimited ||
        FailureKind.serverDown ||
        FailureKind.aiUnavailable =>
          const Color(0xFFD08A00),
        _ => const Color(0xFFC2412D),
      };

  @override
  Widget build(BuildContext context) {
    final spec = failureSpecs[f.kind]!;
    final theme = Theme.of(context);
    final art = _seg(0, 0.6, Curves.easeOutBack);
    final text = _seg(0.2, 0.8);
    final actions = _seg(0.4, 1);

    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight.isFinite ? math.max(0, box.maxHeight - 44) : 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: art,
                child: f.kind == FailureKind.notFound ? _FourOhFour(spin: _spin) : _art(spec),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: text,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(text),
                  child: Column(children: [
                    Text(f.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.4)),
                    const SizedBox(height: 10),
                    Text(f.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.inkMuted, fontSize: 15, height: 1.5)),
                    if (f.until != null && f.until!.isAfter(DateTime.now())) ...[
                      const SizedBox(height: 16),
                      _chip(
                        Icons.timer_outlined,
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(f.kind == FailureKind.votingNotOpen ? 'Opens in ' : 'Try again in ',
                              style: const TextStyle(color: AppColors.forest, fontWeight: FontWeight.w600)),
                          Countdown(
                            to: f.until!,
                            onDone: () => setState(() {}),
                            style: const TextStyle(
                                color: AppColors.forestDark,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ]),
                      ),
                    ],
                    if (_autoRetries) ...[
                      const SizedBox(height: 16),
                      _chip(
                        Icons.sync_rounded,
                        Text('Retrying automatically in ${_autoLeft}s',
                            style: const TextStyle(color: AppColors.forest, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(opacity: actions, child: _Actions(failure: f, onRetry: widget.onRetry)),
              const SizedBox(height: 20),
              FadeTransition(opacity: actions, child: _Details(failure: f)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: AppColors.forest),
          const SizedBox(width: 7),
          child,
        ]),
      );

  /// Kolam ring slowly turning around a mint disc with the kind's icon + badge.
  Widget _art(FailureSpec spec) => SizedBox(
        width: 210,
        height: 210,
        child: Stack(alignment: Alignment.center, children: [
          RotationTransition(
            turns: _spin,
            child: CustomPaint(size: const Size.square(210), painter: _KolamRingPainter()),
          ),
          Container(
            width: 146,
            height: 146,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.mintLine, width: 2),
              boxShadow: [BoxShadow(color: AppColors.forest.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Center(
              child: Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
                child: Icon(spec.icon, size: 54, color: AppColors.forest),
              ),
            ),
          ),
          Positioned(
            right: 34,
            bottom: 34,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _tone,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Icon(spec.badge, size: 22, color: Colors.white),
            ),
          ),
        ]),
      );
}

/// "4 ◎ 4" — the zero is a spinning kolam.
class _FourOhFour extends StatelessWidget {
  const _FourOhFour({required this.spin});

  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 104,
      fontWeight: FontWeight.w800,
      color: AppColors.forest,
      height: 1,
      letterSpacing: -4,
    );
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        const Text('4', style: style),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(alignment: Alignment.center, children: [
            RotationTransition(
              turns: spin,
              child: CustomPaint(size: const Size.square(96), painter: _KolamRingPainter(dots: 12)),
            ),
            const KolamMark(size: 52, color: AppColors.emerald),
          ]),
        ),
        const SizedBox(width: 8),
        const Text('4', style: style),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.signpost_outlined, size: 15, color: AppColors.forest),
          SizedBox(width: 6),
          Text('Wrong turn', style: TextStyle(color: AppColors.forest, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      ),
    ]);
  }
}

/// Dotted kolam ring: dots on a circle joined by little petal loops.
class _KolamRingPainter extends CustomPainter {
  _KolamRingPainter({this.dots = 16});

  final int dots;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final dot = Paint()..color = AppColors.leaf;
    final loop = Paint()
      ..color = AppColors.mintLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, r, loop);
    for (var i = 0; i < dots; i++) {
      final a = 2 * math.pi * i / dots;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(p, 4, dot);
      if (i.isEven) canvas.drawCircle(p, 9, loop);
    }
  }

  @override
  bool shouldRepaint(_KolamRingPainter old) => old.dots != dots;
}

/// Primary + secondary buttons, chosen by failure kind.
class _Actions extends StatelessWidget {
  const _Actions({required this.failure, this.onRetry});

  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    void home() {
      nav.popUntil((r) => r.isFirst);
      GoRouter.maybeOf(context)?.go('/home');
    }

    void go(String path) {
      nav.popUntil((r) => r.isFirst);
      GoRouter.maybeOf(context)?.go(path);
    }

    final retry = onRetry == null ? null : ('Try again', Icons.refresh_rounded, onRetry!);
    final goHome = ('Go to home', Icons.home_rounded, home);
    final back = nav.canPop() ? ('Go back', Icons.arrow_back_rounded, () => nav.pop()) : null;

    final (primary, secondary) = switch (failure.kind) {
      FailureKind.offline || FailureKind.serverDown || FailureKind.serverError || FailureKind.aiUnavailable =>
        (retry ?? back ?? goHome, retry != null ? (back ?? goHome) : null),
      FailureKind.sessionExpired => (
          (
            'Sign in again',
            Icons.login_rounded,
            () {
              nav.popUntil((r) => r.isFirst);
              context.read<AuthProvider>().signOut();
            }
          ),
          null
        ),
      FailureKind.accessDenied => (goHome, back),
      FailureKind.notEligible => (('Open my profile', Icons.badge_rounded, () => go('/profile')), back),
      FailureKind.votingNotOpen => (
          ('Browse proposals', Icons.list_alt_rounded, home),
          ('Suggest an idea', Icons.lightbulb_outline_rounded, () => go('/ideas')),
        ),
      FailureKind.votingClosed => (('See final results', Icons.emoji_events_rounded, () => go('/results')), back),
      FailureKind.alreadyVoted => (
          ('View my receipt', Icons.receipt_long_rounded, () {
            nav.popUntil((r) => r.isFirst);
            showMyReceipt(nav.context);
          }),
          ('See results', Icons.insights_rounded, () => go('/results')),
        ),
      FailureKind.overBudget => (back ?? goHome, back != null ? goHome : null),
      FailureKind.notFound => (goHome, back),
      FailureKind.rateLimited => (
          (failure.until?.isAfter(DateTime.now()) ?? false) ? (back ?? goHome) : (retry ?? back ?? goHome),
          null
        ),
      FailureKind.crash => (('Restart app', Icons.restart_alt_rounded, () => RestartScope.restart(context)), null),
      FailureKind.invalid => (back ?? goHome, null),
    };

    return Column(children: [
      SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: primary.$3,
          icon: Icon(primary.$2),
          label: Text(primary.$1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
      if (secondary != null) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: secondary.$3,
            icon: Icon(secondary.$2),
            label: Text(secondary.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ]);
  }
}

/// Collapsible reference info for bug reports.
class _Details extends StatelessWidget {
  const _Details({required this.failure});

  final AppFailure failure;

  String get _report => [
        'Nam Nagaram error ${failure.code}',
        'Type: ${failure.kind.name}',
        'Time: ${formatDateTime(failure.at)}',
        if (failure.detail != null) failure.detail!.length > 1200 ? failure.detail!.substring(0, 1200) : failure.detail!,
      ].join('\n');

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.mintLine),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.info_outline_rounded, color: AppColors.inkMuted, size: 20),
            title: Text('Technical details · ${failure.code}',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: SelectableText(_report,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.ink, height: 1.4)),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded, size: 19),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _report));
                    ScaffoldMessenger.maybeOf(context)
                        ?.showSnackBar(const SnackBar(content: Text('Error details copied')));
                  },
                ),
              ]),
            ],
          ),
        ),
      );
}

/// Wraps the whole app so the crash page can restart it (rebuilds providers,
/// router and screens; the saved login session is kept).
class RestartScope extends StatefulWidget {
  const RestartScope({super.key, required this.builder});

  final Widget Function() builder;

  static void restart(BuildContext context) => context.findAncestorStateOfType<_RestartScopeState>()?.restart();

  @override
  State<RestartScope> createState() => _RestartScopeState();
}

class _RestartScopeState extends State<RestartScope> {
  Key _key = UniqueKey();
  late Widget _app = widget.builder();

  void restart() => setState(() {
        _key = UniqueKey();
        _app = widget.builder();
      });

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: _app);
}

/// Shown when a widget throws while building: the full crash page when it has
/// room (a whole screen failed), a compact notice inside a smaller area.
class CrashView extends StatelessWidget {
  const CrashView({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final failure = AppFailure.of(FailureKind.crash, detail: '${details.exception}\n${details.stack ?? ''}');
    return LayoutBuilder(builder: (context, box) {
      if (box.maxHeight.isFinite && box.maxHeight >= 420) {
        return Material(color: AppColors.canvas, child: SafeArea(child: FailureView(failure: failure)));
      }
      return Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFDEEEC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF6CFCA)),
          ),
          child: Row(children: [
            const Icon(Icons.broken_image_rounded, color: Color(0xFF9B1C1C), size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('This part of the screen couldn\'t load.',
                  style: TextStyle(color: Color(0xFF9B1C1C), fontSize: 13)),
            ),
            TextButton(onPressed: () => RestartScope.restart(context), child: const Text('Restart')),
          ]),
        ),
      );
    });
  }
}
