import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NaiHuishiApp extends StatefulWidget {
  const NaiHuishiApp({super.key});

  @override
  State<NaiHuishiApp> createState() => _NaiHuishiAppState();
}

class _NaiHuishiAppState extends State<NaiHuishiApp> {
  static const _appearanceKey = 'appearance_mode';
  static const _frostedGlassKey = 'frosted_glass_enabled';
  AppearanceMode _appearanceMode = AppearanceMode.dark;
  bool _frostedGlassEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = AppearanceMode.parse(prefs.getString(_appearanceKey));
    if (mounted) {
      setState(() {
        _appearanceMode = mode;
        _frostedGlassEnabled = prefs.getBool(_frostedGlassKey) ?? true;
      });
    }
  }

  Future<void> _setAppearance(AppearanceMode mode) async {
    if (mode == AppearanceMode.coffeePaper) return;
    setState(() => _appearanceMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appearanceKey, mode.name);
  }

  Future<void> _setFrostedGlass(bool enabled) async {
    setState(() => _frostedGlassEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_frostedGlassKey, enabled);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _appearanceMode.brightness;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'nai 绘世',
      theme: buildNaiHuishiTheme(
        brightness,
        frostedGlassEnabled: _frostedGlassEnabled,
      ),
      home: HomePage(
        appearanceMode: _appearanceMode,
        onAppearanceChanged: _setAppearance,
        frostedGlassEnabled: _frostedGlassEnabled,
        onFrostedGlassChanged: _setFrostedGlass,
      ),
    );
  }
}
