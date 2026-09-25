import 'package:flutter/material.dart';

/// Categories offered in the admin form (proposals may use any text).
const kCategories = [
  'Roads & Transport',
  'Water & Sanitation',
  'Parks & Environment',
  'Street Lighting',
  'Education',
  'Health',
  'Waste Management',
  'Public Safety',
];

IconData categoryIcon(String category) {
  final c = category.toLowerCase();
  if (c.contains('road') || c.contains('transport')) return Icons.directions_bus_outlined;
  if (c.contains('light')) return Icons.lightbulb_outline;
  if (c.contains('park') || c.contains('environment')) return Icons.park_outlined;
  if (c.contains('water') || c.contains('sanitation')) return Icons.water_drop_outlined;
  if (c.contains('health')) return Icons.local_hospital_outlined;
  if (c.contains('education') || c.contains('school')) return Icons.school_outlined;
  if (c.contains('waste')) return Icons.recycling;
  if (c.contains('safety')) return Icons.shield_outlined;
  return Icons.category_outlined;
}
