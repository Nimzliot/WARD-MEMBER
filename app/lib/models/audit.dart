/// Response of GET /api/audit/:wardId — the anonymised vote chain, re-verified
/// by the server on every request.
class AuditEntry {
  final int index;
  final String id;
  final String proposalTitle;
  final String voterHash;
  final String prevHash;
  final String hash;
  final DateTime createdAt;
  final bool hashOk; // stored hash == recomputed hash (record not edited)
  final bool linkOk; // prev_hash == previous vote's hash (nothing removed/inserted)

  const AuditEntry({
    required this.index,
    required this.id,
    required this.proposalTitle,
    required this.voterHash,
    required this.prevHash,
    required this.hash,
    required this.createdAt,
    required this.hashOk,
    required this.linkOk,
  });

  bool get valid => hashOk && linkOk;

  factory AuditEntry.fromMap(Map<String, dynamic> m) => AuditEntry(
        index: m['index'] as int,
        id: m['id'] as String,
        proposalTitle: m['proposal_title'] as String? ?? '',
        voterHash: m['voter_hash'] as String,
        prevHash: m['prev_hash'] as String,
        hash: m['hash'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        hashOk: m['hash_ok'] as bool,
        linkOk: m['link_ok'] as bool,
      );
}

class AuditResult {
  final int wardId;
  final String wardName;
  final bool valid;
  final int? brokenAt;
  final String headHash;
  final DateTime verifiedAt;
  final List<AuditEntry> chain;

  const AuditResult({
    required this.wardId,
    required this.wardName,
    required this.valid,
    required this.brokenAt,
    required this.headHash,
    required this.verifiedAt,
    required this.chain,
  });

  factory AuditResult.fromMap(Map<String, dynamic> m) => AuditResult(
        wardId: m['ward_id'] as int,
        wardName: m['ward_name'] as String,
        valid: m['valid'] as bool,
        brokenAt: m['broken_at'] as int?,
        headHash: m['head_hash'] as String,
        verifiedAt: DateTime.parse(m['verified_at'] as String),
        chain: (m['chain'] as List)
            .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}
