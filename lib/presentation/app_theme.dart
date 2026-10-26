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
  bool frostedGlassEnabled = true,
}) {
  final isDark = brightness == Brightness.dark;
  final baseTheme = ThemeData(brightness: brightness).textTheme;
  final interTheme =
      useGoogleFonts ? GoogleFonts.interTextTheme(baseTheme) : baseTheme;
  final glass = FrostedTheme.forBrightness(brightness)
      .copyWith(blurEnabled: frostedGlassEnabled);
  final textColor = isDark ? const Color(0xFFE7EBF0) : const Color(0xFF303944);
  final surface = isDark ? const Color(0xFF23272D) : const Color(0xFFF9FBFF);
  final primary = isDark ? const Color(0xFFB5C2D3) : const Color(0xFF7488A3);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF15181C) : const Color(0xFFEDF0F4),
    extensions: [glass],
    fontFamily: useGoogleFonts ? GoogleFonts.inter().fontFamily : null,
    fontFamilyFallback: zhFallback,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: isDark ? const Color(0xFF273240) : Colors.white,
      secondary: isDark ? const Color(0xFFB0A1BC) : const Color(0xFF8F839A),
      onSecondary: isDark ? const Color(0xFF273240) : Colors.white,
      tertiary: isDark ? const Color(0xFFA3B7AD) : const Color(0xFF718F81),
      onTertiary: Colors.white,
      error: isDark ? Colors.redAccent : const Color(0xFFFF6B6B),
      onError: Colors.white,
      surface: surface,
      onSurface: textColor,
      surfaceContainerHighest:
          isDark ? const Color(0xFF31363D) : const Color(0xFFE5EAF0),
      outlineVariant:
          isDark ? const Color(0xFF363D47) : const Color(0xFFD3DAE3),
      onSurfaceVariant:
          isDark ? const Color(0xFF939CA9) : const Color(0xFF727E8D),
    ),
    textTheme: _appleishBold(interTheme, textColor),
    cardTheme: CardThemeData(
      color: glass.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: glass.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glass.field,
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
      backgroundColor: glass.rail,
      foregroundColor: textColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
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
      height: 52,
      backgroundColor: Colors.transparent,
      indicatorColor: glass.selection,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(
          fontSize: 11,
          color: textColor,
          fontWeight: FontWeight.w500,
          fontFamilyFallback: zhFallback)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: glass.raised,
      modalBackgroundColor: glass.raised,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: glass.field,
      selectedColor: glass.selection,
      secondarySelectedColor: glass.selection,
      labelStyle: WidgetStateTextStyle.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? glass.onSelection
                : textColor,
            fontSize: 12,
          )),
      side: BorderSide(color: glass.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? glass.selection
                : glass.field),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? glass.onSelection
                : textColor),
      ),
    ),
    dividerTheme: DividerThemeData(color: glass.border, thickness: 1),
  );
}

@immutable
class FrostedTheme extends ThemeExtension<FrostedTheme> {
  final bool blurEnabled;
  final Color surface,
      raised,
      border,
      selection,
      onSelection,
      field,
      rail,
      stage;

  const FrostedTheme(
      {this.blurEnabled = true,
      required this.surface,
      required this.raised,
      required this.border,
      required this.selection,
      required this.onSelection,
      required this.field,
      required this.rail,
      required this.stage});

  static FrostedTheme of(BuildContext context) =>
      Theme.of(context).extension<FrostedTheme>() ??
      forBrightness(Theme.of(context).brightness);

  static FrostedTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.dark
          ? const FrostedTheme(
              surface: Color(0xB323272D),
              raised: Color(0xC031363D),
              border: Color(0x19EBF0F7),
              selection: Color(0xFFCFD5DD),
              onSelection: Color(0xFF2B313A),
              field: Color(0x75101216),
              rail: Color(0xD0181C22),
              stage: Color(0x8C0A0D11))
          : const FrostedTheme(
              surface: Color(0xB3FFFFFF),
              raised: Color(0xC2F9FBFF),
              border: Color(0x1F485770),
              selection: Color(0xFFD2D8E1),
              onSelection: Color(0xFF303845),
              field: Color(0x99EFF2F7),
              rail: Color(0xD0FAFCFF),
              stage: Color(0x73CFD5DF));

  @override
  FrostedTheme copyWith(
          {bool? blurEnabled,
          Color? surface,
          Color? raised,
          Color? border,
          Color? selection,
          Color? onSelection,
          Color? field,
          Color? rail,
          Color? stage}) =>
      FrostedTheme(
          blurEnabled: blurEnabled ?? this.blurEnabled,
          surface: surface ?? this.surface,
          raised: raised ?? this.raised,
          border: border ?? this.border,
          selection: selection ?? this.selection,
          onSelection: onSelection ?? this.onSelection,
          field: field ?? this.field,
          rail: rail ?? this.rail,
          stage: stage ?? this.stage);

  @override
  FrostedTheme lerp(covariant FrostedTheme? other, double t) {
    if (other == null) return this;
    return FrostedTheme(
        // Apply the effect switch immediately, even during a theme transition.
        blurEnabled: other.blurEnabled,
        surface: Color.lerp(surface, other.surface, t)!,
        raised: Color.lerp(raised, other.raised, t)!,
        border: Color.lerp(border, other.border, t)!,
        selection: Color.lerp(selection, other.selection, t)!,
        onSelection: Color.lerp(onSelection, other.onSelection, t)!,
        field: Color.lerp(field, other.field, t)!,
        rail: Color.lerp(rail, other.rail, t)!,
        stage: Color.lerp(stage, other.stage, t)!);
  }
}
