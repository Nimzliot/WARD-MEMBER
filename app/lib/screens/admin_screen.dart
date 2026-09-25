import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/proposal.dart';
import '../models/ward.dart';
import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/categories.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/failure_view.dart';
import 'proposal_form_screen.dart';

/// Admins only (guarded in router.dart and again by the server).
/// Full control: voting windows, wards, proposals, resident ideas, people, ballots.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

/// A ward row from GET /api/admin/wards (with counts).
class _AdminWard {
  _AdminWard(Map<String, dynamic> m)
      : ward = Ward.fromMap(m),
        approved = (m['approved'] as num?)?.toInt() ?? 0,
        pending = (m['pending'] as num?)?.toInt() ?? 0,
        ballots = (m['ballots'] as num?)?.toInt() ?? 0;

  final Ward ward;
  final int approved;
  final int pending;
  final int ballots;
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  List<_AdminWard> _wards = [];
  List<Proposal> _proposals = [];
  bool _loading = true;
  String? _error;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {})); // FAB depends on the tab
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait<dynamic>([
        ApiService.get('/api/admin/wards'),
        // Admins can read every proposal (RLS), including pending / rejected ideas.
        Supabase.instance.client.from('proposals').select('*, budget_items(*)').order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _wards = [for (final w in (r[0]['wards'] as List)) _AdminWard(w as Map<String, dynamic>)];
        _proposals = [for (final p in r[1] as List) Proposal.fromMap(p as Map<String, dynamic>)];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _failure = e;
          _loading = false;
        });
      }
    }
  }

  /// Runs an admin action, shows its message, reloads admin + resident data.
  Future<void> _run(Future<Map<String, dynamic>> Function() action, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    final wp = context.read<WardProvider>();
    try {
      final res = await action();
      messenger.showSnackBar(SnackBar(content: Text(done ?? res['message']?.toString() ?? 'Done')));
      await _load();
      wp.load();
    } catch (e) {
      if (mounted && await showFailure(context, e)) return;
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _openForm(ProposalFormMode mode, [Proposal? p]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProposalFormScreen(mode: mode, proposal: p)),
    );
    if (saved == true) _load();
  }

  String _wardName(int id) => _wards.where((w) => w.ward.id == id).firstOrNull?.ward.name ?? 'Ward $id';

  @override
  Widget build(BuildContext context) {
    final pending = _proposals.where((p) => p.status == ProposalStatus.pending).toList();
    final fab = switch (_tabs.index) {
      0 => FloatingActionButton.extended(
          onPressed: () => _editWard(null),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('New ward'),
        ),
      1 => FloatingActionButton.extended(
          onPressed: () => _openForm(ProposalFormMode.create),
          icon: const Icon(Icons.add),
          label: const Text('New proposal'),
        ),
      _ => null,
    };

    return Scaffold(
      floatingActionButton: fab,
      body: Column(children: [
        BrandHeader(
          showBack: true,
          title: 'Admin panel',
          subtitle: 'Wards, proposals, ideas and people',
          bottomPadding: 0,
          actions: [
            HeaderIconButton(
              icon: Icons.report_gmailerrorred_rounded,
              tooltip: 'Error pages',
              onPressed: () => GoRouter.of(context).push('/admin/errors'),
            ),
          ],
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
              const Tab(text: 'Wards'),
              const Tab(text: 'Proposals'),
              Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Ideas'),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.leaf, borderRadius: BorderRadius.circular(10)),
                      child: Text('${pending.length}',
                          style: const TextStyle(color: AppColors.forestDark, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ]),
              ),
              const Tab(text: 'People'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(message: _error, error: _failure, onRetry: _load)
                  : TabBarView(controller: _tabs, children: [
                      _wardsTab(),
                      _proposalsTab(),
                      _ideasTab(pending),
                      _PeopleTab(wards: [for (final w in _wards) w.ward], onChanged: _load),
                    ]),
        ),
      ]),
    );
  }

  // ============================== Wards ==============================

  Widget _wardsTab() => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            for (final w in _wards) ...[_wardCard(w), const SizedBox(height: 12)],
          ],
        ),
      );

  Widget _wardCard(_AdminWard aw) {
    final w = aw.ward;
    final phase = w.phase;
    final (String label, Color color) = switch (phase) {
      WardPhase.upcoming => ('Upcoming', const Color(0xFF8A5A00)),
      WardPhase.open => ('Voting open', AppTheme.success),
      WardPhase.closed => ('Closed · final', AppColors.inkMuted),
    };
    String when(DateTime? d, String none) => d == null ? none : formatDateTime(d);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => _wardAction(aw, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit name, budget & dates')),
                if (phase != WardPhase.open) const PopupMenuItem(value: 'open', child: Text('Open voting now (7 days)')),
                if (phase != WardPhase.closed) const PopupMenuItem(value: 'close', child: Text('Close voting now')),
                const PopupMenuItem(value: 'reset', child: Text('Reset ballot box…')),
                if (aw.ballots == 0) const PopupMenuItem(value: 'delete', child: Text('Delete ward…')),
              ],
            ),
          ]),
          const SizedBox(height: 4),
          Text('Pool ${inr(w.budgetPool)}', style: const TextStyle(color: AppColors.forestDark, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _kv(Icons.play_circle_outline, 'Opens', when(w.votingOpensAt, 'Already open')),
          _kv(Icons.stop_circle_outlined, 'Closes', when(w.votingClosesAt, 'No deadline')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _pill('${aw.approved} on ballot'),
            if (aw.pending > 0) _pill('${aw.pending} idea${aw.pending == 1 ? '' : 's'} to review', strong: true),
            _pill('${aw.ballots} ballot${aw.ballots == 1 ? '' : 's'}'),
          ]),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  Widget _kv(IconData icon, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.inkMuted),
          const SizedBox(width: 6),
          SizedBox(width: 56, child: Text(k, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _pill(String t, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: strong ? AppColors.forest : AppColors.mint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: strong ? Colors.white : AppColors.forest)),
      );

  Future<void> _wardAction(_AdminWard aw, String action) async {
    final id = aw.ward.id;
    switch (action) {
      case 'edit':
        await _editWard(aw.ward);
      case 'open':
        await _run(() => ApiService.patch('/api/admin/wards/$id', {
              'votingOpensAt': 'now',
              'votingClosesAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
            }));
      case 'close':
        if (await _confirm('Close voting in ${aw.ward.name}?',
            'No more ballots will be accepted and the results become final.', 'Close voting')) {
          await _run(() => ApiService.patch('/api/admin/wards/$id', {'votingClosesAt': 'now'}));
        }
      case 'reset':
        if (await _confirm(
          'Reset the ballot box?',
          'This permanently deletes all ${aw.ballots} ballot(s) in ${aw.ward.name}. '
              'Residents will be able to vote again. This cannot be undone.',
          'Delete ballots',
          danger: true,
        )) {
          await _run(() => ApiService.delete('/api/admin/wards/$id/votes'));
        }
      case 'delete':
        if (await _confirm('Delete ${aw.ward.name}?', 'Its proposals are deleted too.', 'Delete', danger: true)) {
          await _run(() => ApiService.delete('/api/admin/wards/$id'));
        }
    }
  }

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  /// Create ([ward] == null) or edit a ward: name, budget pool, voting window.
  Future<void> _editWard(Ward? ward) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WardSheet(ward: ward),
    );
    if (saved == true) {
      await _load();
      if (mounted) context.read<WardProvider>().load();
    }
  }

  // ============================== Proposals ==============================

  int? _proposalWard; // filter

  Widget _proposalsTab() {
    final list = _proposals
        .where((p) => p.status != ProposalStatus.pending && (_proposalWard == null || p.wardId == _proposalWard))
        .toList()
      ..sort((a, b) => a.wardId != b.wardId ? a.wardId.compareTo(b.wardId) : a.createdAt.compareTo(b.createdAt));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All wards'),
                  selected: _proposalWard == null,
                  onSelected: (_) => setState(() => _proposalWard = null),
                ),
              ),
              for (final w in _wards)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(w.ward.name.split('–').first.trim()),
                    selected: _proposalWard == w.ward.id,
                    onSelected: (_) => setState(() => _proposalWard = w.ward.id),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty) const EmptyView(icon: Icons.inbox_outlined, message: 'No proposals here yet.'),
          for (final p in list) ...[_proposalTile(p), const SizedBox(height: 10)],
        ],
      ),
    );
  }

  Widget _proposalTile(Proposal p) {
    final rejected = p.status == ProposalStatus.rejected;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
          child: Icon(categoryIcon(p.category), color: AppColors.forest, size: 21),
        ),
        title: Text(p.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration: rejected ? TextDecoration.lineThrough : null,
              color: rejected ? AppColors.inkMuted : null,
            )),
        subtitle: Text(
          '${_wardName(p.wardId)} · ${inrCompact(p.totalCost)}'
          '${p.fromResident ? ' · resident idea' : ''}${rejected ? ' · rejected' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _openForm(ProposalFormMode.edit, p),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                await _openForm(ProposalFormMode.edit, p);
              case 'unlist':
                await _run(() => ApiService.patch('/api/admin/proposals/${p.id}', {'status': 'rejected'}),
                    done: 'Removed from the ballot');
              case 'restore':
                await _run(() => ApiService.patch('/api/admin/proposals/${p.id}', {'status': 'approved'}),
                    done: 'Back on the ballot');
              case 'delete':
                if (await _confirm('Delete "${p.title}"?',
                    'Ballots that included it stay valid in the audit, but it no longer counts in results.', 'Delete',
                    danger: true)) {
                  await _run(() => ApiService.delete('/api/admin/proposals/${p.id}'));
                }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (!rejected) const PopupMenuItem(value: 'unlist', child: Text('Remove from ballot')),
            if (rejected) const PopupMenuItem(value: 'restore', child: Text('Put back on ballot')),
            const PopupMenuItem(value: 'delete', child: Text('Delete…')),
          ],
        ),
      ),
    );
  }

  // ============================== Ideas ==============================

  Widget _ideasTab(List<Proposal> pending) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (pending.isEmpty)
              const EmptyView(icon: Icons.task_alt_rounded, message: 'No ideas waiting for review.')
            else
              for (final p in pending) ...[_ideaCard(p), const SizedBox(height: 12)],
          ],
        ),
      );

  Widget _ideaCard(Proposal p) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_wardName(p.wardId).toUpperCase()} · ${p.category.toUpperCase()}',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.emerald)),
            const SizedBox(height: 4),
            Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('${inr(p.totalCost)} · ${p.items.length} budget line${p.items.length == 1 ? '' : 's'} · ${timeAgo(p.createdAt)}',
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(p.description, style: const TextStyle(height: 1.4)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _run(() => ApiService.patch('/api/admin/proposals/${p.id}', {'status': 'approved'}),
                      done: 'Approved: "${p.title}" is on the ballot'),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _openForm(ProposalFormMode.edit, p), child: const Text('Edit')),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _reject(p),
                style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                child: const Text('Reject'),
              ),
            ]),
          ]),
        ),
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
      () => ApiService.patch('/api/admin/proposals/${p.id}', {'status': 'rejected', 'reviewNote': text}),
      done: 'Idea rejected',
    );
  }
}

// ============================== Ward sheet ==============================

class _WardSheet extends StatefulWidget {
  const _WardSheet({required this.ward});

  final Ward? ward;

  @override
  State<_WardSheet> createState() => _WardSheetState();
}

class _WardSheetState extends State<_WardSheet> {
  late final _name = TextEditingController(text: widget.ward?.name ?? '');
  late final _pool = TextEditingController(text: widget.ward == null ? '' : '${widget.ward!.budgetPool}');
  late DateTime? _opens = widget.ward?.votingOpensAt ?? DateTime.now();
  late DateTime? _closes = widget.ward?.votingClosesAt ?? DateTime.now().add(const Duration(days: 14));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pool.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) async {
    final start = initial ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    final pool = int.tryParse(_pool.text);
    if (_name.text.trim().length < 2) return setState(() => _error = 'Enter a ward name');
    if (pool == null || pool <= 0) return setState(() => _error = 'Enter the budget pool in rupees');
    if (_opens != null && _closes != null && !_closes!.isAfter(_opens!)) {
      return setState(() => _error = 'Voting must close after it opens');
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'budgetPool': pool,
      'votingOpensAt': _opens?.toUtc().toIso8601String(),
      'votingClosesAt': _closes?.toUtc().toIso8601String(),
    };
    try {
      if (widget.ward == null) {
        await ApiService.post('/api/admin/wards', body);
      } else {
        await ApiService.patch('/api/admin/wards/${widget.ward!.id}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dateRow(String label, DateTime? value, String none, ValueChanged<DateTime?> set) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.mintLine),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
              Text(value == null ? none : formatDateTime(value), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(
            tooltip: 'Change',
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () async {
              final d = await _pick(value);
              if (d != null) setState(() => set(d));
            },
          ),
          if (value != null)
            IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: () => setState(() => set(null))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.ward == null ? 'New ward' : 'Edit ward',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Ward 4 – River Side'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pool,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
              decoration: const InputDecoration(labelText: 'Budget pool', prefixText: '₹ '),
              onChanged: (_) => setState(() {}),
            ),
            if (int.tryParse(_pool.text) != null) ...[
              const SizedBox(height: 4),
              Text(inr(int.parse(_pool.text)), style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
            ],
            const SizedBox(height: 16),
            const Text('Voting window', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _dateRow('Opens', _opens, 'Already open', (d) => _opens = d),
            _dateRow('Closes', _closes, 'No deadline', (d) => _closes = d),
            if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 12)],
            const SizedBox(height: 6),
            PrimaryButton(label: widget.ward == null ? 'Create ward' : 'Save', loading: _saving, onPressed: _save),
          ]),
        ),
      );
}

// ============================== People ==============================

class _PeopleTab extends StatefulWidget {
  const _PeopleTab({required this.wards, required this.onChanged});

  final List<Ward> wards;
  final VoidCallback onChanged;

  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = Uri.encodeQueryComponent(_q.text.trim());
      final res = await ApiService.get('/api/admin/users${q.isEmpty ? '' : '?q=$q'}');
      if (!mounted) return;
      setState(() => _users = (res['users'] as List).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(Map<String, dynamic> u, Map<String, dynamic> body, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    try {
      await ApiService.patch('/api/admin/users/${u['id']}', body);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (u['id'] == auth.user?.id) auth.loadProfile();
      widget.onChanged();
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _changeWard(Map<String, dynamic> u) async {
    final ward = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Move ${u['full_name'] ?? 'resident'} to…'),
        children: [
          for (final w in widget.wards)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, w.id), child: Text(w.name)),
        ],
      ),
    );
    if (ward != null) await _update(u, {'wardId': ward}, 'Ward changed');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final me = context.watch<AuthProvider>().user?.id;
    String wardName(Object? id) => widget.wards.where((w) => w.id == id).firstOrNull?.name.split('–').first.trim() ?? 'No ward';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search name, email, phone or Resident ID',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Column(children: [
              MessageBanner(_error!),
              TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ])
          else if (_users.isEmpty)
            const EmptyView(icon: Icons.person_search_outlined, message: 'Nobody found.')
          else
            for (final u in _users)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                  leading: InitialsAvatar(name: u['full_name'] as String?, size: 40),
                  title: Row(children: [
                    Flexible(
                      child: Text(u['full_name'] as String? ?? '(no name yet)',
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (u['role'] == 'admin') ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.admin_panel_settings, size: 16, color: AppColors.forest),
                    ],
                  ]),
                  subtitle: Text(
                    [
                      wardName(u['ward_id']),
                      u['resident_id'] ?? 'no Resident ID',
                      if (u['phone'] != null) formatPhone(u['phone'] as String) else u['email'] ?? '',
                      if (u['has_voted'] == true) 'voted',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'admin':
                          _update(u, {'role': 'admin'}, 'Now an admin');
                        case 'resident':
                          _update(u, {'role': 'resident'}, 'Admin rights removed');
                        case 'ward':
                          _changeWard(u);
                      }
                    },
                    itemBuilder: (_) => [
                      if (u['role'] != 'admin') const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                      if (u['role'] == 'admin' && u['id'] != me)
                        const PopupMenuItem(value: 'resident', child: Text('Remove admin')),
                      const PopupMenuItem(value: 'ward', child: Text('Change ward…')),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
