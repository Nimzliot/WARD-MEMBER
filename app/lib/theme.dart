import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Green & white brand palette.
class AppColors {
  static const forest = Color(0xFF0B5D3B); // primary — buttons, headers
  static const forestDark = Color(0xFF06402A); // hero gradients, pressed
  static const emerald = Color(0xFF12A15F); // accents, AI gradient
  static const leaf = Color(0xFF8FE3B4); // highlights on dark green
  static const mint = Color(0xFFE8F5EE); // tinted surfaces, chips
  static const mintLine = Color(0xFFD2E9DC); // borders, dividers
  static const canvas = Color(0xFFF5FAF7); // page background
  static const ink = Color(0xFF10231A); // body text
  static const inkMuted = Color(0xFF5A6E63); // secondary text
}

class AppTheme {
  static const success = Color(0xFF0E8A4F); // readable green for text/icons on white

  /// Hero cards (budget pool, turnout, totals).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.forest, AppColors.forestDark],
  );

  /// Ward Assistant (AI) accent.
  static const aiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.emerald, AppColors.forest],
  );

  static ThemeData light = _build();

  static ThemeData _build() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.forest).copyWith(
      primary: AppColors.forest,
      onPrimary: Colors.white,
      primaryContainer: AppColors.mint,
      onPrimaryContainer: AppColors.forestDark,
      secondary: AppColors.emerald,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.mint,
      onSecondaryContainer: AppColors.forestDark,
      tertiary: const Color(0xFF0F766E),
      tertiaryContainer: const Color(0xFFE1F3EE),
      onTertiaryContainer: const Color(0xFF0B4A43),
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: AppColors.canvas,
      surfaceContainerHigh: AppColors.mint,
      surfaceContainerHighest: AppColors.mint,
      outline: const Color(0xFF9BB4A7),
      outlineVariant: AppColors.mintLine,
      inverseSurface: AppColors.forestDark,
      onInverseSurface: Colors.white,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );
    final radius = BorderRadius.circular(14);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: AppColors.canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.mintLine),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.mintLine)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.mintLine)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.forest, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.forest,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.mintLine,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.mintLine, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.mint,
        side: const BorderSide(color: AppColors.mintLine),
        shape: const StadiumBorder(),
        labelStyle: text.labelLarge?.copyWith(color: AppColors.ink),
        checkmarkColor: AppColors.forest,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.white,
          selectedBackgroundColor: AppColors.forest,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: AppColors.mintLine),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.mint,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium?.copyWith(
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? AppColors.forest : AppColors.inkMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? AppColors.forest : AppColors.inkMuted,
            )),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.forestDark,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.mintLine),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.forest,
        linearTrackColor: AppColors.mint,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
    );
  }
}
