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
import '../widgets/brand.dart';
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
    final firstName = profile.fullName?.trim().split(' ').first ?? '';

    final header = BrandHeader(
      title: 'Namaste, $firstName',
      subtitle: '${wp.ward?.name ?? profile.wardName ?? 'My ward'} · Budget 2026–27',
      actions: [InitialsAvatar(name: profile.fullName, onTap: () => context.push('/profile'))],
      bottomPadding: 48, // room for the overlapping assistant card
      child: wp.ward == null
          ? null
          : _PoolSummary(ward: wp.ward!, requested: wp.totalRequested, count: wp.proposals.length),
    );

    if (wp.proposals.isEmpty && wp.error == null) {
      return Scaffold(
        body: Column(children: [header, const Expanded(child: Center(child: CircularProgressIndicator()))]),
      );
    }
    if (wp.error != null && wp.proposals.isEmpty) {
      return Scaffold(
        body: Column(children: [header, Expanded(child: ErrorView(message: wp.error!, onRetry: wp.load))]),
      );
    }

    final categories = {for (final p in wp.proposals) p.category}.toList()..sort();
    final visible =
        _category == null ? wp.proposals : wp.proposals.where((p) => p.category == _category).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: wp.load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            header,
            const OverlapHeader(
              by: 30,
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: _AssistantBanner()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _VoteStatusCard(votedFor: wp.myVotedProposal),
                  const SizedBox(height: 24),
                  SectionTitle('Proposals', count: wp.proposals.length),
                  if (categories.length > 1) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _FilterChip(label: 'All', selected: _category == null, onTap: () => setState(() => _category = null)),
                        for (final c in categories)
                          _FilterChip(
                            label: c,
                            icon: categoryIcon(c),
                            selected: _category == c,
                            onTap: () => setState(() => _category = _category == c ? null : c),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Budget pool numbers shown inside the green header.
class _PoolSummary extends StatelessWidget {
  const _PoolSummary({required this.ward, required this.requested, required this.count});

  final Ward ward;
  final int requested;
  final int count;

  @override
  Widget build(BuildContext context) {
    final over = requested - ward.budgetPool;
    final fundable = requested == 0 ? 1.0 : math.min(1.0, ward.budgetPool / requested);

    Widget tile(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5)),
            ]),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HeaderLabel('Ward budget pool'),
        const SizedBox(height: 2),
        HeaderNumber(inr(ward.budgetPool)),
        const SizedBox(height: 14),
        Row(children: [
          tile('$count', 'proposals'),
          const SizedBox(width: 8),
          tile(inrCompact(requested), 'requested'),
          const SizedBox(width: 8),
          tile('${(fundable * 100).round()}%', 'can be funded'),
        ]),
        const SizedBox(height: 14),
        HeroProgress(value: fundable),
        const SizedBox(height: 8),
        Text(
          over > 0
              ? 'Requests exceed the pool by ${inrCompact(over)}. Your vote decides what gets built.'
              : 'All proposals fit within the pool.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }
}

/// Entry point to the Ward Assistant (AI) tab, floating over the header edge.
class _AssistantBanner extends StatelessWidget {
  const _AssistantBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1.6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.leaf, AppColors.emerald, AppColors.forest]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.forestDark.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.4),
        child: InkWell(
          borderRadius: BorderRadius.circular(18.4),
          onTap: () => context.go('/assistant'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(gradient: AppTheme.aiGradient, shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome, color: Colors.white),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ask Ward Assistant',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.forestDark)),
                  SizedBox(height: 2),
                  Text('AI answers about your ward budget · English, தமிழ், हिंदी',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                ]),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, color: AppColors.forest, size: 18),
              ),
            ]),
          ),
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
    final voted = votedFor != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: voted ? () => context.push('/proposal/${votedFor!.id}') : null,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: voted ? AppTheme.success : AppColors.leaf),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: voted ? AppTheme.success.withValues(alpha: 0.12) : AppColors.mint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(voted ? Icons.check_rounded : Icons.how_to_vote_outlined,
                        color: voted ? AppTheme.success : AppColors.forest, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(voted ? 'You have voted' : 'You haven\'t voted yet',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        voted ? votedFor!.title : 'Pick the one project you want funded most.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
                      ),
                    ]),
                  ),
                  if (voted) const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? AppColors.forest : Colors.white,
          shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.forest : AppColors.mintLine)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: selected ? Colors.white : AppColors.forest),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.ink,
                    )),
              ]),
            ),
          ),
        ),
      );
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal, required this.pool, required this.isMyVote});

  final Proposal proposal;
  final int pool;
  final bool isMyVote;

  @override
  Widget build(BuildContext context) {
    final share = pool == 0 ? 0.0 : proposal.totalCost / pool;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: isMyVote
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppTheme.success, width: 1.6),
            )
          : null,
      child: InkWell(
        onTap: () => context.push('/proposal/${proposal.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(13)),
                  child: Icon(categoryIcon(proposal.category), color: AppColors.forest, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(proposal.category.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: AppColors.emerald)),
                    const SizedBox(height: 3),
                    Text(proposal.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.25)),
                  ]),
                ),
                if (isMyVote)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.success, borderRadius: BorderRadius.circular(20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 3),
                      Text('Your vote',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(proposal.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.inkMuted, fontSize: 13.5, height: 1.45)),
              const SizedBox(height: 14),
              Row(children: [
                Text(inr(proposal.totalCost),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.forestDark)),
                const Spacer(),
                SizedBox(
                  width: 54,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: math.min(1.0, share), minHeight: 6),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${(share * 100).round()}% of pool',
                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome, size: 13, color: AppColors.emerald),
                    SizedBox(width: 5),
                    Text('AI explain',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.forest)),
                  ]),
                ),
                const Spacer(),
                const Text('View details',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.forest)),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.forest),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
