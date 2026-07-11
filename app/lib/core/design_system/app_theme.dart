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
      color: const Color(0xFF121A30),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFCC4A42),
          displayColor: const Color(0xFFCC4A42),
        ),
  );
}
