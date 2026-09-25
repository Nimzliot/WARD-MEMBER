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
              child: Text(justVoted ? 'Vote recorded!' : 'Your vote receipt',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            if (receipt.proposalTitle != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(receipt.proposalTitle!,
                    textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              ),
            ],
            const SizedBox(height: 4),
            Center(
              child: Text(formatDateTime(receipt.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 20),
            _HashRow(label: 'Vote hash (your receipt)', value: receipt.hash, copyable: true),
            _HashRow(
              label: 'Previous vote hash',
              value: receipt.isFirstInChain ? '${receipt.prevHash.substring(0, 16)}… (first vote in ward)' : receipt.prevHash,
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
                'Your name is never stored with your vote. Each vote\'s hash includes the previous '
                'vote\'s hash, so changing or deleting any vote breaks the chain. Anyone in your '
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
                    .showSnackBar(const SnackBar(content: Text('Vote hash copied')));
              },
            ),
        ],
      ),
    );
  }
}
