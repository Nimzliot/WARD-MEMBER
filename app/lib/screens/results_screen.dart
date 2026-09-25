import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/live_results.dart';
import '../providers/ward_provider.dart';
import '../theme.dart';
import '../utils/chart_colors.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

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
      _results = LiveResults(wardId: wardId)..start();
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
    final results = _results;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live results'),
        actions: [
          if (results != null)
            ListenableBuilder(
              listenable: results,
              builder: (context, _) => _LiveChip(live: results.live),
            ),
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: results == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: results,
              builder: (context, _) {
                if (results.loading || wp.ward == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (results.error != null && results.totalVotes == 0) {
                  return ErrorView(message: results.error!, onRetry: results.refresh);
                }
                final alloc = allocate(wp.proposals, results.counts, wp.ward!.budgetPool);
                return RefreshIndicator(
                  onRefresh: () => Future.wait([results.refresh(), wp.load()]),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _TurnoutCard(results: results, wardName: wp.ward!.name),
                      const SizedBox(height: 16),
                      _VotesCard(alloc: alloc, totalVotes: results.totalVotes, myVoteId: wp.myVoteProposalId),
                      const SizedBox(height: 16),
                      _AllocationCard(alloc: alloc),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = live ? AppTheme.success : Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(live ? 'LIVE' : 'Connecting…',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Turnout

class _TurnoutCard extends StatelessWidget {
  const _TurnoutCard({required this.results, required this.wardName});

  final LiveResults results;
  final String wardName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = (results.turnout * 100).toStringAsFixed(0);

    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Turnout · $wardName',
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$pct%',
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${results.totalVotes} of ${results.eligible} verified residents voted',
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: math.min(1.0, results.turnout),
                minHeight: 8,
                backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              results.lastVoteAt == null ? 'No votes yet' : 'Last vote ${timeAgo(results.lastVoteAt!)}',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Bars in the proposals' fixed order so colours and numbers never move.
    final bySlot = [...alloc.ranked]..sort((a, b) => a.slot.compareTo(b.slot));
    final maxVotes = bySlot.fold(0, (m, r) => math.max(m, r.votes));
    final interval = math.max(1, (maxVotes / 4).ceil()).toDouble();
    final maxY = math.max(interval * 4, maxVotes + interval * 0.5);

    return _SectionCard(
      title: 'Votes by proposal',
      subtitle: '$totalVotes vote${totalVotes == 1 ? '' : 's'} cast · updates live',
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: interval,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(value.toInt().toString(),
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text('#${value.toInt() + 1}',
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => scheme.inverseSurface,
                    getTooltipItem: (group, _, rod, _) {
                      final r = bySlot[group.x];
                      return BarTooltipItem(
                        '${r.proposal.title}\n${r.votes} vote${r.votes == 1 ? '' : 's'}',
                        TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (final r in bySlot)
                    BarChartGroupData(x: r.slot, barRods: [
                      BarChartRodData(
                        toY: r.votes.toDouble(),
                        width: 22,
                        color: slotColor(context, r.slot),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Table view: exact numbers for every bar.
          for (final r in alloc.ranked)
            _LegendRow(
              color: slotColor(context, r.slot),
              label: '#${r.slot + 1}  ${r.proposal.title}',
              trailing: '${r.votes}',
              caption: totalVotes == 0 ? '—' : '${(r.votes * 100 / totalVotes).toStringAsFixed(0)}%',
              badge: r.proposal.id == myVoteId ? 'Your vote' : null,
            ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final funded = alloc.funded;
    final notFunded = alloc.ranked.where((r) => !r.funded).toList();

    return _SectionCard(
      title: 'Fund allocation',
      subtitle: 'Most-voted proposals are funded first until the ${inrCompact(alloc.pool)} pool runs out',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 62,
                    startDegreeOffset: -90,
                    sections: [
                      for (final r in funded)
                        PieChartSectionData(
                          value: r.proposal.totalCost.toDouble(),
                          color: slotColor(context, r.slot),
                          radius: 30,
                          showTitle: false,
                        ),
                      if (alloc.unallocated > 0)
                        PieChartSectionData(
                          value: alloc.unallocated.toDouble(),
                          color: neutralColor(context),
                          radius: 30,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(inrCompact(alloc.allocated),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text('allocated',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (funded.isEmpty)
            Text('No votes yet — nothing is funded.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          for (final r in funded)
            _LegendRow(
              color: slotColor(context, r.slot),
              label: r.proposal.title,
              trailing: inrCompact(r.proposal.totalCost),
              caption: '${(r.proposal.totalCost * 100 / alloc.pool).toStringAsFixed(0)}%',
              icon: Icons.check_circle,
            ),
          _LegendRow(
            color: neutralColor(context),
            label: 'Unallocated',
            trailing: inrCompact(alloc.unallocated),
            caption: '${(alloc.unallocated * 100 / alloc.pool).toStringAsFixed(0)}%',
          ),
          if (notFunded.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Not funded', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final r in notFunded)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${r.proposal.title} (${inrCompact(r.proposal.totalCost)}) — '
                  '${r.votes == 0 ? 'no votes' : 'does not fit the remaining pool'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
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
    required this.trailing,
    required this.caption,
    this.badge,
    this.icon,
  });

  final Color color;
  final String label;
  final String trailing;
  final String caption;
  final String? badge;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
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
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label),
                if (badge != null)
                  TextSpan(
                    text: '  ✓ $badge',
                    style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600),
                  ),
              ]),
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (icon != null) ...[Icon(icon, size: 16, color: AppTheme.success), const SizedBox(width: 4)],
          Text(trailing, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(
            width: 44,
            child: Text(caption,
                textAlign: TextAlign.right, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
        ],
      ),
    );
  }
}
