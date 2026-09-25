import 'package:flutter_test/flutter_test.dart';
import 'package:ward_budget/models/proposal.dart';
import 'package:ward_budget/providers/live_results.dart';

Proposal _p(String id, int cost) => Proposal(
      id: id,
      wardId: 1,
      title: id,
      description: '',
      category: 'Test',
      totalCost: cost,
      createdAt: DateTime(2026),
      items: const [],
    );

void main() {
  // Ward 1 seed: pool ₹75 L
  final roads = _p('roads', 3255000);
  final lights = _p('lights', 2850000);
  final park = _p('park', 2500000);
  final health = _p('health', 2200000);
  final all = [roads, lights, park, health];
  const pool = 7500000;

  test('no votes → nothing funded', () {
    final a = allocate(all, {}, pool);
    expect(a.funded, isEmpty);
    expect(a.allocated, 0);
    expect(a.unallocated, pool);
  });

  test('funds by votes and skips a proposal that no longer fits', () {
    // roads (32.55 L) + lights (28.5 L) = 61.05 L; park (25 L) does not fit; health (22 L) does not fit either
    final a = allocate(all, {'roads': 5, 'lights': 4, 'park': 3, 'health': 1}, pool);
    expect(a.funded.map((r) => r.proposal.id), ['roads', 'lights']);
    expect(a.allocated, 6105000);
  });

  test('a cheaper lower-ranked proposal can use the leftover money', () {
    // roads 32.55 L + park 25 L = 57.55 L → 17.45 L left: lights (28.5 L) and health (22 L) don't fit
    final a = allocate(all, {'roads': 5, 'park': 4, 'lights': 3, 'health': 2}, pool);
    expect(a.funded.map((r) => r.proposal.id), ['roads', 'park']);
    // …but a ₹10 L proposal with fewer votes still fits in the leftover 17.45 L
    final b = allocate([roads, park, _p('small', 1000000)], {'roads': 5, 'park': 4, 'small': 1}, pool);
    expect(b.funded.map((r) => r.proposal.id), ['roads', 'park', 'small']);
  });

  test('ties go to the cheaper proposal', () {
    final a = allocate(all, {'roads': 2, 'health': 2}, pool);
    expect(a.ranked.first.proposal.id, 'health');
  });

  test('colour slot follows the proposal, not its rank', () {
    final a = allocate(all, {'health': 9}, pool);
    expect(a.ranked.first.slot, 3); // health is 4th in the ward list
  });
}
