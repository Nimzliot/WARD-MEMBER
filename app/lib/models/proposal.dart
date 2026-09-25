class BudgetItem {
  final String id;
  final String label;
  final int amount; // INR

  const BudgetItem({required this.id, required this.label, required this.amount});

  factory BudgetItem.fromMap(Map<String, dynamic> m) => BudgetItem(
        id: m['id'] as String,
        label: m['label'] as String,
        amount: (m['amount'] as num).toInt(),
      );
}

/// pending → waiting for admin review; approved → on the ballot; rejected → not.
enum ProposalStatus { pending, approved, rejected }

class Proposal {
  final String id;
  final int wardId;
  final String title;
  final String description;
  final String category;
  final int totalCost; // INR, = sum of items (kept by a DB trigger)
  final DateTime createdAt;
  final List<BudgetItem> items; // largest first
  final ProposalStatus status;
  final bool fromResident; // submitted as a resident idea
  final String? submittedBy;
  final String? reviewNote; // admin's note to the resident

  const Proposal({
    required this.id,
    required this.wardId,
    required this.title,
    required this.description,
    required this.category,
    required this.totalCost,
    required this.createdAt,
    required this.items,
    this.status = ProposalStatus.approved,
    this.fromResident = false,
    this.submittedBy,
    this.reviewNote,
  });

  bool get isApproved => status == ProposalStatus.approved;

  factory Proposal.fromMap(Map<String, dynamic> m) => Proposal(
        id: m['id'] as String,
        wardId: m['ward_id'] as int,
        title: m['title'] as String,
        description: m['description'] as String? ?? '',
        category: m['category'] as String,
        totalCost: (m['total_cost'] as num).toInt(),
        createdAt: DateTime.parse(m['created_at'] as String),
        items: ((m['budget_items'] as List?) ?? [])
            .map((e) => BudgetItem.fromMap(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount)),
        status: ProposalStatus.values.asNameMap()[m['status'] as String? ?? 'approved'] ?? ProposalStatus.approved,
        fromResident: m['origin'] == 'resident',
        submittedBy: m['submitted_by'] as String?,
        reviewNote: m['review_note'] as String?,
      );
}
