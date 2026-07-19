/// AstroTransit design tokens and themes (SPEC section 15).
///
/// Three modes: dark (default, for night observation), light (daytime / solar
/// use) and a low-brightness "red mode" that preserves night vision (RF-019,
/// section 15.2).
library;

import 'package:flutter/material.dart';

enum AppThemeMode { dark, light, red }

/// Semantic colors carry consistent meaning across the app (section 15.3) —
/// never rely on color alone to convey state.
class AstroColors {
  AstroColors._();

  static const sun = Color(0xFFFFC169);
  static const moon = Color(0xFFE8E0C0);
  static const aircraftCommon = Color(0xFF7C8AA8);
  static const aircraftCandidate = Color(0xFF5EC2FF);
  static const satellite = Color(0xFFB98BFF);

  static const success = Color(0xFF3DDC84);
  static const warning = Color(0xFFFFC24B);
  static const error = Color(0xFFFF6259);
  static const info = Color(0xFF5EC2FF);
}

class AppTheme {
  AppTheme._();

  static ThemeData forMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.dark:
        return _dark;
      case AppThemeMode.light:
        return _light;
      case AppThemeMode.red:
        return _red;
    }
  }

  static final _tabularNums = const TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle countdownStyle(BuildContext context, {required Color color}) {
    return _tabularNums.copyWith(
      fontSize: 56,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: -1,
    );
  }

  static final ColorScheme _darkScheme = ColorScheme.fromSeed(
    seedColor: AstroColors.aircraftCandidate,
    brightness: Brightness.dark,
    surface: const Color(0xFF0B1020),
  );

  static final _dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _darkScheme,
    scaffoldBackgroundColor: const Color(0xFF05070F),
    cardTheme: CardThemeData(
      color: const Color(0xFF111A31),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF223052)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: Color(0xFF2E3D63)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFFEAF0FF),
      ),
    ),
  );

  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E6FB5),
    brightness: Brightness.light,
  );

  static final _light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _lightScheme,
    scaffoldBackgroundColor: const Color(0xFFEEF1F8),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFDDE3F0)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );

  // Red mode: minimizes blue light and overall brightness to preserve dark
  // adaptation during night observation sessions (section 15.2).
  static final ColorScheme _redScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB5342E),
    brightness: Brightness.dark,
    surface: const Color(0xFF120404),
  );

  static final _red = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _redScheme,
    scaffoldBackgroundColor: const Color(0xFF0A0202),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A0707),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF3A1210)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFCC4A42),
          displayColor: const Color(0xFFCC4A42),
        ),
  );
}
