/// A vote as returned by the Node API (POST /api/votes, GET /api/votes/me).
/// Contains no personal data — only the anonymised voter hash and chain hashes.
class VoteReceipt {
  final String id;
  final String proposalId;
  final String? proposalTitle;
  final String voterHash;
  final String prevHash;
  final String hash;
  final DateTime createdAt;

  const VoteReceipt({
    required this.id,
    required this.proposalId,
    this.proposalTitle,
    required this.voterHash,
    required this.prevHash,
    required this.hash,
    required this.createdAt,
  });

  bool get isFirstInChain => RegExp(r'^0+$').hasMatch(prevHash);

  factory VoteReceipt.fromMap(Map<String, dynamic> m) => VoteReceipt(
        id: m['id'] as String,
        proposalId: m['proposal_id'] as String,
        proposalTitle: m['proposal_title'] as String?,
        voterHash: m['voter_hash'] as String,
        prevHash: m['prev_hash'] as String,
        hash: m['hash'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
