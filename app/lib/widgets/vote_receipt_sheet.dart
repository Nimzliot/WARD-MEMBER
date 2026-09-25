import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/vote.dart';
import '../theme.dart';
import '../utils/format.dart';

Future<void> showVoteReceipt(
  BuildContext context,
  VoteReceipt receipt, {
  bool justVoted = false,
  VoidCallback? onViewResults,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => VoteReceiptSheet(receipt: receipt, justVoted: justVoted, onViewResults: onViewResults),
  );
}

class VoteReceiptSheet extends StatelessWidget {
  const VoteReceiptSheet({super.key, required this.receipt, this.justVoted = false, this.onViewResults});

  final VoteReceipt receipt;
  final bool justVoted;
  final VoidCallback? onViewResults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 32,
                backgroundColor: AppTheme.success.withValues(alpha: 0.15),
                child: const Icon(Icons.check_rounded, size: 40, color: AppTheme.success),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(justVoted ? 'Ballot recorded!' : 'Your ballot receipt',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(formatDateTime(receipt.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 14),
            // Every project on the ballot + what they cost together
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.mintLine),
              ),
              child: Column(children: [
                for (final t in receipt.proposalTitles)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.success),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                  ),
                if (receipt.totalCost > 0) ...[
                  const Divider(height: 18),
                  Row(children: [
                    Text(
                      '${receipt.proposalTitles.length} project${receipt.proposalTitles.length == 1 ? '' : 's'}',
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                    const Spacer(),
                    Text(inr(receipt.totalCost),
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forestDark)),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 18),
            _HashRow(label: 'Ballot hash (your receipt)', value: receipt.hash, copyable: true),
            _HashRow(
              label: 'Previous ballot hash',
              value: receipt.isFirstInChain ? '${receipt.prevHash.substring(0, 16)}… (first ballot in ward)' : receipt.prevHash,
            ),
            _HashRow(label: 'Anonymous voter ID', value: receipt.voterHash),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Your name is never stored with your ballot. Each ballot\'s hash includes the previous '
                'ballot\'s hash, so changing or deleting any ballot breaks the chain. Anyone in your '
                'ward can check this in the Audit Log.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            if (onViewResults != null) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onViewResults!();
                  },
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('See live results'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: onViewResults != null
                  ? OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))
                  : FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ),
          ],
        ),
      ),
    );
  }
}

class _HashRow extends StatelessWidget {
  const _HashRow({required this.label, required this.value, this.copyable = false});

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Ballot hash copied')));
              },
            ),
        ],
      ),
    );
  }
}
