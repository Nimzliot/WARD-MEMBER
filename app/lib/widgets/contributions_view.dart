import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/format.dart';
import 'common.dart';

/// Fundraisers + every contribution (all statuses), for the Ward Admin
/// (their ward) and the super admin (all wards, [wardName] shown).
class ContributionsView extends StatelessWidget {
  const ContributionsView({super.key, required this.data, this.wardName, this.header});

  final Map<String, dynamic> data; // { campaigns: [...], contributions: [...] }
  final String Function(int wardId)? wardName;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final campaigns = (data['campaigns'] as List? ?? const []).cast<Map<String, dynamic>>();
    final rows = (data['contributions'] as List? ?? const []).cast<Map<String, dynamic>>();
    final paid = rows.where((r) => r['status'] == 'paid');
    final raised = paid.fold<int>(0, (s, r) => s + (r['amount'] as num).toInt());

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ?header,
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
            Text('${paid.length}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text('payments', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
          ]),
        ]),
      ),
      const SizedBox(height: 18),
      Text('Fundraisers (${campaigns.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      if (campaigns.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('No fundraisers yet.', style: TextStyle(color: AppColors.inkMuted)),
        ),
      for (final c in campaigns)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800))),
                _chip(c['status'] == 'active' ? 'Active' : 'Closed', c['status'] == 'active' ? AppTheme.success : AppColors.inkMuted),
              ]),
              if (wardName != null) ...[
                const SizedBox(height: 2),
                Text(wardName!(c['ward_id'] as int), style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
              ],
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: ((c['raised'] as num) / (c['goal'] as num)).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: AppColors.mint,
                ),
              ),
              const SizedBox(height: 6),
              Text('${inr(c['raised'] as num)} of ${inr(c['goal'] as num)} · ${c['backers']} supporters',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            ]),
          ),
        ),
      const SizedBox(height: 10),
      Text('Contributions (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      if (rows.isEmpty)
        const Text('No contributions yet.', style: TextStyle(color: AppColors.inkMuted)),
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
                r['campaign_title'],
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

  static Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5)),
      );

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
