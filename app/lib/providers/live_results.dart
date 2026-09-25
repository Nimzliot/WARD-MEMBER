import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/proposal.dart';
import '../utils/errors.dart';

/// Vote counts + turnout for one ward, kept live with Supabase Realtime.
class LiveResults extends ChangeNotifier {
  LiveResults({required this.wardId});

  final int wardId;
  final SupabaseClient _sb = Supabase.instance.client;
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _fallbackPoll;
  bool _disposed = false;

  Map<String, int> counts = {}; // proposal_id → ballots that back it
  int totalVotes = 0; // ballots cast (one per resident)
  int eligible = 0; // fully verified residents in the ward
  DateTime? lastVoteAt;
  bool loading = true;
  bool live = false; // Realtime channel subscribed
  String? error;

  double get turnout => eligible == 0 ? 0 : totalVotes / eligible;

  Future<void> start() async {
    await refresh();
    _subscribe();
    // Safety net: if Realtime is not connected, poll every 15 s.
    _fallbackPoll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!live) refresh();
    });
  }

  Future<void> refresh() async {
    try {
      final r = await Future.wait<dynamic>([
        // Clients may not read votes.user_id, so select explicit columns.
        _sb.from('votes').select('proposal_ids, created_at').eq('ward_id', wardId),
        _sb.rpc('ward_turnout', params: {'p_ward_id': wardId}),
      ]);
      final votes = (r[0] as List).cast<Map<String, dynamic>>();
      final next = <String, int>{};
      DateTime? last;
      for (final v in votes) {
        for (final pid in (v['proposal_ids'] as List).cast<String>()) {
          next[pid] = (next[pid] ?? 0) + 1;
        }
        final at = DateTime.parse(v['created_at'] as String);
        if (last == null || at.isAfter(last)) last = at;
      }
      final t = r[1] as List;
      counts = next;
      totalVotes = votes.length;
      lastVoteAt = last;
      eligible = t.isEmpty ? 0 : ((t.first as Map)['eligible'] as num).toInt();
      error = null;
    } catch (e) {
      error = friendlyError(e);
    }
    loading = false;
    _notify();
  }

  void _subscribe() {
    _channel = _sb
        .channel('votes-ward-$wardId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'votes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ward_id',
            value: wardId,
          ),
          // Any change → re-count (debounced so a burst of votes = one refresh).
          callback: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), refresh);
          },
        )
        .subscribe((status, [err]) {
      live = status == RealtimeSubscribeStatus.subscribed;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _fallbackPoll?.cancel();
    if (_channel != null) _sb.removeChannel(_channel!);
    super.dispose();
  }
}

class ResultRow {
  ResultRow({required this.proposal, required this.slot, required this.votes});

  final Proposal proposal;
  final int slot; // fixed colour slot (proposal's position in the ward list)
  final int votes; // ballots backing this project
  bool funded = false;
}

class Allocation {
  Allocation(this.ranked, this.pool, this.allocated);

  final List<ResultRow> ranked; // most votes first
  final int pool;
  final int allocated;

  int get unallocated => pool - allocated;
  List<ResultRow> get funded => ranked.where((r) => r.funded).toList();
}

/// Funding rule (greedy participatory budgeting): walk proposals from most to
/// fewest votes (ties → cheaper first) and fund each one that still fits in
/// the remaining pool. Proposals with zero votes are never funded.
Allocation allocate(List<Proposal> proposals, Map<String, int> counts, int pool) {
  final rows = [
    for (var i = 0; i < proposals.length; i++)
      ResultRow(proposal: proposals[i], slot: i, votes: counts[proposals[i].id] ?? 0),
  ];
  final ranked = [...rows]
    ..sort((a, b) => b.votes != a.votes
        ? b.votes.compareTo(a.votes)
        : a.proposal.totalCost.compareTo(b.proposal.totalCost));

  var remaining = pool;
  for (final r in ranked) {
    if (r.votes > 0 && r.proposal.totalCost <= remaining) {
      r.funded = true;
      remaining -= r.proposal.totalCost;
    }
  }
  return Allocation(ranked, pool, pool - remaining);
}
