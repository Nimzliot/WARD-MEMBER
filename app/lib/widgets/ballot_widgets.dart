import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../models/ward.dart';
import '../providers/ward_provider.dart';
import '../theme.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import 'common.dart';
import 'vote_receipt_sheet.dart';

/// "2d 04h 13m" / "13m 09s" until [to]; rebuilds itself every second.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.to, this.style, this.onDone});

  final DateTime to;
  final TextStyle? style;
  final VoidCallback? onDone; // fired once when the countdown reaches zero

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_fired && !DateTime.now().isBefore(widget.to)) {
        _fired = true;
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(formatCountdown(widget.to.difference(DateTime.now())), style: widget.style);
}

String formatCountdown(Duration d) {
  if (d.isNegative) return '0m 00s';
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inDays > 0) return '${d.inDays}d ${two(d.inHours % 24)}h ${two(d.inMinutes % 60)}m';
  if (d.inHours > 0) return '${d.inHours}h ${two(d.inMinutes % 60)}m ${two(d.inSeconds % 60)}s';
  return '${d.inMinutes}m ${two(d.inSeconds % 60)}s';
}

/// Phase card on Home: where the ward is in the cycle, with a live countdown.
class PhaseCard extends StatelessWidget {
  const PhaseCard({super.key, required this.ward});

  final Ward ward;

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final phase = ward.phase;
    final deadline = ward.nextDeadline;

    final (IconData icon, String title, String body, Color accent) = switch (phase) {
      WardPhase.upcoming => (
          Icons.schedule_rounded,
          'Voting opens soon',
          'Browse the projects and suggest your own ideas before voting starts.',
          AppColors.emerald,
        ),
      WardPhase.open when wp.hasVoted => (
          Icons.verified_rounded,
          'Your ballot is in',
          '${wp.myBallot!.length} project${wp.myBallot!.length == 1 ? '' : 's'} backed · tap for your receipt',
          AppTheme.success,
        ),
      WardPhase.open => (
          Icons.how_to_vote_rounded,
          'Voting is open',
          'Tick every project you want, up to the ward budget of ${inrCompact(ward.budgetPool)}.',
          AppColors.forest,
        ),
      WardPhase.closed => (
          Icons.emoji_events_rounded,
          'Voting closed · results are final',
          wp.hasVoted ? 'Thank you for voting. See which projects get built.' : 'See which projects get built.',
          AppColors.forestDark,
        ),
    };

    VoidCallback? onTap;
    if (phase == WardPhase.closed) {
      onTap = () => context.go('/results');
    } else if (wp.hasVoted) {
      onTap = () => showMyReceipt(context);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(body, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.35)),
                      ]),
                    ),
                    if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                  ]),
                  if (deadline != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.timer_outlined, size: 18, color: AppColors.forest),
                        const SizedBox(width: 8),
                        Text(phase == WardPhase.upcoming ? 'Opens in ' : 'Closes in ',
                            style: const TextStyle(color: AppColors.forest, fontWeight: FontWeight.w600)),
                        Countdown(
                          to: deadline,
                          onDone: wp.load, // phase flips → refresh
                          style: const TextStyle(
                            color: AppColors.forestDark,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            formatDateTime(deadline),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.inkMuted, fontSize: 11.5),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

Future<void> showMyReceipt(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final receipt = await context.read<WardProvider>().fetchMyReceipt();
    if (!context.mounted) return;
    if (receipt == null) {
      messenger.showSnackBar(const SnackBar(content: Text('No ballot found')));
    } else {
      await showVoteReceipt(context, receipt);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// Round tick button used on proposal cards to add/remove a project from the ballot.
class PickButton extends StatelessWidget {
  const PickButton({super.key, required this.proposal});

  final Proposal proposal;

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final picked = wp.isPicked(proposal.id);
    final fits = wp.fits(proposal);
    return Tooltip(
      message: picked ? 'Remove from ballot' : fits ? 'Add to ballot' : 'Does not fit the remaining budget',
      child: InkResponse(
        radius: 26,
        onTap: () => togglePickWithFeedback(context, proposal),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: picked ? AppColors.forest : Colors.white,
            border: Border.all(color: picked ? AppColors.forest : fits ? AppColors.leaf : AppColors.mintLine, width: 2),
          ),
          child: Icon(
            picked ? Icons.check_rounded : Icons.add_rounded,
            size: 20,
            color: picked ? Colors.white : fits ? AppColors.forest : AppColors.mintLine,
          ),
        ),
      ),
    );
  }
}

void togglePickWithFeedback(BuildContext context, Proposal p) {
  final wp = context.read<WardProvider>();
  if (!wp.togglePick(p)) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${inrCompact(p.totalCost)} won\'t fit — only ${inrCompact(wp.remainingBudget)} left. '
            'Remove a project first.'),
      ));
  }
}

/// Budget meter: how much of the ward pool the current picks use.
class BudgetMeter extends StatelessWidget {
  const BudgetMeter({super.key, required this.used, required this.pool, this.dark = false});

  final int used;
  final int pool;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final v = pool == 0 ? 0.0 : math.min(1.0, used / pool);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: v,
        minHeight: 8,
        color: dark ? AppColors.leaf : AppColors.forest,
        backgroundColor: dark ? Colors.white.withValues(alpha: 0.18) : AppColors.mint,
      ),
    );
  }
}

/// Bottom bar on Home while building a ballot: picks + budget used + Review.
class BallotBar extends StatelessWidget {
  const BallotBar({super.key});

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    if (!wp.canVote) return const SizedBox.shrink();
    final n = wp.picks.length;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: AppColors.forestDark.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              n == 0 ? 'Tap + to add projects' : '$n project${n == 1 ? '' : 's'} · ${inrCompact(wp.pickedCost)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 6),
            BudgetMeter(used: wp.pickedCost, pool: wp.pool),
            const SizedBox(height: 4),
            Text('${inrCompact(wp.remainingBudget)} of ${inrCompact(wp.pool)} left',
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 11.5)),
          ]),
        ),
        const SizedBox(width: 14),
        FilledButton.icon(
          onPressed: n == 0 ? null : () => showBallotReview(context),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 50), padding: const EdgeInsets.symmetric(horizontal: 18)),
          icon: const Icon(Icons.how_to_vote_rounded, size: 20),
          label: const Text('Review', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

Future<void> showBallotReview(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _BallotReviewSheet(),
    );

class _BallotReviewSheet extends StatefulWidget {
  const _BallotReviewSheet();

  @override
  State<_BallotReviewSheet> createState() => _BallotReviewSheetState();
}

class _BallotReviewSheetState extends State<_BallotReviewSheet> {
  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    final wp = context.read<WardProvider>();
    final router = GoRouter.of(context);
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final receipt = await wp.castBallot();
      if (!mounted) return;
      Navigator.pop(context);
      if (!rootContext.mounted) return;
      await showVoteReceipt(rootContext, receipt, justVoted: true, onViewResults: () => router.go('/results'));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final picked = wp.pickedProposals;
    if (picked.isEmpty && !_sending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your ballot', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(wp.ward?.name ?? '', style: const TextStyle(color: AppColors.inkMuted)),
            const SizedBox(height: 16),
            for (final p in picked)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.mintLine),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(inr(p.totalCost), style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: _sending ? null : () => wp.togglePick(p),
                    icon: const Icon(Icons.close_rounded, color: AppColors.inkMuted),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${inr(wp.pickedCost)} of ${inrCompact(wp.pool)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forestDark)),
            ]),
            const SizedBox(height: 8),
            BudgetMeter(used: wp.pickedCost, pool: wp.pool),
            const SizedBox(height: 16),
            const MessageBanner(
              'You get ONE ballot. It cannot be changed after you submit. '
              'Projects with the most backers are funded first until the money runs out.',
              isError: false,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              MessageBanner(_error!),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Submit ballot',
              icon: Icons.how_to_vote_rounded,
              loading: _sending,
              onPressed: picked.isEmpty ? null : _submit,
            ),
          ]),
        ),
      ),
    );
  }
}
