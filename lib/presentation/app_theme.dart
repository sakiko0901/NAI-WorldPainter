import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppearanceMode {
  light,
  dark,
  coffeePaper;

  static AppearanceMode parse(String? value) {
    return AppearanceMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AppearanceMode.dark,
    );
  }

  Brightness get brightness => switch (this) {
        AppearanceMode.light => Brightness.light,
        AppearanceMode.dark || AppearanceMode.coffeePaper => Brightness.dark,
      };
}

const zhFallback = <String>[
  'PingFang SC',
  'HarmonyOS Sans SC',
  'Source Han Sans CN',
  'Noto Sans CJK SC',
  'Microsoft YaHei',
  'sans-serif',
];

TextTheme _appleishBold(TextTheme base, Color color) {
  TextStyle? bump(TextStyle? s, FontWeight target) {
    if (s == null) return null;
    return s.copyWith(
      fontWeight: target,
      fontFamilyFallback: zhFallback,
      letterSpacing: (s.letterSpacing ?? 0) - 0.1,
    );
  }

  return base
      .copyWith(
        displayLarge: bump(base.displayLarge, FontWeight.w700),
        displayMedium: bump(base.displayMedium, FontWeight.w700),
        displaySmall: bump(base.displaySmall, FontWeight.w700),
        headlineLarge: bump(base.headlineLarge, FontWeight.w700),
        headlineMedium: bump(base.headlineMedium, FontWeight.w700),
        headlineSmall: bump(base.headlineSmall, FontWeight.w700),
        titleLarge: bump(base.titleLarge, FontWeight.w700),
        titleMedium: bump(base.titleMedium, FontWeight.w600),
        titleSmall: bump(base.titleSmall, FontWeight.w600),
        bodyLarge: bump(base.bodyLarge, FontWeight.w600),
        bodyMedium: bump(base.bodyMedium, FontWeight.w600),
        bodySmall: bump(base.bodySmall, FontWeight.w600),
        labelLarge: bump(base.labelLarge, FontWeight.w700),
        labelMedium: bump(base.labelMedium, FontWeight.w600),
        labelSmall: bump(base.labelSmall, FontWeight.w600),
      )
      .apply(
        bodyColor: color,
        displayColor: color,
      );
}

ThemeData buildNaiHuishiTheme(Brightness brightness,
    {bool useGoogleFonts = true}) {
  final isDark = brightness == Brightness.dark;
  final baseTheme = ThemeData(brightness: brightness).textTheme;
  final interTheme =
      useGoogleFonts ? GoogleFonts.interTextTheme(baseTheme) : baseTheme;
  final textColor = isDark ? Colors.white : const Color(0xFF172033);
  final surface = isDark ? const Color(0xFF1C1C21) : const Color(0xFFFFFFFF);
  final primary = isDark ? const Color(0xFFF5D57A) : const Color(0xFF3B82F6);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF0A0A0C) : const Color(0xFFF2F4F8),
    fontFamily: useGoogleFonts ? GoogleFonts.inter().fontFamily : null,
    fontFamilyFallback: zhFallback,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? Colors.black : Colors.white,
      secondary: isDark ? const Color(0xFF6C5CE7) : const Color(0xFF8B5CF6),
      onSecondary: Colors.white,
      tertiary: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF14B8A6),
      onTertiary: Colors.white,
      error: isDark ? Colors.redAccent : const Color(0xFFFF6B6B),
      onError: Colors.white,
      surface: surface,
      onSurface: textColor,
      onSurfaceVariant: isDark
          ? Colors.white.withValues(alpha: 0.6)
          : const Color(0xFF5D6B82),
    ),
    textTheme: _appleishBold(interTheme, textColor),
    cardTheme: CardThemeData(
      color: isDark
          ? surface.withValues(alpha: 0.8)
          : surface.withValues(alpha: 0.94),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFD7E6FF),
          width: 1,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.03)
          : const Color(0xFFEFF6FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: primary, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}
