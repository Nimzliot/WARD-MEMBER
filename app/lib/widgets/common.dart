import 'package:flutter/material.dart';

import '../theme.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final bg = isError ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = isError ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: fg))),
        ],
      ),
    );
  }
}

/// Centered error message with a Retry button (for failed loads).
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
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
            Icon(icon, size: 48, color: muted),
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

/// Small "Step 1 of 2" style progress header for the onboarding screens.
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.step, required this.total, required this.title});

  final int step;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STEP $step OF $total',
            style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: step / total, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 20),
        Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
