import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  test('appearance mode parses and maps brightness', () {
    expect(AppearanceMode.parse('light'), AppearanceMode.light);
    expect(AppearanceMode.parse('dark'), AppearanceMode.dark);
    expect(AppearanceMode.parse('coffeePaper'), AppearanceMode.coffeePaper);
    expect(AppearanceMode.parse('unknown'), AppearanceMode.dark);
    expect(AppearanceMode.light.brightness, Brightness.light);
    expect(AppearanceMode.dark.brightness, Brightness.dark);
    expect(AppearanceMode.coffeePaper.brightness, Brightness.dark);
  });

  test('dark theme uses mist gray and neutral selection', () {
    final theme = buildNaiHuishiTheme(Brightness.dark, useGoogleFonts: false);

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF15181C));
    expect(theme.colorScheme.primary, const Color(0xFFB5C2D3));
    expect(theme.extension<FrostedTheme>()!.selection, const Color(0xFFCFD5DD));
    expect(theme.navigationBarTheme.height, 52);
  });

  test('light theme uses silver white and muted secondary colors', () {
    final theme = buildNaiHuishiTheme(Brightness.light, useGoogleFonts: false);

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFEDF0F4));
    expect(theme.colorScheme.primary, const Color(0xFF7488A3));
    expect(theme.colorScheme.secondary, const Color(0xFF8F839A));
    expect(theme.colorScheme.tertiary, const Color(0xFF718F81));
    expect(theme.colorScheme.error, const Color(0xFFFF6B6B));
  });
}
