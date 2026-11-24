import 'package:flutter/cupertino.dart' show NoDefaultCupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        AppearanceMode.light || AppearanceMode.coffeePaper => Brightness.light,
        AppearanceMode.dark => Brightness.dark,
      };
}

const _darkBackground = Color(0xFF1A1A1A);
const _darkSurface = Color(0xFF242424);
const _darkRaised = Color(0xFF303030);
const _darkControl = Color(0xFF3B3B3B);
const _darkInk = Color(0xFFF2F2F2);
const _darkMuted = Color(0xFFB7B7B7);
const _darkPrimary = Color(0xFFE3E3E3);

final _darkColors = ColorScheme.fromSeed(
  seedColor: _darkPrimary,
  brightness: Brightness.dark,
  dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
).copyWith(
  primary: _darkPrimary,
  onPrimary: _darkBackground,
  primaryContainer: _darkControl,
  onPrimaryContainer: _darkInk,
  secondaryContainer: _darkControl,
  onSecondaryContainer: _darkInk,
  surface: _darkSurface,
  surfaceDim: _darkBackground,
  surfaceBright: _darkControl,
  surfaceContainerLowest: _darkBackground,
  surfaceContainerLow: _darkSurface,
  surfaceContainer: const Color(0xFF292929),
  surfaceContainerHigh: _darkRaised,
  surfaceContainerHighest: _darkControl,
  surfaceTint: Colors.transparent,
  onSurface: _darkInk,
  onSurfaceVariant: _darkMuted,
  outline: const Color(0xFF8F8F8F),
  outlineVariant: const Color(0xFF414141),
);

const _coffeePaperBackground = Color(0xFFF3EDE2);
const _coffeePaperColors = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFA24E37),
  onPrimary: Color(0xFFFFFBF5),
  primaryContainer: Color(0xFFF2D7C9),
  onPrimaryContainer: Color(0xFF622F21),
  secondary: Color(0xFF755846),
  onSecondary: Color(0xFFFFFBF5),
  secondaryContainer: Color(0xFFEDE0D1),
  onSecondaryContainer: Color(0xFF4E382B),
  tertiary: Color(0xFF566448),
  onTertiary: Color(0xFFFFFBF5),
  tertiaryContainer: Color(0xFFE2E8D6),
  onTertiaryContainer: Color(0xFF38452C),
  error: Color(0xFFA3342A),
  onError: Color(0xFFFFFBF5),
  errorContainer: Color(0xFFF8DED7),
  onErrorContainer: Color(0xFF702720),
  surface: Color(0xFFFCF8F0),
  onSurface: Color(0xFF362820),
  onSurfaceVariant: Color(0xFF6D584A),
  surfaceDim: Color(0xFFE8DACA),
  surfaceBright: Color(0xFFFFFBF5),
  surfaceContainerLowest: Color(0xFFFFFBF5),
  surfaceContainerLow: Color(0xFFFAF4EA),
  surfaceContainer: Color(0xFFF7EFE4),
  surfaceContainerHigh: Color(0xFFF2E8DC),
  surfaceContainerHighest: Color(0xFFEEE0D1),
  outline: Color(0xFF87705D),
  outlineVariant: Color(0xFFD9C8B6),
  inverseSurface: Color(0xFF47352B),
  onInverseSurface: Color(0xFFFFF6E9),
  inversePrimary: Color(0xFFF3B89F),
  shadow: Color(0xFF493326),
  scrim: Color(0xFF362820),
  surfaceTint: Colors.transparent,
);

const _coffeePaperOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);

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
}) =>
    buildNaiHuishiAppearanceTheme(
      brightness == Brightness.dark
          ? AppearanceMode.dark
          : AppearanceMode.light,
      useGoogleFonts: useGoogleFonts,
      frostedGlassEnabled: frostedGlassEnabled,
    );

ThemeData buildNaiHuishiAppearanceTheme(
  AppearanceMode appearanceMode, {
  bool useGoogleFonts = false,
  bool frostedGlassEnabled = true,
}) {
  final brightness = appearanceMode.brightness;
  final isDark = brightness == Brightness.dark;
  final isCoffeePaper = appearanceMode == AppearanceMode.coffeePaper;
  final baseTheme = ThemeData(brightness: brightness).textTheme;
  final interTheme =
      useGoogleFonts ? GoogleFonts.interTextTheme(baseTheme) : baseTheme;
  final glass = FrostedTheme.forAppearance(appearanceMode)
      .copyWith(blurEnabled: frostedGlassEnabled);
  final colors = switch (appearanceMode) {
    AppearanceMode.dark => _darkColors,
    AppearanceMode.light => _lightColors(),
    AppearanceMode.coffeePaper => _coffeePaperColors,
  };
  final useThemedSurfaces = isDark || isCoffeePaper;
  final textColor = colors.onSurface;
  final textTheme = _appleishBold(interTheme, textColor);
  final primary = colors.primary;
  final popupSurface =
      isDark ? colors.surfaceContainerHigh : colors.surfaceContainerLowest;
  final modalBarrier =
      isCoffeePaper ? colors.scrim.withValues(alpha: 0.42) : null;
  final popupOutline =
      isCoffeePaper ? BorderSide(color: glass.border) : BorderSide.none;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: switch (appearanceMode) {
      AppearanceMode.light => const Color(0xFFEDF0F4),
      AppearanceMode.dark => _darkBackground,
      AppearanceMode.coffeePaper => _coffeePaperBackground,
    },
    canvasColor: useThemedSurfaces ? popupSurface : null,
    cupertinoOverrideTheme: useThemedSurfaces
        ? NoDefaultCupertinoThemeData(
            primaryColor: primary,
            primaryContrastingColor: colors.onPrimary,
            scaffoldBackgroundColor:
                isDark ? _darkBackground : _coffeePaperBackground,
            barBackgroundColor: glass.rail,
            applyThemeToAll: true,
          )
        : null,
    extensions: [glass],
    fontFamily: useGoogleFonts ? GoogleFonts.inter().fontFamily : null,
    fontFamilyFallback: zhFallback,
    colorScheme: colors,
    textTheme: textTheme,
    textSelectionTheme: useThemedSurfaces
        ? TextSelectionThemeData(
            cursorColor: primary,
            selectionColor: primary.withValues(alpha: 0.24),
            selectionHandleColor: primary,
          )
        : null,
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
      systemOverlayStyle: isCoffeePaper ? _coffeePaperOverlayStyle : null,
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
      indicatorColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(
          fontSize: 11,
          color: textColor,
          fontWeight: FontWeight.w500,
          fontFamilyFallback: zhFallback)),
    ),
    dialogTheme: useThemedSurfaces
        ? DialogThemeData(
            backgroundColor: popupSurface,
            barrierColor: modalBarrier,
            surfaceTintColor: Colors.transparent,
            shadowColor: colors.shadow.withValues(alpha: 0.24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: popupOutline,
            ),
          )
        : null,
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isCoffeePaper ? popupSurface : glass.raised,
      modalBackgroundColor: isCoffeePaper ? popupSurface : glass.raised,
      modalBarrierColor: modalBarrier,
      surfaceTintColor: useThemedSurfaces ? Colors.transparent : null,
      dragHandleColor: isCoffeePaper ? colors.outline : null,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: useThemedSurfaces
        ? PopupMenuThemeData(
            color: popupSurface,
            surfaceTintColor: Colors.transparent,
            shadowColor: colors.shadow.withValues(alpha: 0.20),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: popupOutline,
            ),
          )
        : null,
    chipTheme: ChipThemeData(
      backgroundColor: glass.field,
      selectedColor: glass.selection,
      secondarySelectedColor: glass.selection,
      labelStyle: textTheme.labelSmall?.copyWith(
        fontSize: 12,
        color: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return textColor.withValues(alpha: 0.38);
          }
          return states.contains(WidgetState.selected)
              ? glass.onSelection
              : textColor;
        }),
      ),
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
    dividerColor: useThemedSurfaces ? glass.border : null,
    dividerTheme: DividerThemeData(color: glass.border, thickness: 1),
  );
}

ColorScheme _lightColors() {
  const primary = Color(0xFF7488A3);
  return ColorScheme.fromSeed(seedColor: primary).copyWith(
    primary: primary,
    onPrimary: Colors.white,
    secondary: const Color(0xFF8F839A),
    onSecondary: Colors.white,
    tertiary: const Color(0xFF718F81),
    onTertiary: Colors.white,
    error: const Color(0xFFFF6B6B),
    onError: Colors.white,
    surface: const Color(0xFFF9FBFF),
    onSurface: const Color(0xFF303944),
    surfaceContainerHighest: const Color(0xFFE5EAF0),
    outlineVariant: const Color(0xFFD3DAE3),
    onSurfaceVariant: const Color(0xFF727E8D),
  );
}

@immutable
class FrostedTheme extends ThemeExtension<FrostedTheme> {
  final AppearanceMode appearanceMode;
  final bool blurEnabled;
  final Color surface,
      panel,
      raised,
      border,
      selection,
      onSelection,
      field,
      rail,
      stage;

  const FrostedTheme(
      {required this.appearanceMode,
      this.blurEnabled = true,
      required this.surface,
      required this.panel,
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
      forAppearance(brightness == Brightness.dark
          ? AppearanceMode.dark
          : AppearanceMode.light);

  static FrostedTheme forAppearance(AppearanceMode appearanceMode) =>
      switch (appearanceMode) {
        AppearanceMode.dark => const FrostedTheme(
            appearanceMode: AppearanceMode.dark,
            surface: Color(0xD9242424),
            panel: _darkSurface,
            raised: Color(0xEB3B3B3B),
            border: Color(0x24FFFFFF),
            selection: _darkPrimary,
            onSelection: _darkBackground,
            field: Color(0xDB202020),
            rail: Color(0xDB262626),
            stage: Color(0xFF161616)),
        AppearanceMode.light => const FrostedTheme(
            appearanceMode: AppearanceMode.light,
            surface: Color(0xB3FFFFFF),
            panel: Colors.white,
            raised: Color(0xC2F9FBFF),
            border: Color(0x1F485770),
            selection: Color(0xFFD2D8E1),
            onSelection: Color(0xFF303845),
            field: Color(0x99EFF2F7),
            rail: Color(0xD0FAFCFF),
            stage: Color(0x73CFD5DF)),
        AppearanceMode.coffeePaper => FrostedTheme(
            appearanceMode: appearanceMode,
            surface: _coffeePaperColors.surface.withValues(alpha: 0.93),
            panel: _coffeePaperColors.surface,
            raised: _coffeePaperColors.surfaceContainerLowest
                .withValues(alpha: 0.96),
            border: _coffeePaperColors.outlineVariant,
            selection: _coffeePaperColors.primaryContainer,
            onSelection: _coffeePaperColors.onPrimaryContainer,
            field: _coffeePaperColors.surfaceContainerHigh,
            rail: _coffeePaperColors.surfaceContainer.withValues(alpha: 0.92),
            stage: _coffeePaperColors.surfaceDim),
      };

  @override
  FrostedTheme copyWith(
          {bool? blurEnabled,
          Color? surface,
          Color? panel,
          Color? raised,
          Color? border,
          Color? selection,
          Color? onSelection,
          Color? field,
          Color? rail,
          Color? stage}) =>
      FrostedTheme(
          appearanceMode: appearanceMode,
          blurEnabled: blurEnabled ?? this.blurEnabled,
          surface: surface ?? this.surface,
          panel: panel ?? this.panel,
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
        appearanceMode: other.appearanceMode,
        // Apply the effect switch immediately, even during a theme transition.
        blurEnabled: other.blurEnabled,
        surface: Color.lerp(surface, other.surface, t)!,
        panel: Color.lerp(panel, other.panel, t)!,
        raised: Color.lerp(raised, other.raised, t)!,
        border: Color.lerp(border, other.border, t)!,
        selection: Color.lerp(selection, other.selection, t)!,
        onSelection: Color.lerp(onSelection, other.onSelection, t)!,
        field: Color.lerp(field, other.field, t)!,
        rail: Color.lerp(rail, other.rail, t)!,
        stage: Color.lerp(stage, other.stage, t)!);
  }
}
