import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF00796B); // civic teal
  static const sdgOrange = Color(0xFFFD9D24); // official SDG 11 colour
  static const success = Color(0xFF2E7D32);

  static ThemeData light = _build(Brightness.light);
  static ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final radius = BorderRadius.circular(12);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: radius),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: radius),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius)),
      ),
    );
  }
}
