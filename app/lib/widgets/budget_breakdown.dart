import 'package:flutter/material.dart';

import '../models/proposal.dart';
import '../utils/chart_colors.dart';
import '../utils/format.dart';

/// One proportional bar (each budget line's share of the total) plus a legend
/// table with the exact ₹ amount and percentage for every line.
class BudgetBreakdown extends StatelessWidget {
  const BudgetBreakdown({super.key, required this.items, required this.total});

  final List<BudgetItem> items; // sorted largest first
  final int total;

  /// More than 8 lines → keep the top 7 and fold the rest into "Other".
  List<({String label, int amount})> get _rows {
    final rows = [for (final i in items) (label: i.label, amount: i.amount)];
    if (rows.length <= kMaxSeries) return rows;
    final rest = rows.sublist(kMaxSeries - 1);
    return [
      ...rows.take(kMaxSeries - 1),
      (label: 'Other (${rest.length} lines)', amount: rest.fold(0, (s, r) => s + r.amount)),
    ];
  }

  /// Largest line = darkest green; a folded "Other" row is neutral grey.
  Color _color(int i, int count) =>
      (items.length > kMaxSeries && i == count - 1) ? kNeutralChart : rampColor(i);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = _rows;
    if (rows.isEmpty || total <= 0) return const Text('No budget lines');

    String pct(int amount) => '${(amount * 100 / total).toStringAsFixed(amount * 100 / total < 10 ? 1 : 0)}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Proportional bar — 2px surface gaps between segments, rounded ends.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      Expanded(
                        flex: (rows[i].amount * 1000 / total).round().clamp(1, 1000),
                        child: Container(
                          margin: EdgeInsets.only(right: i == rows.length - 1 ? 0 : 2),
                          color: _color(i, rows.length),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Legend / table view
            for (var i = 0; i < rows.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _color(i, rows.length),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(rows[i].label, style: theme.textTheme.bodyMedium)),
                    const SizedBox(width: 8),
                    Text(inr(rows[i].amount),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(
                      width: 52,
                      child: Text(pct(rows[i].amount),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
              if (i < rows.length - 1) Divider(height: 1, color: scheme.outlineVariant),
            ],
            Divider(height: 16, thickness: 1.5, color: scheme.outline),
            Row(
              children: [
                const SizedBox(width: 24),
                Expanded(
                  child: Text('Total',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text(inr(total),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 52),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
