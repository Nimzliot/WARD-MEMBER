/// Where a ward is in its budgeting cycle.
enum WardPhase { upcoming, open, closed }

class Ward {
  final int id;
  final String name;
  final int budgetPool; // INR
  final DateTime? votingOpensAt; // null = already open
  final DateTime? votingClosesAt; // null = no deadline
  final double? centerLat; // map centre
  final double? centerLng;
  final String? adminUserId; // the one Ward Admin (null = none yet)

  const Ward({
    required this.id,
    required this.name,
    required this.budgetPool,
    this.votingOpensAt,
    this.votingClosesAt,
    this.centerLat,
    this.centerLng,
    this.adminUserId,
  });

  factory Ward.fromMap(Map<String, dynamic> m) => Ward(
        id: m['id'] as int,
        name: m['name'] as String,
        budgetPool: (m['budget_pool'] as num).toInt(),
        votingOpensAt: _date(m['voting_opens_at']),
        votingClosesAt: _date(m['voting_closes_at']),
        centerLat: (m['center_lat'] as num?)?.toDouble(),
        centerLng: (m['center_lng'] as num?)?.toDouble(),
        adminUserId: m['admin_user_id'] as String?,
      );

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

  /// Same rule as the server (server/src/lib/phase.js).
  WardPhase phaseAt(DateTime now) {
    if (votingClosesAt != null && !now.isBefore(votingClosesAt!)) return WardPhase.closed;
    if (votingOpensAt != null && now.isBefore(votingOpensAt!)) return WardPhase.upcoming;
    return WardPhase.open;
  }

  WardPhase get phase => phaseAt(DateTime.now());
  bool get isOpen => phase == WardPhase.open;
  bool get isClosed => phase == WardPhase.closed;

  /// The next moment the phase changes (for countdowns), or null.
  DateTime? get nextDeadline => switch (phase) {
        WardPhase.upcoming => votingOpensAt,
        WardPhase.open => votingClosesAt,
        WardPhase.closed => null,
      };
}
