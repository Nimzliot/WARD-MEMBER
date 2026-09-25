import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/failure.dart';
import 'civic.dart';
import 'failure_view.dart';

/// Full-width filled button with a built-in loading spinner.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          );
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(onPressed: loading ? null : onPressed, child: child),
    );
  }
}

/// Inline error / info message box.
class MessageBanner extends StatelessWidget {
  const MessageBanner(this.message, {super.key, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    const errorFg = Color(0xFF9B1C1C);
    final bg = isError ? const Color(0xFFFDEEEC) : AppColors.mint;
    final border = isError ? const Color(0xFFF6CFCA) : AppColors.mintLine;
    final fg = isError ? errorFg : AppColors.forestDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: fg, fontSize: 13.5, height: 1.4))),
        ],
      ),
    );
  }
}

/// Deep-green gradient card with a soft kolam texture — used for the key
/// number on a screen (budget pool, turnout, proposal total).
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: AppColors.forest.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [Colors.transparent, Colors.white], stops: [0.3, 1])
                  .createShader(r),
              blendMode: BlendMode.dstIn,
              child: CustomPaint(painter: KolamPatternPainter(opacity: 0.08, cell: 24)),
            ),
          ),
          Padding(
            padding: padding,
            child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
          ),
        ],
      ),
    );
  }
}

/// White progress bar on a hero card.
class HeroProgress extends StatelessWidget {
  const HeroProgress({super.key, required this.value, this.warning = false});

  final double value;
  final bool warning;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 8,
          color: warning ? const Color(0xFFFFB4A8) : AppColors.leaf,
          backgroundColor: Colors.white.withValues(alpha: 0.18),
        ),
      );
}

/// A screen that failed to load: shows the matching full failure page
/// (offline, server down, session expired, 404…). Pass the raw [error] when
/// you have it; [message] alone is classified by its wording.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.message, this.error, required this.onRetry});

  final String? message;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) =>
      FailureView(failure: AppFailure.from(error ?? message ?? 'Unknown error'), onRetry: onRetry);
}

/// Centered icon + message for empty lists.
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: AppColors.forest),
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ],
        ),
      ),
    );
  }
}

/// "✓ Verified" / "Not verified" pill.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final color = verified ? AppTheme.success : Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verified ? Icons.verified : Icons.help_outline, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            verified ? 'Verified' : 'Not verified',
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
