/// AstroTransit design tokens and themes — "Celestial Precision" (SPEC section 15).
///
/// A premium, scientific, accessible astronomy interface. Three observation modes:
/// dark ("Observatório", default night use), light ("Solar", high legibility under
/// bright light) and red ("Visão noturna", minimal brightness / no blue to preserve
/// dark adaptation) — RF-019, section 15.2.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppThemeMode { dark, light, red }

/// Semantic colors carry consistent meaning across the app (section 15.3) —
/// never rely on color alone to convey state.
class AstroColors {
  AstroColors._();

  // --- Celestial Precision palette -----------------------------------------
  static const deepSpace = Color(0xFF050914); // fundo principal
  static const orbitalSurface = Color(0xFF0D1729); // cards / superfícies
  static const surfaceElevated = Color(0xFF111F35); // componentes destacados
  static const border = Color(0xFF213553); // contornos e divisores
  static const transitCyan = Color(0xFF66D6FF); // ação principal / navegação
  static const lunarIvory = Color(0xFFECE5C9); // Lua
  static const solarAmber = Color(0xFFFFC56C); // Sol
  static const confidenceGreen = Color(0xFF50DFA1); // confiança alta
  static const telemetry = Color(0xFF9AACC9); // texto secundário
  static const critical = Color(0xFFFF756F); // erros / gravação

  // --- Semantic aliases (stable names used across the app) -----------------
  static const sun = solarAmber;
  static const moon = lunarIvory;
  static const aircraftCandidate = transitCyan;
  static const aircraftCommon = Color(0xFF5B6C89); // tráfego comum (dim)
  static const satellite = Color(0xFFB98BFF); // ISS / Tiangong
  static const success = confidenceGreen;
  static const warning = solarAmber;
  static const error = critical;
  static const info = transitCyan;
}

/// Shared geometry tokens (8-pt system, generous radii).
class AstroRadii {
  AstroRadii._();
  static const card = 24.0;
  static const button = 16.0;
  static const chip = 999.0;
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

  /// Big tabular-figure countdown (RF-018): weight 800, no jitter as digits change.
  static TextStyle countdownStyle(BuildContext context, {required Color color}) {
    return GoogleFonts.manrope(
      fontSize: 56,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: -1.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Uppercase, letter-spaced technical section label (10–12 px).
  static TextStyle sectionLabelStyle(BuildContext context, {Color? color}) {
    return GoogleFonts.manrope(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
      color: color ?? Theme.of(context).colorScheme.primary,
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    return GoogleFonts.manropeTextTheme(base).copyWith(
      headlineLarge: GoogleFonts.manrope(
          fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineMedium: GoogleFonts.manrope(
          fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: GoogleFonts.manrope(fontWeight: FontWeight.w800),
      titleLarge: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      titleMedium: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      titleSmall: GoogleFonts.manrope(fontWeight: FontWeight.w700),
    );
  }

  static CardThemeData _cardTheme(Color color, Color border) => CardThemeData(
        color: color,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AstroRadii.card),
          side: BorderSide(color: border),
        ),
      );

  // Botões primários: altura MÍNIMA 52 (não fixa), raio 16, peso 700.
  //
  // `minimumSize` com altura fixa + rótulo longo = texto cortado, que é o
  // "texto quebrando nos botões" relatado. A correção tem duas partes:
  //   1. o rótulo pode ocupar 2 linhas, centralizado (softWrap real) em vez de
  //      ser aparado;
  //   2. o botão cresce em altura para caber (`tapTargetSize` + padding
  //      vertical), então nunca corta.
  // Ainda assim, o certo é o CHAMADOR encurtar rótulos — isto é a rede de
  // segurança para telas estreitas e fonte grande, não licença para textão.
  static TextStyle get _btnTextStyle => GoogleFonts.manrope(
      fontSize: 15, fontWeight: FontWeight.w700, height: 1.15);

  static FilledButtonThemeData _filledButtons() => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AstroRadii.button),
          ),
          textStyle: _btnTextStyle,
        ),
      );

  /// AppBar derivada do ColorScheme, para os TRÊS temas.
  ///
  /// Antes cada tema escrevia a cor do título na mão (e o tema de visão
  /// noturna não declarava appBarTheme nenhum, caindo no padrão do Material —
  /// por isso a barra "não mudava de cor com o tema"). Derivar de
  /// `onSurface`/`surface` faz valer a regra do design system: mexer no token
  /// propaga para todas as telas.
  ///
  /// `surfaceTintColor` fica transparente de propósito: no Material 3 a barra
  /// ganha um tingimento automático quando o conteúdo rola por baixo dela, e
  /// esse tingimento é calculado sobre o primário — numa paleta escura ele
  /// aparece como uma faixa clara que não pertence a nenhum dos temas.
  static AppBarTheme _appBar(ColorScheme scheme) => AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      );

  static OutlinedButtonThemeData _outlinedButtons(Color side) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AstroRadii.button),
          ),
          side: BorderSide(color: side),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          textStyle: _btnTextStyle,
        ),
      );

  // ------------------------------------------------------------------ dark ---
  static final ColorScheme _darkScheme = ColorScheme.fromSeed(
    seedColor: AstroColors.transitCyan,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AstroColors.transitCyan,
    onPrimary: AstroColors.deepSpace,
    secondary: AstroColors.confidenceGreen,
    onSecondary: AstroColors.deepSpace,
    surface: AstroColors.orbitalSurface,
    onSurface: const Color(0xFFE8EEFB),
    onSurfaceVariant: AstroColors.telemetry,
    outline: AstroColors.border,
    error: AstroColors.critical,
  );

  static final _dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _darkScheme,
    scaffoldBackgroundColor: AstroColors.deepSpace,
    textTheme: _textTheme(Brightness.dark),
    cardTheme: _cardTheme(AstroColors.orbitalSurface, AstroColors.border),
    filledButtonTheme: _filledButtons(),
    outlinedButtonTheme: _outlinedButtons(const Color(0xFF2E4166)),
    dividerTheme: const DividerThemeData(color: AstroColors.border, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AstroColors.orbitalSurface,
      indicatorColor: AstroColors.transitCyan.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    appBarTheme: _appBar(_darkScheme),
  );

  // ----------------------------------------------------------------- light ---
  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1C7FB8),
    brightness: Brightness.light,
  ).copyWith(
    primary: const Color(0xFF0E6CA6),
    secondary: const Color(0xFF1C9E6B),
    surface: Colors.white,
    onSurfaceVariant: const Color(0xFF52627C),
    outline: const Color(0xFFCBD5E6),
  );

  static final _light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _lightScheme,
    scaffoldBackgroundColor: const Color(0xFFEEF2F8),
    textTheme: _textTheme(Brightness.light),
    cardTheme: _cardTheme(Colors.white, const Color(0xFFDCE3F0)),
    filledButtonTheme: _filledButtons(),
    outlinedButtonTheme: _outlinedButtons(const Color(0xFFCBD5E6)),
    appBarTheme: _appBar(_lightScheme),
  );

  // ------------------------------------------------------------------- red ---
  // Minimizes blue light and overall brightness to preserve dark adaptation
  // during night observation sessions (section 15.2).
  static final ColorScheme _redScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB5342E),
    brightness: Brightness.dark,
    surface: const Color(0xFF140505),
  ).copyWith(
    primary: const Color(0xFFE0564E),
    onPrimary: const Color(0xFF120303),
    onSurface: const Color(0xFFD9564E),
    onSurfaceVariant: const Color(0xFFA84139),
    outline: const Color(0xFF3A1210),
  );

  static final _red = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _redScheme,
    scaffoldBackgroundColor: const Color(0xFF0A0202),
    textTheme: _textTheme(Brightness.dark).apply(
      bodyColor: const Color(0xFFCC4A42),
      displayColor: const Color(0xFFCC4A42),
    ),
    cardTheme: _cardTheme(const Color(0xFF1A0707), const Color(0xFF3A1210)),
    filledButtonTheme: _filledButtons(),
    outlinedButtonTheme: _outlinedButtons(const Color(0xFF4A1613)),
  );
}
