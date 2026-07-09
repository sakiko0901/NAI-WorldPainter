import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/pages/history_page.dart';
import 'package:nai_huishi/presentation/pages/settings_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/history_viewmodel.dart';

class _ThemeToggleButton extends StatelessWidget {
  final Brightness brightness;
  final VoidCallback? onTap;

  const _ThemeToggleButton({required this.brightness, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    const iconGold = Color(0xFFF5D57A);
    const iconBlue = Color(0xFF3B82F6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final rotate = Tween<double>(begin: 0.72, end: 1).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: animation,
                  child: RotationTransition(turns: rotate, child: child),
                ),
              );
            },
            child: Icon(
              isDark ? CupertinoIcons.moon_stars : CupertinoIcons.sun_max,
              key: ValueKey(isDark),
              color: isDark ? iconBlue : iconGold,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  static const initialIndex = 1;

  final Brightness brightness;
  final VoidCallback? onToggleTheme;

  const HomePage({
    super.key,
    this.brightness = Brightness.dark,
    this.onToggleTheme,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = HomePage.initialIndex;

  void _switchPage(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      // 切到生成页时刷新模型列表（用户可能刚在设置页保存了供应商配置）
      if (index == 1) {
        sl<GenerationViewModel>().loadModels();
      }
      // 切到历史页时主动刷新一次（IndexedStack 不会触发子页 didChangeDependencies）
      if (index == 0) {
        sl<HistoryViewModel>().loadHistory(refresh: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // 页面内容
          IndexedStack(
            index: _currentIndex,
            children: [
              HistoryPage(onNavigate: _switchPage), // 0
              GeneratePage(onNavigate: _switchPage), // 1
              SettingsPage(onNavigateToGenerate: () => _switchPage(1)), // 2
            ],
          ),

          if (_currentIndex == 1)
            Positioned(
              left: 14,
              top: MediaQuery.paddingOf(context).top + 10,
              child: _ThemeToggleButton(
                brightness: widget.brightness,
                onTap: widget.onToggleTheme,
              ),
            ),

          // 在非生成页时，显示一个简化的底部导航
          if (_currentIndex != 1) // 只要不在生成页，就显示导航
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildSimpleBottomBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildSimpleBottomBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64 + MediaQuery.paddingOf(context).bottom,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E).withValues(alpha: 0.8) : surface.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFBBD7FF),
                width: 0.5,
              ),
            ),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, CupertinoIcons.clock, CupertinoIcons.clock_fill, '历史'),
              _buildNavItem(1, CupertinoIcons.paintbrush, CupertinoIcons.paintbrush_fill, '生成'),
              _buildNavItem(2, CupertinoIcons.settings, CupertinoIcons.settings_solid, '更多'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _switchPage(index),
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: color,
              size: 24,
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
