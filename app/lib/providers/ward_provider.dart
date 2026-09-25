import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/proposal.dart';
import '../models/vote.dart';
import '../models/ward.dart';
import '../services/api_service.dart';
import '../utils/errors.dart';

/// The signed-in resident's ward, its ballot (approved proposals), the
/// resident's own ballot / picks, and their submitted ideas.
/// Kept in sync with AuthProvider by a ChangeNotifierProxyProvider in main.dart.
class WardProvider extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;

  String? _key; // "<userId>:<wardId>" — reload when either changes
  String? _userId;
  int? wardId;
  Ward? ward;
  List<Proposal> proposals = []; // approved = on the ballot
  List<Proposal> myIdeas = []; // my submissions, any status, newest first
  List<String>? myBallot; // null = not voted yet
  final Set<String> picks = {}; // ballot being built (before submitting)
  bool loading = false;
  String? error;

  RealtimeChannel? _channel;
  Timer? _debounce;

  /// Called from the proxy provider (during build), so the actual load is deferred.
  void setWard({required String? userId, required int? wardId}) {
    final key = (userId == null || wardId == null) ? null : '$userId:$wardId';
    if (key == _key) return;
    _key = key;
    _userId = userId;
    this.wardId = key == null ? null : wardId;
    ward = null;
    proposals = [];
    myIdeas = [];
    myBallot = null;
    picks.clear();
    error = null;
    _unsubscribe();
    if (key != null) {
      Future.microtask(load);
      Future.microtask(_subscribe);
    }
  }

  Future<void> load() async {
    final id = wardId;
    if (id == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        _sb.from('wards').select().eq('id', id).single(),
        _sb
            .from('proposals')
            .select('*, budget_items(*)')
            .eq('ward_id', id)
            .eq('status', 'approved')
            .order('created_at', ascending: true),
        _sb.rpc('my_vote'), // my ballot's proposal ids, or null
        _sb
            .from('proposals')
            .select('*, budget_items(*)')
            .eq('submitted_by', _userId ?? '')
            .order('created_at', ascending: false),
      ]);
      if (id != wardId) return; // ward changed while loading
      ward = Ward.fromMap(results[0] as Map<String, dynamic>);
      proposals = (results[1] as List).map((m) => Proposal.fromMap(m as Map<String, dynamic>)).toList();
      myBallot = results[2] == null ? null : List<String>.from(results[2] as List);
      myIdeas = (results[3] as List).map((m) => Proposal.fromMap(m as Map<String, dynamic>)).toList();
      // Drop picks that are no longer on the ballot (deleted / rejected by an admin).
      picks.removeWhere((pid) => byId(pid) == null);
    } catch (e) {
      error = friendlyError(e);
    }
    loading = false;
    notifyListeners();
  }

  /// Admin changes (voting dates, approvals, edits) show up without a manual refresh.
  void _subscribe() {
    final id = wardId;
    if (id == null) return;
    void reload(_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), load);
    }

    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id);
    final wardFilter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'ward_id', value: id);
    _channel = _sb
        .channel('ward-$id-changes')
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'wards', filter: filter, callback: reload)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'proposals', filter: wardFilter, callback: reload)
        .subscribe();
  }

  void _unsubscribe() {
    _debounce?.cancel();
    if (_channel != null) _sb.removeChannel(_channel!);
    _channel = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  Proposal? byId(String id) {
    for (final p in proposals) {
      if (p.id == id) return p;
    }
    return null;
  }

  int get totalRequested => proposals.fold(0, (sum, p) => sum + p.totalCost);
  int get pool => ward?.budgetPool ?? 0;

  // ---------------- my ballot ----------------

  bool get hasVoted => myBallot != null;
  bool isOnMyBallot(String proposalId) => myBallot?.contains(proposalId) ?? false;
  List<Proposal> get myBallotProposals => [for (final id in myBallot ?? const <String>[]) ?byId(id)];

  // ---------------- ballot being built ----------------

  bool get canVote => ward != null && ward!.isOpen && !hasVoted;
  bool isPicked(String id) => picks.contains(id);
  List<Proposal> get pickedProposals => [for (final p in proposals) if (picks.contains(p.id)) p];
  int get pickedCost => pickedProposals.fold(0, (s, p) => s + p.totalCost);
  int get remainingBudget => pool - pickedCost;

  /// Whether [p] can still be added without going over the ward pool.
  bool fits(Proposal p) => picks.contains(p.id) || p.totalCost <= remainingBudget;

  /// Adds or removes a project. Returns false if adding would exceed the pool.
  bool togglePick(Proposal p) {
    if (picks.remove(p.id)) {
      notifyListeners();
      return true;
    }
    if (!fits(p)) return false;
    picks.add(p.id);
    notifyListeners();
    return true;
  }

  void clearPicks() {
    picks.clear();
    notifyListeners();
  }

  /// Submits the ballot through the Node API (the only place votes can be written).
  Future<VoteReceipt> castBallot() async {
    try {
      final res = await ApiService.post('/api/votes', {'proposalIds': picks.toList()});
      final receipt = VoteReceipt.fromMap(res['receipt'] as Map<String, dynamic>);
      myBallot = receipt.proposalIds;
      picks.clear();
      notifyListeners();
      return receipt;
    } on ApiException catch (e) {
      if (e.statusCode == 409 || e.statusCode == 403) await load(); // already voted / window changed
      rethrow;
    }
  }

  Future<VoteReceipt?> fetchMyReceipt() async {
    final res = await ApiService.get('/api/votes/me');
    final vote = res['vote'];
    return vote == null ? null : VoteReceipt.fromMap(vote as Map<String, dynamic>);
  }

  // ---------------- ideas ----------------

  int get pendingIdeas => myIdeas.where((i) => i.status == ProposalStatus.pending).length;

  Future<void> submitIdea({
    required String title,
    required String category,
    required String description,
    required List<({String label, int amount})> items,
  }) async {
    await ApiService.post('/api/ideas', {
      'title': title,
      'category': category,
      'description': description,
      'items': [for (final i in items) {'label': i.label, 'amount': i.amount}],
    });
    await load();
  }

  Future<void> withdrawIdea(String id) async {
    await ApiService.delete('/api/ideas/$id');
    await load();
  }
}
