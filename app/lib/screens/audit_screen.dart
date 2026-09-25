import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/audit.dart';
import '../models/ward.dart';
import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

String _short(String h) => h.length <= 18 ? h : '${h.substring(0, 10)}…${h.substring(h.length - 6)}';

/// Anonymised, hash-chained vote log for a ward + "Verify Integrity".
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  int? _wardId;
  AuditResult? _result;
  String? _myHash; // highlight the viewer's own vote
  List<Ward> _wards = []; // admins can audit any ward
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wardId == null) {
      final wardId = context.read<WardProvider>().wardId;
      if (wardId != null) {
        _wardId = wardId;
        _verify(announce: false);
        _myReceipt();
        if (context.read<AuthProvider>().profile?.isAdmin ?? false) _loadWards();
      }
    }
  }

  Future<void> _loadWards() async {
    try {
      final rows = await Supabase.instance.client.from('wards').select().order('id');
      if (mounted) setState(() => _wards = rows.map(Ward.fromMap).toList());
    } catch (_) {}
  }

  Future<void> _myReceipt() async {
    try {
      final receipt = await context.read<WardProvider>().fetchMyReceipt();
      if (mounted) setState(() => _myHash = receipt?.hash);
    } catch (_) {} // optional — the log works without it
  }

  /// The server re-computes every hash and link on each call.
  Future<void> _verify({bool announce = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = AuditResult.fromMap(await ApiService.get('/api/audit/$_wardId'));
      if (!mounted) return;
      setState(() => _result = res);
      if (announce) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: res.valid ? AppTheme.success : Theme.of(context).colorScheme.error,
          content: Text(res.valid
              ? 'Integrity verified: all ${res.chain.length} votes intact'
              : 'Tampering detected at vote #${res.brokenAt}'),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _verify(announce: false),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_wards.length > 1) ...[
              Wrap(spacing: 8, children: [
                for (final w in _wards)
                  ChoiceChip(
                    label: Text('Ward ${w.id}'),
                    selected: w.id == _wardId,
                    onSelected: (_) {
                      setState(() {
                        _wardId = w.id;
                        _result = null;
                      });
                      _verify(announce: false);
                    },
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            _StatusCard(result: result, loading: _loading, onVerify: _verify),
            const SizedBox(height: 16),
            if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 16)],
            if (result == null && _loading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (result != null && result.chain.isEmpty)
              const EmptyView(icon: Icons.link_off, message: 'No votes in this ward yet.')
            else if (result != null) ...[
              const _GenesisBlock(),
              for (final e in result.chain) ...[
                _Connector(broken: !e.linkOk),
                _EntryCard(entry: e, isMine: e.hash == _myHash),
              ],
            ],
            const SizedBox(height: 20),
            const _HowItWorks(),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.result, required this.loading, required this.onVerify});

  final AuditResult? result;
  final bool loading;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = result;
    final ok = r?.valid ?? true;
    final color = r == null ? scheme.outline : (ok ? AppTheme.success : scheme.error);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                r == null ? Icons.shield_outlined : (ok ? Icons.verified_user : Icons.gpp_bad),
                color: color,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    r == null
                        ? 'Not verified yet'
                        : ok
                            ? 'Chain intact'
                            : 'Tampering detected',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color),
                  ),
                  if (r != null)
                    Text(
                      ok
                          ? '${r.wardName} · all ${r.chain.length} votes verified'
                          : '${r.wardName} · chain breaks at vote #${r.brokenAt}',
                      style: theme.textTheme.bodyMedium,
                    ),
                ]),
              ),
            ]),
            if (r != null) ...[
              const SizedBox(height: 12),
              Text('Latest hash: ${_short(r.headHash)}',
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
              Text('Checked by server ${timeAgo(r.verifiedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Verify Integrity',
              icon: Icons.fact_check_outlined,
              loading: loading,
              onPressed: onVerify,
            ),
          ],
        ),
      ),
    );
  }
}

class _GenesisBlock extends StatelessWidget {
  const _GenesisBlock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.flag_outlined, size: 18),
        const SizedBox(width: 8),
        Text('Start of chain  ', style: theme.textTheme.labelLarge),
        Expanded(
          child: Text('0000000000…000000',
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
        ),
      ]),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.broken});

  final bool broken;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 28,
      child: Center(
        child: Icon(
          broken ? Icons.link_off : Icons.arrow_downward,
          size: 20,
          color: broken ? scheme.error : scheme.outline,
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.isMine});

  final AuditEntry entry;
  final bool isMine;

  void _showFull(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vote #${entry.index}', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final (label, value) in [
                ('Proposal', entry.proposalTitle),
                ('Time', formatDateTime(entry.createdAt)),
                ('Anonymous voter ID', entry.voterHash),
                ('Previous hash', entry.prevHash),
                ('Hash', entry.hash),
              ]) ...[
                Text(label, style: Theme.of(ctx).textTheme.labelMedium),
                SelectableText(value,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final borderColor = !entry.valid ? scheme.error : (isMine ? scheme.primary : Colors.transparent);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: InkWell(
        onTap: () => _showFull(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(radius: 14, child: Text('${entry.index}', style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(entry.proposalTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(formatDateTime(entry.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
                if (isMine)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('Your vote',
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                Icon(entry.valid ? Icons.check_circle : Icons.error,
                    color: entry.valid ? AppTheme.success : scheme.error, size: 20),
              ]),
              const SizedBox(height: 8),
              Text('voter  ${_short(entry.voterHash)}', style: mono),
              Text('prev   ${_short(entry.prevHash)}', style: mono),
              Text('hash   ${_short(entry.hash)}', style: mono),
              if (!entry.valid) ...[
                const SizedBox(height: 6),
                Text(
                  !entry.hashOk
                      ? 'Hash mismatch: this record was edited after it was cast.'
                      : 'Broken link: the vote before this one was removed or changed.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.error, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('How this works', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            Text(
              '• Names are never shown. Each voter appears as SHA-256(user id + secret salt).\n'
              '• Every vote stores SHA-256(voter + proposal + time + previous hash), '
              'so each vote is locked to the one before it.\n'
              '• "Verify Integrity" makes the server recompute every hash. Editing, deleting '
              'or inserting any vote breaks the chain from that point on.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
