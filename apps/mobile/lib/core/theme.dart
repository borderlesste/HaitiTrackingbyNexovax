import 'package:flutter/material.dart';

/// Colores tomados de las maquetas de Haiti Tracking.
class HtColors {
  static const navy = Color(0xFF0B2A66);
  static const blue = Color(0xFF0D47C2);
  static const red = Color(0xFFD62839);
  static const green = Color(0xFF1E9E5A);
  static const amber = Color(0xFFE0A100);
  static const surface = Color(0xFFF4F7FC);
  static const text = Color(0xFF111C3A);
  static const muted = Color(0xFF5B6478);
  static const border = Color(0xFFDDE3EE);
  static const blueSoft = Color(0xFFEAF1FD);
  static const greenSoft = Color(0xFFE6F6EC);
  static const amberSoft = Color(0xFFFFF4D6);
  static const redSoft = Color(0xFFFDECEC);
  static const moncash = Color(0xFFE11B22);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HtColors.blue,
    primary: HtColors.blue,
    secondary: HtColors.red,
    surface: Colors.white,
  );
  return ThemeData(
    fontFamily: 'Roboto',
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
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: HtColors.blue,
        side: const BorderSide(color: HtColors.blue, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HtColors.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: HtColors.blueSoft,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? HtColors.blue : HtColors.text,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? HtColors.blue : HtColors.text)),
    ),
  );
}
