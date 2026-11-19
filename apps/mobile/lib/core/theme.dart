import 'package:flutter/material.dart';

/// Colores tomados de las maquetas de Haiti Tracking.
class HtColors {
  static const navy = Color(0xFF0B2A66);
  static const blue = Color(0xFF0D47C2);
  static const red = Color(0xFFD62839);
  static const green = Color(0xFF1E9E5A);
  static const surface = Color(0xFFF4F7FC);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HtColors.blue,
    primary: HtColors.blue,
    secondary: HtColors.red,
    surface: Colors.white,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: HtColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: HtColors.navy,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
