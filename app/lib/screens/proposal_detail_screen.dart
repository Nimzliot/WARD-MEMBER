import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../theme.dart';
import '../utils/categories.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/brand.dart';
import '../widgets/budget_breakdown.dart';
import '../widgets/common.dart';
import '../widgets/vote_receipt_sheet.dart';

class ProposalDetailScreen extends StatefulWidget {
  const ProposalDetailScreen({super.key, required this.proposalId});

  final String proposalId;

  @override
  State<ProposalDetailScreen> createState() => _ProposalDetailScreenState();
}

class _ProposalDetailScreenState extends State<ProposalDetailScreen> {
  bool _voting = false;
  bool _loadingReceipt = false;

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _vote(Proposal p) async {
    final wp = context.read<WardProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.how_to_vote_rounded),
        title: const Text('Confirm your vote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(inr(p.totalCost)),
            const SizedBox(height: 16),
            MessageBanner(
              'You have ONE vote in ${wp.ward?.name ?? 'your ward'}. '
              'It cannot be changed or withdrawn after you confirm.',
              isError: false,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm vote')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _voting = true);
    try {
      final receipt = await wp.castVote(p.id);
      if (mounted) {
        await showVoteReceipt(context, receipt, justVoted: true, onViewResults: () => context.go('/results'));
      }
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Future<void> _showReceipt() async {
    setState(() => _loadingReceipt = true);
    try {
      final receipt = await context.read<WardProvider>().fetchMyReceipt();
      if (!mounted) return;
      if (receipt == null) {
        _snack('No vote found', error: true);
      } else {
        await showVoteReceipt(context, receipt);
      }
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingReceipt = false);
    }
  }

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
        votedForId: wp.myVoteProposalId,
        votedForTitle: wp.myVotedProposal?.title,
        eligibleReason: _ineligibleReason(auth),
        voting: _voting,
        loadingReceipt: _loadingReceipt,
        onVote: () => _vote(p),
        onShowReceipt: _showReceipt,
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

class _VoteBar extends StatelessWidget {
  const _VoteBar({
    required this.proposal,
    required this.votedForId,
    required this.votedForTitle,
    required this.eligibleReason,
    required this.voting,
    required this.loadingReceipt,
    required this.onVote,
    required this.onShowReceipt,
    required this.onAsk,
  });

  final Proposal proposal;
  final String? votedForId;
  final String? votedForTitle;
  final String? eligibleReason;
  final bool voting;
  final bool loadingReceipt;
  final VoidCallback onVote;
  final VoidCallback onShowReceipt;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget content;
    if (votedForId == proposal.id) {
      content = Row(
        children: [
          const Icon(Icons.check_circle, color: AppTheme.success),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('You voted for this', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton.icon(
            onPressed: loadingReceipt ? null : onShowReceipt,
            icon: loadingReceipt
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.receipt_long),
            label: const Text('Receipt'),
          ),
        ],
      );
    } else if (votedForId != null) {
      content = Row(
        children: [
          Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You already voted for "${votedForTitle ?? 'another proposal'}"',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      );
    } else if (eligibleReason != null) {
      content = MessageBanner(eligibleReason!);
    } else {
      content = PrimaryButton(
        label: 'Vote for this proposal',
        icon: Icons.how_to_vote_rounded,
        loading: voting,
        onPressed: onVote,
      );
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
