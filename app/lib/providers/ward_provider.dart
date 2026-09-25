import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/proposal.dart';
import '../models/vote.dart';
import '../models/ward.dart';
import '../services/api_service.dart';
import '../utils/errors.dart';

/// The signed-in resident's ward, its proposals, and the resident's own vote.
/// Kept in sync with AuthProvider by a ChangeNotifierProxyProvider in main.dart.
class WardProvider extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;

  String? _key; // "<userId>:<wardId>" — reload when either changes
  int? wardId;
  Ward? ward;
  List<Proposal> proposals = [];
  String? myVoteProposalId; // null = not voted yet
  bool loading = false;
  String? error;

  /// Called from the proxy provider (during build), so the actual load is deferred.
  void setWard({required String? userId, required int? wardId}) {
    final key = (userId == null || wardId == null) ? null : '$userId:$wardId';
    if (key == _key) return;
    _key = key;
    this.wardId = key == null ? null : wardId;
    ward = null;
    proposals = [];
    myVoteProposalId = null;
    error = null;
    if (key != null) Future.microtask(load);
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
        _sb.from('proposals').select('*, budget_items(*)').eq('ward_id', id).order('created_at'),
        _sb.rpc('my_vote'), // proposal id I voted for, or null
      ]);
      if (id != wardId) return; // ward changed while loading
      ward = Ward.fromMap(results[0] as Map<String, dynamic>);
      proposals = (results[1] as List)
          .map((m) => Proposal.fromMap(m as Map<String, dynamic>))
          .toList();
      myVoteProposalId = results[2] as String?;
    } catch (e) {
      error = friendlyError(e);
    }
    loading = false;
    notifyListeners();
  }

  Proposal? byId(String id) {
    for (final p in proposals) {
      if (p.id == id) return p;
    }
    return null;
  }

  int get totalRequested => proposals.fold(0, (sum, p) => sum + p.totalCost);

  bool get hasVoted => myVoteProposalId != null;

  Proposal? get myVotedProposal => myVoteProposalId == null ? null : byId(myVoteProposalId!);

  /// Casts the vote through the Node API (the only place votes can be written).
  Future<VoteReceipt> castVote(String proposalId) async {
    try {
      final res = await ApiService.post('/api/votes', {'proposalId': proposalId});
      myVoteProposalId = proposalId;
      notifyListeners();
      return VoteReceipt.fromMap(res['receipt'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 409) await load(); // already voted (e.g. on another device)
      rethrow;
    }
  }

  Future<VoteReceipt?> fetchMyReceipt() async {
    final res = await ApiService.get('/api/votes/me');
    final vote = res['vote'];
    return vote == null ? null : VoteReceipt.fromMap(vote as Map<String, dynamic>);
  }
}
