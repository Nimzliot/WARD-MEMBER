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
import '../widgets/ballot_widgets.dart';
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
        body: Column(children: [header, Expanded(child: ErrorView(message: wp.error, error: wp.failure, onRetry: wp.load))]),
      );
    }

    final categories = {for (final p in wp.proposals) p.category}.toList()..sort();
    final visible =
        _category == null ? wp.proposals : wp.proposals.where((p) => p.category == _category).toList();

    return Scaffold(
      bottomNavigationBar: const BallotBar(),
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
                  if (wp.ward != null) PhaseCard(ward: wp.ward!),
                  const SizedBox(height: 12),
                  _IdeasCard(pending: wp.pendingIdeas, total: wp.myIdeas.length, closed: wp.ward?.isClosed ?? false),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _ShortcutCard(
                        icon: Icons.volunteer_activism_rounded,
                        title: 'Ward Fund',
                        subtitle: 'Chip in for projects',
                        onTap: () => context.push('/funds'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ShortcutCard(
                        icon: wp.isWardAdmin ? Icons.inbox_rounded : Icons.forum_rounded,
                        title: wp.isWardAdmin ? 'Resident messages' : 'Ward Admin',
                        subtitle: wp.isWardAdmin ? 'Your inbox · encrypted' : 'Private chat · encrypted',
                        onTap: () => context.push(wp.isWardAdmin ? '/inbox' : '/chat'),
                      ),
                    ),
                  ]),
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
                        isMyVote: wp.isOnMyBallot(p.id),
                        canPick: wp.canVote,
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
              ? 'Requests exceed the pool by ${inrCompact(over)}. Your ballot decides what gets built.'
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

/// Small square shortcut card (Ward Fund, chat).
class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.forest, size: 20),
              ),
              const SizedBox(height: 10),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
            ]),
          ),
        ),
      );
}

/// "Have an idea?" — residents suggest projects; shows how many await review.
class _IdeasCard extends StatelessWidget {
  const _IdeasCard({required this.pending, required this.total, required this.closed});

  final int pending;
  final int total;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final subtitle = total == 0
        ? (closed ? 'Voting has closed for this cycle.' : 'Suggest a project. The ward office reviews it for the ballot.')
        : '$total idea${total == 1 ? '' : 's'} submitted${pending > 0 ? ' · $pending awaiting review' : ''}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/ideas'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.lightbulb_outline_rounded, color: AppColors.forest, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(total == 0 ? 'Have an idea for your ward?' : 'My ideas',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.35)),
              ]),
            ),
            if (pending > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(20)),
                child: Text('$pending', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            const Icon(Icons.chevron_right, color: AppColors.inkMuted),
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
  const _ProposalCard({required this.proposal, required this.pool, required this.isMyVote, required this.canPick});

  final Proposal proposal;
  final int pool;
  final bool isMyVote; // on my submitted ballot
  final bool canPick; // voting open and I haven't voted → show the + / ✓ button

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
                    Text(
                        proposal.fromResident
                            ? '${proposal.category.toUpperCase()} · RESIDENT IDEA'
                            : proposal.category.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                      Text('On your ballot',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                    ]),
                  ),
                if (canPick) ...[const SizedBox(width: 8), PickButton(proposal: proposal)],
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
