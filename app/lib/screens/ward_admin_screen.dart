import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../models/ward.dart';
import '../providers/ward_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/categories.dart';
import '../utils/errors.dart';
import '../utils/failure.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/contributions_view.dart';
import '../widgets/failure_view.dart';
import 'inbox_screen.dart';
import 'proposal_form_screen.dart';

/// Ward Admin console: control of ONE ward (the admin's own).
/// Overview · Ideas · Proposals · Fund · Messages.
/// Total control over every ward stays with the super admin's Admin panel.
class WardAdminScreen extends StatefulWidget {
  const WardAdminScreen({super.key});

  @override
  State<WardAdminScreen> createState() => _WardAdminScreenState();
}

class _WardAdminScreenState extends State<WardAdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  Map<String, dynamic>? _overview;
  List<Proposal> _proposals = [];
  Map<String, dynamic>? _funds;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        ApiService.get('/api/ward-admin/overview'),
        ApiService.get('/api/ward-admin/proposals'),
        ApiService.get('/api/ward-admin/contributions'),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = r[0];
        _proposals = [for (final p in r[1]['proposals'] as List) Proposal.fromMap(p as Map<String, dynamic>)];
        _funds = r[2];
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    final wp = context.read<WardProvider>();
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      await _load();
      wp.load();
    } catch (e) {
      if (mounted && !await showFailure(context, e) && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _form(ProposalFormMode mode, [Proposal? p]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProposalFormScreen(mode: mode, proposal: p, asWardAdmin: true)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    // Only this ward's admin gets in (the server enforces it too).
    if (_error != null && AppFailure.from(_error!).kind == FailureKind.accessDenied) {
      return FailureScreen(failure: AppFailure.from(_error!));
    }
    final ward = _overview == null ? null : Ward.fromMap(_overview!['ward'] as Map<String, dynamic>);
    final pending = _proposals.where((p) => p.status == ProposalStatus.pending).toList();

    return Scaffold(
      floatingActionButton: switch (_tabs.index) {
        2 => FloatingActionButton.extended(
            onPressed: () => _form(ProposalFormMode.create),
            icon: const Icon(Icons.add),
            label: const Text('New proposal'),
          ),
        3 => FloatingActionButton.extended(
            onPressed: () async {
              await context.push('/funds');
              _load();
            },
            icon: const Icon(Icons.volunteer_activism_rounded),
            label: const Text('Manage fundraisers'),
          ),
        _ => null,
      },
      body: Column(children: [
        BrandHeader(
          showBack: true,
          title: 'Ward Admin',
          subtitle: ward?.name ?? 'Your ward',
          bottomPadding: 0,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
            indicatorColor: AppColors.leaf,
            indicatorWeight: 3,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Jakarta'),
            tabs: [
              const Tab(text: 'Overview'),
              _badgeTab('Ideas', pending.length),
              const Tab(text: 'Proposals'),
              const Tab(text: 'Fund'),
              _badgeTab('Messages', (_overview?['unread_messages'] as num?)?.toInt() ?? 0),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(error: _error, onRetry: _load)
                  : TabBarView(controller: _tabs, children: [
                      _overviewTab(ward!),
                      _ideasTab(pending),
                      _proposalsTab(),
                      RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          children: [ContributionsView(data: _funds ?? const {})],
                        ),
                      ),
                      const InboxScreen(embedded: true),
                    ]),
        ),
      ]),
    );
  }

  Tab _badgeTab(String label, int n) => Tab(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          if (n > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: AppColors.leaf, borderRadius: BorderRadius.circular(10)),
              child: Text('$n', style: const TextStyle(color: AppColors.forestDark, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      );

  // ---------------- Overview ----------------

  Widget _overviewTab(Ward ward) {
    final o = _overview!;
    Widget tile(IconData icon, String value, String label, {VoidCallback? onTap}) => Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: AppColors.forest),
                  const SizedBox(height: 8),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.forestDark)),
                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ]),
              ),
            ),
          ),
        );
    final phase = switch (ward.phase) {
      WardPhase.upcoming => 'Voting opens ${ward.votingOpensAt == null ? '' : formatDateTime(ward.votingOpensAt!)}',
      WardPhase.open => 'Voting open${ward.votingClosesAt == null ? '' : ' until ${formatDateTime(ward.votingClosesAt!)}'}',
      WardPhase.closed => 'Voting closed · results final',
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        MessageBanner(
          'You are the Ward Admin of ${ward.name}. You manage this ward\'s ideas, proposals, fundraisers and resident '
          'messages. Budgets, voting dates and roles are set by the super admin.',
          isError: false,
        ),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            leading: const Icon(Icons.how_to_vote_rounded, color: AppColors.forest),
            title: Text(phase, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Pool ${inr(ward.budgetPool)} · ${o['ballots']} ballots from ${o['residents']} residents'),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          tile(Icons.lightbulb_outline_rounded, '${o['pending_ideas']}', 'ideas to review', onTap: () => _tabs.animateTo(1)),
          tile(Icons.list_alt_rounded, '${o['approved']}', 'on the ballot', onTap: () => _tabs.animateTo(2)),
        ]),
        Row(children: [
          tile(Icons.volunteer_activism_rounded, inrCompact(o['raised'] as num), 'raised · ${o['active_funds']} active',
              onTap: () => _tabs.animateTo(3)),
          tile(Icons.forum_rounded, '${o['unread_messages']}', 'unread messages', onTap: () => _tabs.animateTo(4)),
        ]),
      ]),
    );
  }

  // ---------------- Ideas ----------------

  Widget _ideasTab(List<Proposal> pending) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          if (pending.isEmpty) const EmptyView(icon: Icons.task_alt_rounded, message: 'No ideas waiting for review.'),
          for (final p in pending)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.category.toUpperCase(),
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.emerald)),
                  const SizedBox(height: 4),
                  Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('${inr(p.totalCost)} · ${p.items.length} budget lines · ${timeAgo(p.createdAt)}',
                      style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
                  if (p.description.isNotEmpty) ...[const SizedBox(height: 8), Text(p.description)],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _run(
                          () => ApiService.patch('/api/ward-admin/proposals/${p.id}', {'status': 'approved'}),
                          'Approved: "${p.title}" is on the ballot',
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: () => _form(ProposalFormMode.edit, p), child: const Text('Edit')),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _reject(p),
                      style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                      child: const Text('Reject'),
                    ),
                  ]),
                ]),
              ),
            ),
        ]),
      );

  Future<void> _reject(Proposal p) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this idea?'),
        content: TextField(
          controller: note,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Reason (shown to the resident)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true) return;
    await _run(
      () => ApiService.patch('/api/ward-admin/proposals/${p.id}', {'status': 'rejected', 'reviewNote': text}),
      'Idea rejected',
    );
  }

  // ---------------- Proposals ----------------

  Widget _proposalsTab() {
    final list = _proposals.where((p) => p.status != ProposalStatus.pending).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        if (list.isEmpty) const EmptyView(icon: Icons.inbox_outlined, message: 'No proposals yet.'),
        for (final p in list)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
              onTap: () => _form(ProposalFormMode.edit, p),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
                child: Icon(categoryIcon(p.category), color: AppColors.forest, size: 21),
              ),
              title: Text(p.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: p.status == ProposalStatus.rejected ? TextDecoration.lineThrough : null,
                  )),
              subtitle: Text('${inrCompact(p.totalCost)}${p.fromResident ? ' · resident idea' : ''}'
                  '${p.status == ProposalStatus.rejected ? ' · not on ballot' : ''}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      await _form(ProposalFormMode.edit, p);
                    case 'unlist':
                      await _run(() => ApiService.patch('/api/ward-admin/proposals/${p.id}', {'status': 'rejected'}),
                          'Removed from the ballot');
                    case 'restore':
                      await _run(() => ApiService.patch('/api/ward-admin/proposals/${p.id}', {'status': 'approved'}),
                          'Back on the ballot');
                    case 'delete':
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Delete "${p.title}"?'),
                          content: const Text('Ballots that included it stay valid, but it no longer counts in results.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true) await _run(() => ApiService.delete('/api/ward-admin/proposals/${p.id}'), 'Deleted');
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (p.status == ProposalStatus.approved) const PopupMenuItem(value: 'unlist', child: Text('Remove from ballot')),
                  if (p.status == ProposalStatus.rejected) const PopupMenuItem(value: 'restore', child: Text('Put back on ballot')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete…')),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}
