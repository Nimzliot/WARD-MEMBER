/// A ballot as returned by the Node API (POST /api/votes, GET /api/votes/me).
/// One ballot backs one or more projects. Contains no personal data — only the
/// anonymised voter hash and chain hashes.
class VoteReceipt {
  final String id;
  final List<String> proposalIds;
  final List<String> proposalTitles;
  final int totalCost; // INR, sum of the backed projects
  final String voterHash;
  final String prevHash;
  final String hash;
  final DateTime createdAt;

  const VoteReceipt({
    required this.id,
    required this.proposalIds,
    required this.proposalTitles,
    required this.totalCost,
    required this.voterHash,
    required this.prevHash,
    required this.hash,
    required this.createdAt,
  });

  bool get isFirstInChain => RegExp(r'^0+$').hasMatch(prevHash);

  factory VoteReceipt.fromMap(Map<String, dynamic> m) => VoteReceipt(
        id: m['id'] as String,
        proposalIds: List<String>.from(m['proposal_ids'] as List? ?? const []),
        proposalTitles: List<String>.from(m['proposal_titles'] as List? ?? const []),
        totalCost: (m['total_cost'] as num?)?.toInt() ?? 0,
        voterHash: m['voter_hash'] as String,
        prevHash: m['prev_hash'] as String,
        hash: m['hash'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
