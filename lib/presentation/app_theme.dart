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
        bodyLarge: bump(base.bodyLarge, FontWeight.w400),
        bodyMedium: bump(base.bodyMedium, FontWeight.w400),
        bodySmall: bump(base.bodySmall, FontWeight.w400),
        labelLarge: bump(base.labelLarge, FontWeight.w700),
        labelMedium: bump(base.labelMedium, FontWeight.w600),
        labelSmall: bump(base.labelSmall, FontWeight.w600),
      )
      .apply(bodyColor: color, displayColor: color);
}

ThemeData buildNaiHuishiTheme(
  Brightness brightness, {
  bool useGoogleFonts = false,
}) {
  final isDark = brightness == Brightness.dark;
  final baseTheme = ThemeData(brightness: brightness).textTheme;
  final interTheme =
      useGoogleFonts ? GoogleFonts.interTextTheme(baseTheme) : baseTheme;
  final textColor = isDark ? const Color(0xFFEDF0F4) : const Color(0xFF172033);
  final surface = isDark ? const Color(0xFF191C22) : const Color(0xFFFFFFFF);
  final primary = isDark ? const Color(0xFFE3CE98) : const Color(0xFF507AB2);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF101216) : const Color(0xFFF5F6F8),
    fontFamily: useGoogleFonts ? GoogleFonts.inter().fontFamily : null,
    fontFamilyFallback: zhFallback,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
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
      surfaceContainerHighest:
          isDark ? const Color(0xFF22262E) : const Color(0xFFEDF0F5),
      outlineVariant:
          isDark ? const Color(0xFF30353D) : const Color(0xFFDDE1E8),
      onSurfaceVariant:
          isDark ? const Color(0xFF939BA9) : const Color(0xFF5D6B82),
    ),
    textTheme: _appleishBold(interTheme, textColor),
    cardTheme: CardThemeData(
      color: isDark
          ? surface.withValues(alpha: 0.8)
          : surface.withValues(alpha: 0.94),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor:
          isDark ? const Color(0xFF101216) : const Color(0xFFF5F6F8),
      foregroundColor: textColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textColor,
        fontFamilyFallback: zhFallback,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor:
          isDark ? const Color(0xFF101216) : const Color(0xFFF5F6F8),
      indicatorColor: primary.withValues(alpha: 0.12),
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(
          fontSize: 12,
          color: textColor,
          fontWeight: FontWeight.w500,
          fontFamilyFallback: zhFallback)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
