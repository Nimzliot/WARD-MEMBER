import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/live_results.dart';
import '../providers/ward_provider.dart';
import '../theme.dart';
import '../utils/chart_colors.dart';
import '../utils/format.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  /// Creates the live-results controller; replaceable in tests (no Realtime socket).
  @visibleForTesting
  static LiveResults Function(int wardId) createResults = (wardId) => LiveResults(wardId: wardId)..start();

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  LiveResults? _results;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wardId = context.watch<WardProvider>().wardId;
    if (wardId != null && wardId != _results?.wardId) {
      _results?.dispose();
      _results = ResultsScreen.createResults(wardId);
    }
  }

  @override
  void dispose() {
    _results?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final profile = context.watch<AuthProvider>().profile;
    final results = _results;

    Widget header({Widget? child}) => BrandHeader(
          title: 'Live results',
          subtitle: wp.ward?.name,
          actions: [
            if (results != null)
              ListenableBuilder(listenable: results, builder: (context, _) => _LivePill(live: results.live)),
            const SizedBox(width: 8),
            InitialsAvatar(name: profile?.fullName, onTap: () => context.push('/profile')),
          ],
          child: child,
        );

    if (results == null) {
      return Scaffold(
          body: Column(children: [header(), const Expanded(child: Center(child: CircularProgressIndicator()))]));
    }

    return Scaffold(
      body: ListenableBuilder(
        listenable: results,
        builder: (context, _) {
          if (results.loading || wp.ward == null) {
            return Column(children: [header(), const Expanded(child: Center(child: CircularProgressIndicator()))]);
          }
          if (results.error != null && results.totalVotes == 0) {
            return Column(children: [
              header(),
              Expanded(child: ErrorView(message: results.error!, onRetry: results.refresh)),
            ]);
          }
          final alloc = allocate(wp.proposals, results.counts, wp.ward!.budgetPool);
          return RefreshIndicator(
            onRefresh: () => Future.wait([results.refresh(), wp.load()]),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                header(child: _Turnout(results: results)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Column(children: [
                    // Ward Assistant reads the live numbers (re-runs as votes come in)
                    InsightCard(wardId: wp.ward!.id, totalVotes: results.totalVotes),
                    if (results.totalVotes > 0) const SizedBox(height: 16),
                    _VotesCard(alloc: alloc, totalVotes: results.totalVotes, myVoteId: wp.myVoteProposalId),
                    const SizedBox(height: 16),
                    _AllocationCard(alloc: alloc),
                  ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: live ? AppColors.leaf : Colors.white54, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(live ? 'LIVE' : 'Connecting…',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 0.6)),
        ]),
      );
}

/// Turnout numbers inside the green header.
class _Turnout extends StatelessWidget {
  const _Turnout({required this.results});

  final LiveResults results;

  @override
  Widget build(BuildContext context) {
    final pct = (results.turnout * 100).toStringAsFixed(0);
    final soft = Colors.white.withValues(alpha: 0.8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HeaderLabel('Turnout'),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          HeaderNumber('$pct%', size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${results.totalVotes} of ${results.eligible} verified residents have voted',
                  style: TextStyle(color: soft, fontSize: 13.5, height: 1.3)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        HeroProgress(value: math.min(1.0, results.turnout)),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.schedule, size: 14, color: soft),
          const SizedBox(width: 5),
          Text(results.lastVoteAt == null ? 'No votes yet' : 'Last vote ${timeAgo(results.lastVoteAt!)}',
              style: TextStyle(color: soft, fontSize: 12.5)),
        ]),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, this.subtitle, required this.icon, required this.child});

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: AppColors.forest),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Votes (bar chart)

class _VotesCard extends StatelessWidget {
  const _VotesCard({required this.alloc, required this.totalVotes, required this.myVoteId});

  final Allocation alloc;
  final int totalVotes;
  final String? myVoteId;

  @override
  Widget build(BuildContext context) {
    // Bars in the proposals' fixed order (#1, #2…) so they never jump around.
    final bySlot = [...alloc.ranked]..sort((a, b) => a.slot.compareTo(b.slot));
    final maxVotes = bySlot.fold(0, (m, r) => math.max(m, r.votes));
    final interval = math.max(1, (maxVotes / 4).ceil()).toDouble();
    final maxY = math.max(interval * 4, maxVotes + interval * 0.5);
    const muted = TextStyle(fontSize: 12, color: AppColors.inkMuted);

    return _SectionCard(
      title: 'Votes by proposal',
      subtitle: '$totalVotes vote${totalVotes == 1 ? '' : 's'} cast · updates live',
      icon: Icons.bar_chart_rounded,
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.mintLine, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: interval,
                      getTitlesWidget: (value, meta) =>
                          SideTitleWidget(meta: meta, child: Text(value.toInt().toString(), style: muted)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text('#${value.toInt() + 1}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.forest)),
                      ),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.forestDark,
                    getTooltipItem: (group, _, rod, _) {
                      final r = bySlot[group.x];
                      return BarTooltipItem(
                        '${r.proposal.title}\n${r.votes} vote${r.votes == 1 ? '' : 's'}',
                        const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (final r in bySlot)
                    BarChartGroupData(x: r.slot, barRods: [
                      BarChartRodData(
                        toY: r.votes.toDouble(),
                        width: 26,
                        // one series → one colour; the resident's own choice is highlighted
                        color: r.proposal.id == myVoteId ? AppColors.emerald : AppColors.forest,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Table view: exact numbers, ranked
          for (final (i, r) in alloc.ranked.indexed) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r.proposal.id == myVoteId ? AppColors.emerald : AppColors.mint,
                    shape: BoxShape.circle,
                  ),
                  child: Text('#${r.slot + 1}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: r.proposal.id == myVoteId ? Colors.white : AppColors.forest,
                      )),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.proposal.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (r.proposal.id == myVoteId)
                      const Row(children: [
                        Icon(Icons.check_circle, size: 12, color: AppTheme.success),
                        SizedBox(width: 3),
                        Text('Your vote',
                            style: TextStyle(fontSize: 11.5, color: AppTheme.success, fontWeight: FontWeight.w700)),
                      ]),
                  ]),
                ),
                Text('${r.votes}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                SizedBox(
                  width: 46,
                  child: Text(
                    totalVotes == 0 ? '—' : '${(r.votes * 100 / totalVotes).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: muted,
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Allocation (donut)

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.alloc});

  final Allocation alloc;

  @override
  Widget build(BuildContext context) {
    final funded = alloc.funded;
    final notFunded = alloc.ranked.where((r) => !r.funded).toList();

    return _SectionCard(
      title: 'Fund allocation',
      subtitle: 'Most-voted first, until the ${inrCompact(alloc.pool)} pool runs out',
      icon: Icons.donut_large_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 60,
                    startDegreeOffset: -90,
                    sections: [
                      // funded proposals in rank order: darkest green = most votes
                      for (final (i, r) in funded.indexed)
                        PieChartSectionData(
                          value: r.proposal.totalCost.toDouble(),
                          color: rampColor(i),
                          radius: 28,
                          showTitle: false,
                        ),
                      if (alloc.unallocated > 0)
                        PieChartSectionData(
                          value: alloc.unallocated.toDouble(),
                          color: kNeutralChart,
                          radius: 28,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(inrCompact(alloc.allocated),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.forestDark)),
                  const Text('allocated', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (funded.isEmpty)
            const Text('No votes yet — nothing is funded.', style: TextStyle(color: AppColors.inkMuted)),
          for (final (i, r) in funded.indexed)
            _LegendRow(
              color: rampColor(i),
              label: r.proposal.title,
              value: inrCompact(r.proposal.totalCost),
              caption: '${(r.proposal.totalCost * 100 / alloc.pool).toStringAsFixed(0)}%',
              funded: true,
            ),
          _LegendRow(
            color: kNeutralChart,
            label: 'Unallocated',
            value: inrCompact(alloc.unallocated),
            caption: '${(alloc.unallocated * 100 / alloc.pool).toStringAsFixed(0)}%',
          ),
          if (notFunded.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('NOT FUNDED YET',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.inkMuted)),
                const SizedBox(height: 6),
                for (final r in notFunded)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${r.proposal.title} (${inrCompact(r.proposal.totalCost)}) — '
                      '${r.votes == 0 ? 'no votes' : 'does not fit the remaining pool'}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.35),
                    ),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    required this.caption,
    this.funded = false,
  });

  final Color color;
  final String label;
  final String value;
  final String caption;
  final bool funded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          if (funded) ...[
            const Icon(Icons.check_circle, size: 15, color: AppTheme.success),
            const SizedBox(width: 6),
          ],
          Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          SizedBox(
            width: 44,
            child: Text(caption,
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ),
        ],
      ),
    );
  }
}
