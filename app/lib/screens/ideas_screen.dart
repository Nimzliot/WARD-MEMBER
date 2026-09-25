import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../providers/ward_provider.dart';
import '../theme.dart';
import '../utils/categories.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'proposal_form_screen.dart';

/// Resident: my submitted ideas with their review status, plus "Suggest an idea".
class IdeasScreen extends StatelessWidget {
  const IdeasScreen({super.key});

  Future<void> _newIdea(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProposalFormScreen(mode: ProposalFormMode.idea)),
      );

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final closed = wp.ward?.isClosed ?? false;
    final ideas = wp.myIdeas;

    return Scaffold(
      floatingActionButton: closed
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _newIdea(context),
              icon: const Icon(Icons.lightbulb_outline_rounded),
              label: const Text('Suggest an idea', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
      body: RefreshIndicator(
        onRefresh: wp.load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            BrandHeader(
              showBack: true,
              title: 'My ideas',
              subtitle: wp.ward?.name,
              bottomPadding: 20,
              child: const Text(
                'Suggest a project for your ward. The ward office reviews every idea, and approved '
                'ideas go on the ballot for everyone to vote on.',
                style: TextStyle(color: Colors.white, height: 1.45),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (closed) ...[
                  const MessageBanner('Voting has closed in your ward, so new ideas are not being accepted.',
                      isError: false),
                  const SizedBox(height: 16),
                ],
                SectionTitle('Submitted', count: ideas.length),
                if (ideas.isEmpty)
                  const EmptyView(
                    icon: Icons.lightbulb_outline_rounded,
                    message: 'No ideas yet.\nTap "Suggest an idea". The assistant can draft the budget for you.',
                  )
                else
                  for (final i in ideas) ...[_IdeaCard(idea: i), const SizedBox(height: 12)],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.idea});

  final Proposal idea;

  Future<void> _withdraw(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this idea?'),
        content: Text('"${idea.title}" will be deleted. You can submit it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<WardProvider>().withdrawIdea(idea.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (String label, IconData icon, Color fg, Color bg) = switch (idea.status) {
      ProposalStatus.pending => ('In review', Icons.hourglass_top_rounded, const Color(0xFF8A5A00), const Color(0xFFFFF4DC)),
      ProposalStatus.approved => ('On the ballot', Icons.check_circle_rounded, AppTheme.success, AppColors.mint),
      ProposalStatus.rejected => ('Not approved', Icons.cancel_outlined, const Color(0xFF9B1C1C), const Color(0xFFFDEEEC)),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: idea.isApproved ? () => context.push('/proposal/${idea.id}') : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
                child: Icon(categoryIcon(idea.category), color: AppColors.forest, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(idea.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text('${inr(idea.totalCost)} · ${timeAgo(idea.createdAt)}',
                      style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11.5)),
                ]),
              ),
            ]),
            if (idea.reviewNote?.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
                child: Text('Ward office: ${idea.reviewNote}',
                    style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.ink)),
              ),
            ],
            if (idea.status == ProposalStatus.pending)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _withdraw(context),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Withdraw'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
