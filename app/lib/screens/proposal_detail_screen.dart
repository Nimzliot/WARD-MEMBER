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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
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
        await showVoteReceipt(
          context,
          receipt,
          justVoted: true,
          onViewResults: () => context.go('/results'),
        );
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
      appBar: AppBar(title: const Text('Proposal')),
      bottomNavigationBar: _VoteBar(
        proposal: p,
        votedForId: wp.myVoteProposalId,
        votedForTitle: wp.myVotedProposal?.title,
        eligibleReason: _ineligibleReason(auth),
        voting: _voting,
        loadingReceipt: _loadingReceipt,
        onVote: () => _vote(p),
        onShowReceipt: _showReceipt,
      ),
      body: RefreshIndicator(
        onRefresh: wp.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(children: [
              Chip(
                avatar: Icon(categoryIcon(p.category), size: 18),
                label: Text(p.category),
                visualDensity: VisualDensity.compact,
              ),
            ]),
            const SizedBox(height: 8),
            Text(p.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(p.description, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 20),

            // Cost vs ward pool
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total cost', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(inr(p.totalCost),
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: math.min(1.0, share), minHeight: 8),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(share * 100).toStringAsFixed(0)}% of the ward pool (${inrCompact(pool)})',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Text('Budget breakdown',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            BudgetBreakdown(items: p.items, total: p.totalCost),
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
  });

  final Proposal proposal;
  final String? votedForId;
  final String? votedForTitle;
  final String? eligibleReason;
  final bool voting;
  final bool loadingReceipt;
  final VoidCallback onVote;
  final VoidCallback onShowReceipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget content;
    if (votedForId == proposal.id) {
      content = Row(children: [
        const Icon(Icons.check_circle, color: AppTheme.success),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('You voted for this proposal', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        TextButton.icon(
          onPressed: loadingReceipt ? null : onShowReceipt,
          icon: loadingReceipt
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.receipt_long),
          label: const Text('Receipt'),
        ),
      ]);
    } else if (votedForId != null) {
      content = Row(children: [
        Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text('You already voted for "${votedForTitle ?? 'another proposal'}"',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ]);
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

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: content),
      ),
    );
  }
}
