import 'package:flutter/material.dart';

/// Calm, clinical colors. Confidence is never shown in red or green, so a result never looks like a verdict.
class LumisColors {
  static const seed = Color(0xFF1F6F78); // deep teal
  static const high = Color(0xFF1F6F78);
  static const low = Color(0xFFB7791F); // amber: "Lumis isn't sure"
  static const inconclusive = Color(0xFF6B7280); // gray
}

ThemeData lumisTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: LumisColors.seed);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF7F8F8),
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, centerTitle: false),
    cardTheme: const CardThemeData(margin: EdgeInsets.zero, elevation: 0),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: const TextStyle(fontSize: 16)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    ),
  );
}
