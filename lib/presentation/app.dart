import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/core/services/app_update_service.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/app_update_navigation_observer.dart';
import 'package:nai_huishi/presentation/pages/home_page.dart';
import 'package:nai_huishi/presentation/widgets/app_update_prompt_host.dart';
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
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _updateNavigationObserver = AppUpdateNavigationObserver();

  @override
  void initState() {
    super.initState();
    _loadAppearance();
    if (sl.isRegistered<AppUpdateService>()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(sl<AppUpdateService>().initialize());
      });
    }
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
  void dispose() {
    _updateNavigationObserver.dispose();
    super.dispose();
  }

  Widget _buildAppContent(Widget child) {
    if (!sl.isRegistered<AppUpdateInstallGuard>()) return child;
    final guard = sl<AppUpdateInstallGuard>();
    final content = sl.isRegistered<AppUpdateService>()
        ? AppUpdatePromptHost(
            service: sl<AppUpdateService>(),
            guard: guard,
            navigatorKey: _navigatorKey,
            rootRouteCurrent: _updateNavigationObserver.rootRouteCurrent,
            child: child,
          )
        : child;
    return ListenableBuilder(
      listenable: guard,
      child: content,
      builder: (context, child) => ExcludeFocus(
        excluding: guard.isInstalling,
        child: AbsorbPointer(
          absorbing: guard.isInstalling,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _appearanceMode.brightness;
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_updateNavigationObserver],
      debugShowCheckedModeBanner: false,
      title: 'nai 绘世',
      theme: buildNaiHuishiTheme(
        brightness,
        frostedGlassEnabled: _frostedGlassEnabled,
      ),
      builder: (context, child) => _buildAppContent(child!),
      home: HomePage(
        appearanceMode: _appearanceMode,
        onAppearanceChanged: _setAppearance,
        frostedGlassEnabled: _frostedGlassEnabled,
        onFrostedGlassChanged: _setFrostedGlass,
      ),
    );
  }
}
