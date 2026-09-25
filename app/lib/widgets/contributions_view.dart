import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/format.dart';
import 'common.dart';

/// Ward Fund money: totals (per ward for the super admin) and every
/// contribution with its status. Used by the Ward Admin console (their ward)
/// and the super admin's Funds tab (all wards, [wardName] shown).
class ContributionsView extends StatelessWidget {
  const ContributionsView({super.key, required this.data, this.wardName});

  final Map<String, dynamic> data; // { wards: [{ward_id, raised, payments, supporters}], contributions: [...] }
  final String Function(int wardId)? wardName;

  @override
  Widget build(BuildContext context) {
    final wards = (data['wards'] as List? ?? const []).cast<Map<String, dynamic>>();
    final rows = (data['contributions'] as List? ?? const []).cast<Map<String, dynamic>>();
    final raised = wards.fold<int>(0, (s, w) => s + (w['raised'] as num).toInt());
    final payments = wards.fold<int>(0, (s, w) => s + (w['payments'] as num).toInt());
    final top = wards.fold<int>(1, (m, w) => (w['raised'] as num).toInt() > m ? (w['raised'] as num).toInt() : m);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      HeroCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('RAISED (CONFIRMED)',
                  style: TextStyle(color: AppColors.leaf, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.1)),
              const SizedBox(height: 4),
              Text(inr(raised), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$payments', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text('payments', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
          ]),
        ]),
      ),
      // Per-ward bars (super admin view)
      if (wardName != null && wards.length > 1) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              for (final w in wards)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 70,
                      child: Text(wardName!(w['ward_id'] as int),
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (w['raised'] as num) / top,
                          minHeight: 12,
                          backgroundColor: AppColors.mint,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 70,
                      child: Text(inrCompact(w['raised'] as num),
                          textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forestDark)),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text('Contributions (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      if (rows.isEmpty) const Text('No contributions yet.', style: TextStyle(color: AppColors.inkMuted)),
      for (final r in rows)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            leading: CircleAvatar(
              backgroundColor: _statusColor(r['status'] as String).withValues(alpha: 0.12),
              child: Icon(_statusIcon(r['status'] as String), color: _statusColor(r['status'] as String), size: 20),
            ),
            title: Row(children: [
              Expanded(
                child: Text('${r['name']}${r['anonymous'] == true ? ' (anonymous to residents)' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(inr(r['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forestDark)),
            ]),
            subtitle: Text(
              [
                if (wardName != null && r['ward_id'] != null) wardName!(r['ward_id'] as int),
                _statusLabel(r['status'] as String),
                if (r['razorpay_payment_id'] != null) r['razorpay_payment_id'],
                formatDateTime(DateTime.parse((r['paid_at'] ?? r['created_at']) as String).toLocal()),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
    ]);
  }

  static Color _statusColor(String s) => switch (s) {
        'paid' => AppTheme.success,
        'created' => const Color(0xFFB27300),
        _ => AppColors.inkMuted,
      };
  static IconData _statusIcon(String s) => switch (s) {
        'paid' => Icons.check_rounded,
        'created' => Icons.hourglass_top_rounded,
        _ => Icons.close_rounded,
      };
  static String _statusLabel(String s) => switch (s) {
        'paid' => 'Paid',
        'created' => 'Awaiting payment',
        'expired' => 'Expired',
        _ => 'Failed',
      };
}
