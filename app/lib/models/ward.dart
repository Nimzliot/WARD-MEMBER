class Ward {
  final int id;
  final String name;
  final int budgetPool; // INR

  const Ward({required this.id, required this.name, required this.budgetPool});

  factory Ward.fromMap(Map<String, dynamic> m) => Ward(
        id: m['id'] as int,
        name: m['name'] as String,
        budgetPool: (m['budget_pool'] as num).toInt(),
      );
}
