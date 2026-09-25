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
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _category; // null = all

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile!;
    final wp = context.watch<WardProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(wp.ward?.name ?? profile.wardName ?? 'My ward'),
            Text('Participatory Budget 2026–27',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: _buildBody(context, wp, profile.fullName),
    );
  }

  Widget _buildBody(BuildContext context, WardProvider wp, String? fullName) {
    if (wp.proposals.isEmpty && (wp.loading || wp.ward == null) && wp.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (wp.error != null && wp.proposals.isEmpty) {
      return ErrorView(message: wp.error!, onRetry: wp.load);
    }

    final categories = {for (final p in wp.proposals) p.category}.toList()..sort();
    final visible = _category == null
        ? wp.proposals
        : wp.proposals.where((p) => p.category == _category).toList();

    return RefreshIndicator(
      onRefresh: wp.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Namaste, ${fullName?.split(' ').first ?? ''} 👋',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (wp.ward != null) _BudgetSummaryCard(ward: wp.ward!, requested: wp.totalRequested, count: wp.proposals.length),
          const SizedBox(height: 12),
          _VoteStatusCard(votedFor: wp.myVotedProposal),
          const SizedBox(height: 16),
          if (categories.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final c in categories) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: Icon(categoryIcon(c), size: 18),
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = _category == c ? null : c),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            const EmptyView(icon: Icons.inbox_outlined, message: 'No proposals in this ward yet.')
          else
            for (final p in visible) ...[
              _ProposalCard(
                proposal: p,
                pool: wp.ward?.budgetPool ?? 0,
                isMyVote: wp.myVoteProposalId == p.id,
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({required this.ward, required this.requested, required this.count});

  final Ward ward;
  final int requested;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final over = requested - ward.budgetPool;
    final fundable = requested == 0 ? 1.0 : math.min(1.0, ward.budgetPool / requested);

    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ward budget pool',
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(inr(ward.budgetPool),
                style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fundable,
                minHeight: 8,
                backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$count proposals ask for ${inrCompact(requested)}. '
              '${over > 0 ? 'That is ${inrCompact(over)} more than the pool — your vote decides what gets funded.' : 'All proposals fit within the pool.'}',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoteStatusCard extends StatelessWidget {
  const _VoteStatusCard({required this.votedFor});

  final Proposal? votedFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final voted = votedFor != null;

    return Card(
      color: voted ? AppTheme.success.withValues(alpha: 0.12) : scheme.tertiaryContainer,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          voted ? Icons.check_circle : Icons.how_to_vote_outlined,
          color: voted ? AppTheme.success : scheme.onTertiaryContainer,
        ),
        title: Text(voted ? 'You have voted' : 'You haven\'t voted yet',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(voted
            ? votedFor!.title
            : 'Open a proposal and cast your one vote for the project you want funded most.'),
        trailing: voted ? const Icon(Icons.chevron_right) : null,
        onTap: voted ? () => context.push('/proposal/${votedFor!.id}') : null,
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal, required this.pool, required this.isMyVote});

  final Proposal proposal;
  final int pool;
  final bool isMyVote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final share = pool == 0 ? 0 : (proposal.totalCost * 100 / pool).round();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/proposal/${proposal.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(categoryIcon(proposal.category), size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(proposal.category,
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
                ),
                if (isMyVote)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle, size: 14, color: AppTheme.success),
                      SizedBox(width: 4),
                      Text('Your vote',
                          style: TextStyle(
                              color: AppTheme.success, fontWeight: FontWeight.w600, fontSize: 12)),
                    ]),
                  )
                else
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ]),
              const SizedBox(height: 8),
              Text(proposal.title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(proposal.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(children: [
                Text(inr(proposal.totalCost),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('$share% of pool · ${proposal.items.length} lines',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
