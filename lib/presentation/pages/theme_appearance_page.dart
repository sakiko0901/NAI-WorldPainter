import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class ThemeAppearancePage extends StatefulWidget {
  final AppearanceMode appearanceMode;
  final ValueChanged<AppearanceMode> onAppearanceChanged;

  const ThemeAppearancePage({
    super.key,
    required this.appearanceMode,
    required this.onAppearanceChanged,
  });

  @override
  State<ThemeAppearancePage> createState() => _ThemeAppearancePageState();
}

class _ThemeAppearancePageState extends State<ThemeAppearancePage> {
  late AppearanceMode _selectedMode;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.appearanceMode;
  }

  void _select(AppearanceMode mode) {
    setState(() => _selectedMode = mode);
    widget.onAppearanceChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.08);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('主题与外观'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ColoredBox(
              color: isDark ? const Color(0xFF1C1C21) : Colors.white,
              child: Column(
                children: [
                  _AppearanceOption(
                    icon: CupertinoIcons.sun_max_fill,
                    title: '亮色',
                    selected: _selectedMode == AppearanceMode.light,
                    onTap: () => _select(AppearanceMode.light),
                  ),
                  Divider(height: 1, indent: 58, color: dividerColor),
                  _AppearanceOption(
                    icon: CupertinoIcons.moon_stars_fill,
                    title: '暗色',
                    selected: _selectedMode == AppearanceMode.dark,
                    onTap: () => _select(AppearanceMode.dark),
                  ),
                  Divider(height: 1, indent: 58, color: dividerColor),
                  _AppearanceOption(
                    icon: CupertinoIcons.doc_text_fill,
                    title: '咖啡纸',
                    subtitle: '即将推出',
                    selected: false,
                    onTap: () => showFloatingToast(
                      context,
                      '咖啡纸主题暂不可用',
                      icon: CupertinoIcons.info_circle_fill,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _AppearanceOption({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: selected ? colors.primary : null),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? colors.primary : colors.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 21,
              color: selected
                  ? colors.primary
                  : colors.onSurfaceVariant.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}
