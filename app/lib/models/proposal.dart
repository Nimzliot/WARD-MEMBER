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

class Proposal {
  final String id;
  final int wardId;
  final String title;
  final String description;
  final String category;
  final int totalCost; // INR, = sum of items (kept by a DB trigger)
  final DateTime createdAt;
  final List<BudgetItem> items; // largest first

  const Proposal({
    required this.id,
    required this.wardId,
    required this.title,
    required this.description,
    required this.category,
    required this.totalCost,
    required this.createdAt,
    required this.items,
  });

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
      );
}
