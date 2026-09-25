import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'civic.dart';

/// The app's signature header: a deep-green gradient block with rounded bottom
/// corners and soft rings. Every main screen starts with one, so the whole app
/// reads as one green-and-white product.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.child,
    this.showBack = false,
    this.bottomPadding = 26,
  });

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? child;
  final bool showBack;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light, // white status-bar icons on green
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          gradient: AppTheme.heroGradient,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        child: Stack(
          children: [
            // Kolam texture, fading out towards the left so text stays crisp
            Positioned.fill(
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  colors: [Colors.transparent, Colors.white],
                  stops: [0.25, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: CustomPaint(painter: KolamPatternPainter()),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(showBack ? 8 : 20, 4, 12, bottomPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Portal-style authority line
                    Padding(
                      padding: EdgeInsets.only(left: showBack ? 12 : 0, top: 6),
                      child: Row(children: [
                        const KolamMark(size: 16, color: AppColors.leaf),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            kAuthorityLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ]),
                    ),
                    SizedBox(
                      height: 52,
                      child: Row(children: [
                        if (showBack)
                          IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          ),
                        if (leading != null) ...[leading!, const SizedBox(width: 12)],
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title != null)
                                Text(title!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                        color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                              if (subtitle != null)
                                Text(subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
                            ],
                          ),
                        ),
                        ...actions,
                      ]),
                    ),
                    if (child != null)
                      Padding(
                        padding: EdgeInsets.only(left: showBack ? 12 : 0, right: 8, top: 14),
                        child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child!),
                      ),
                  ],
                ),
              ),
            ),
            // Tricolour strip along the very top edge (under the status bar)
            Positioned(left: 0, right: 0, top: MediaQuery.paddingOf(context).top, child: const TricolourStrip(height: 3)),
          ],
        ),
      ),
    );
  }
}

/// Header for the sign-up steps: segmented progress, big title, subtitle.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    super.key,
    required this.step,
    required this.total,
    required this.title,
    this.subtitle,
    this.icon,
    this.showBack = true,
    this.actions = const [],
  });

  final int step;
  final int total;
  final String title;
  final InlineSpan? subtitle;
  final IconData? icon;
  final bool showBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return BrandHeader(
      showBack: showBack,
      actions: actions,
      bottomPadding: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('STEP $step OF $total',
                style: const TextStyle(
                    color: AppColors.leaf, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
            const SizedBox(width: 12),
            for (var i = 1; i <= total; i++)
              Expanded(
                child: Container(
                  height: 5,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: i <= step ? AppColors.leaf : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 22),
          if (icon != null) ...[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: AppColors.forest, size: 28),
            ),
            const SizedBox(height: 16),
          ],
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text.rich(subtitle!,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 14.5, height: 1.45)),
          ],
        ],
      ),
    );
  }
}

/// Round translucent-white icon button for use inside [BrandHeader].
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: Colors.white.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );
}

/// White circle with the user's initials (profile shortcut in headers).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 42, this.onTap});

  final String? name;
  final double size;
  final VoidCallback? onTap;

  String get _initials {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    final s = parts.map((p) => p[0].toUpperCase()).join();
    return s.isEmpty ? '?' : s;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.leaf, width: 2),
          ),
          child: Text(_initials,
              style: TextStyle(
                  color: AppColors.forest, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
        ),
      );
}

/// Small uppercase label used inside the green header ("WARD BUDGET POOL").
class HeaderLabel extends StatelessWidget {
  const HeaderLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          color: AppColors.leaf, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2));
}

/// Big white number inside the green header.
class HeaderNumber extends StatelessWidget {
  const HeaderNumber(this.text, {super.key, this.size = 34});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: Colors.white, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.15));
}

/// Section title with an optional count pill and trailing widget.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.count, this.trailing});

  final String text;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(text,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
              child: Text('$count',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.forest)),
            ),
          ],
          const Spacer(),
          ?trailing,
        ]),
      );
}

/// Pulls the first card up over the bottom edge of the [BrandHeader].
class OverlapHeader extends StatelessWidget {
  const OverlapHeader({super.key, required this.child, this.by = 24});

  final Widget child;
  final double by;

  @override
  Widget build(BuildContext context) => Transform.translate(offset: Offset(0, -by), child: child);
}
