import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../models/ward.dart';
import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../theme.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/ballot_widgets.dart';
import '../widgets/brand.dart';
import '../widgets/budget_breakdown.dart';
import '../widgets/common.dart';

class ProposalDetailScreen extends StatefulWidget {
  const ProposalDetailScreen({super.key, required this.proposalId});

  final String proposalId;

  @override
  State<ProposalDetailScreen> createState() => _ProposalDetailScreenState();
}

class _ProposalDetailScreenState extends State<ProposalDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final auth = context.watch<AuthProvider>();
    final p = wp.byId(widget.proposalId);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: wp.loading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyView(icon: Icons.search_off, message: 'Proposal not found in your ward.'),
      );
    }

    final pool = wp.ward?.budgetPool ?? 0;
    final share = pool == 0 ? 0.0 : p.totalCost / pool;

    return Scaffold(
      bottomNavigationBar: _VoteBar(
        proposal: p,
        eligibleReason: _ineligibleReason(auth),
        onAsk: () => showAskSheet(context, p),
      ),
      body: RefreshIndicator(
        onRefresh: wp.load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            BrandHeader(
              showBack: true,
              title: 'Proposal',
              subtitle: wp.ward?.name,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(categoryIcon(p.category), size: 15, color: AppColors.leaf),
                        const SizedBox(width: 6),
                        Text(
                          p.category,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    p.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const HeaderLabel('Total cost'),
                            const SizedBox(height: 2),
                            HeaderNumber(inr(p.totalCost), size: 28),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${(share * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'of ${inrCompact(pool)} pool',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  HeroProgress(value: math.min(1.0, share)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('About this proposal'),
                  Text(
                    p.description,
                    style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  // Ward Assistant — plain-language explanation in EN / Tamil / Hindi
                  ExplainCard(key: ValueKey(p.id), proposal: p),
                  const SizedBox(height: 28),
                  SectionTitle('Budget breakdown', count: p.items.length),
                  BudgetBreakdown(items: p.items, total: p.totalCost),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Voting requires ONE verification (email or SMS code) + completed profile.
  /// (The route guard already enforces this; the server checks it again.)
  String? _ineligibleReason(AuthProvider auth) {
    final profile = auth.profile;
    if (auth.session == null || profile == null) return 'Sign in to vote';
    if (auth.user?.emailConfirmedAt == null && !profile.phoneVerified) {
      return 'Verify your email or mobile number to vote';
    }
    if (!profile.isComplete) return 'Complete your profile to vote';
    return null;
  }
}

/// Bottom action bar. What it shows depends on the voting phase and whether the
/// resident has already submitted a ballot.
class _VoteBar extends StatelessWidget {
  const _VoteBar({required this.proposal, required this.eligibleReason, required this.onAsk});

  final Proposal proposal;
  final String? eligibleReason;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final ward = wp.ward;
    final phase = ward?.phase ?? WardPhase.open;

    Widget status(IconData icon, Color color, String text, {Widget? trailing}) => Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
          ?trailing,
        ]);

    final receiptButton = TextButton.icon(
      onPressed: () => showMyReceipt(context),
      icon: const Icon(Icons.receipt_long),
      label: const Text('Receipt'),
    );

    Widget content;
    if (wp.hasVoted) {
      content = wp.isOnMyBallot(proposal.id)
          ? status(Icons.check_circle, AppTheme.success, 'On your ballot', trailing: receiptButton)
          : status(Icons.info_outline, AppColors.inkMuted, 'Not on your ballot', trailing: receiptButton);
    } else if (phase == WardPhase.closed) {
      content = status(Icons.lock_clock_outlined, AppColors.inkMuted, 'Voting closed · results final',
          trailing: TextButton(onPressed: () => context.go('/results'), child: const Text('Results')));
    } else if (phase == WardPhase.upcoming) {
      content = Row(children: [
        const Icon(Icons.schedule_rounded, color: AppColors.forest),
        const SizedBox(width: 8),
        const Text('Voting opens in ', style: TextStyle(fontWeight: FontWeight.w600)),
        Countdown(to: ward!.votingOpensAt!, onDone: wp.load, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]);
    } else if (eligibleReason != null) {
      content = MessageBanner(eligibleReason!);
    } else {
      final picked = wp.isPicked(proposal.id);
      final fits = wp.fits(proposal);
      content = Row(children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: picked
                ? OutlinedButton.icon(
                    onPressed: () => wp.togglePick(proposal),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('On ballot', style: TextStyle(fontWeight: FontWeight.w700)),
                  )
                : FilledButton.icon(
                    onPressed: fits ? () => wp.togglePick(proposal) : null,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(fits ? 'Add to ballot' : 'Over budget',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
          ),
        ),
        if (wp.picks.isNotEmpty) ...[
          const SizedBox(width: 8),
          SizedBox(
            height: 52,
            child: FilledButton.tonal(
              onPressed: () => showBallotReview(context),
              child: Text('Review ${wp.picks.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestDark.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          // Ask AI sits beside the main action so it never covers budget numbers
          child: Row(
            children: [
              _AskButton(onPressed: onAsk),
              const SizedBox(width: 10),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact gradient "Ask AI" button for the bottom bar.
class _AskButton extends StatelessWidget {
  const _AskButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(gradient: AppTheme.aiGradient, borderRadius: BorderRadius.circular(14)),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: const SizedBox(
          height: 52,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'Ask AI',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
