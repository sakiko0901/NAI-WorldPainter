import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/app_destination.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/pages/history_page.dart';
import 'package:nai_huishi/presentation/pages/settings_page.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/fountain_pen_icon.dart';

class HomePage extends StatefulWidget {
  static const initialIndex = 0;

  final AppearanceMode appearanceMode;
  final ValueChanged<AppearanceMode> onAppearanceChanged;
  final bool frostedGlassEnabled;
  final ValueChanged<bool>? onFrostedGlassChanged;

  const HomePage({
    super.key,
    required this.appearanceMode,
    required this.onAppearanceChanged,
    this.frostedGlassEnabled = true,
    this.onFrostedGlassChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppDestination _destination = AppDestination.create;
  bool _hasVisitedAssistant = false;
  bool _hasVisitedTools = false;
  Route<void>? _galleryRoute;

  void _selectDestination(AppDestination destination) {
    if (destination == _destination &&
        (destination != AppDestination.assistant || _hasVisitedAssistant) &&
        (destination != AppDestination.tools || _hasVisitedTools)) {
      return;
    }

    setState(() {
      _destination = destination;
      if (destination == AppDestination.assistant) {
        _hasVisitedAssistant = true;
      } else if (destination == AppDestination.tools) {
        _hasVisitedTools = true;
      }
    });
  }

  void _handleLegacyNavigation(int index) {
    if (index == 0) {
      _selectDestination(AppDestination.create);
      unawaited(_openGallery());
      return;
    }

    final destination = AppDestination.fromLegacyTabIndex(index);
    if (destination == null) return;

    if (destination == AppDestination.create) {
      _returnToCreate();
    } else {
      _selectDestination(destination);
    }
  }

  Future<void> _openGallery() async {
    if (_galleryRoute != null) return;

    FocusManager.instance.primaryFocus?.unfocus();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final route = PageRouteBuilder<void>(
      transitionDuration: Duration(milliseconds: reduceMotion ? 0 : 280),
      reverseTransitionDuration: Duration(milliseconds: reduceMotion ? 0 : 280),
      pageBuilder: (_, __, ___) =>
          HistoryPage(onNavigate: _handleLegacyNavigation),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    );
    _galleryRoute = route;
    try {
      await Navigator.of(context).push<void>(route);
    } finally {
      if (mounted && identical(_galleryRoute, route)) {
        setState(() => _galleryRoute = null);
      }
    }
  }

  void _returnToCreate() {
    // Legacy callers may still be inside a detail page. Returning to the
    // persistent creation destination should close the Gallery route as well.
    Navigator.of(context).popUntil((route) => route.isFirst);
    _selectDestination(AppDestination.create);
  }

  Widget _withDestinationTicker(AppDestination destination, Widget child) {
    return TickerMode(enabled: destination == _destination, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndexedStack(
        index: _destination.index,
        children: [
          _withDestinationTicker(
            AppDestination.create,
            GeneratePage(
              onNavigate: _handleLegacyNavigation,
              onOpenAssistant: () =>
                  _selectDestination(AppDestination.assistant),
            ),
          ),
          _withDestinationTicker(
            AppDestination.assistant,
            _hasVisitedAssistant
                ? ChatDrawer(
                    key: const ValueKey('assistant-destination'),
                    embedded: true,
                    active: _destination == AppDestination.assistant,
                    title: 'AI 助手',
                    onClose: () => _selectDestination(AppDestination.create),
                  )
                : const SizedBox.shrink(),
          ),
          _withDestinationTicker(
            AppDestination.tools,
            _hasVisitedTools
                ? SettingsPage(
                    key: const ValueKey('tools-destination'),
                    appearanceMode: widget.appearanceMode,
                    onAppearanceChanged: widget.onAppearanceChanged,
                    frostedGlassEnabled: widget.frostedGlassEnabled,
                    onFrostedGlassChanged: widget.onFrostedGlassChanged,
                    onNavigateToGenerate: _returnToCreate,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : FrostedSurface(
              radius: 0,
              blur: 18,
              child: NavigationBar(
                height: 52 +
                    ((MediaQuery.textScalerOf(context).scale(11) - 11) * 1.5)
                        .clamp(0, 24),
                animationDuration: Duration(
                    milliseconds:
                        MediaQuery.disableAnimationsOf(context) ? 0 : 200),
                selectedIndex: _destination.index,
                onDestinationSelected: (index) =>
                    _selectDestination(AppDestination.values[index]),
                destinations: [
                  NavigationDestination(
                    label: AppDestination.create.label,
                    tooltip: AppDestination.create.label,
                    icon: const FountainPenIcon(),
                    selectedIcon: FountainPenIcon(
                        color: FrostedTheme.of(context).onSelection),
                  ),
                  _navigationDestination(
                    label: AppDestination.assistant.label,
                    icon: CupertinoIcons.sparkles,
                    selectedIcon: CupertinoIcons.sparkles,
                  ),
                  _navigationDestination(
                    label: AppDestination.tools.label,
                    icon: CupertinoIcons.square_grid_2x2,
                    selectedIcon: CupertinoIcons.square_grid_2x2_fill,
                  ),
                ],
              )),
    );
  }

  NavigationDestination _navigationDestination({
    required String label,
    required IconData icon,
    required IconData selectedIcon,
  }) {
    return NavigationDestination(
      icon: Icon(icon, size: 20),
      selectedIcon: Icon(selectedIcon,
          size: 20, color: FrostedTheme.of(context).onSelection),
      label: label,
      tooltip: label,
    );
  }
}
