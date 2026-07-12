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

  test('dark theme keeps black and gold palette', () {
    final theme = buildNaiHuishiTheme(Brightness.dark, useGoogleFonts: false);

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0A0A0C));
    expect(theme.colorScheme.primary, const Color(0xFFF5D57A));
  });

  test('light theme uses soft white and blue palette with extra colors', () {
    final theme = buildNaiHuishiTheme(Brightness.light, useGoogleFonts: false);

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF2F4F8));
    expect(theme.colorScheme.primary, const Color(0xFF3B82F6));
    expect(theme.colorScheme.secondary, const Color(0xFF8B5CF6));
    expect(theme.colorScheme.tertiary, const Color(0xFF14B8A6));
    expect(theme.colorScheme.error, const Color(0xFFFF6B6B));
  });
}
