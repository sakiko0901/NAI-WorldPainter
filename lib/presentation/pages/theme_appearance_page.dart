import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

class ThemeAppearancePage extends StatefulWidget {
  final AppearanceMode appearanceMode;
  final ValueChanged<AppearanceMode> onAppearanceChanged;
  final bool frostedGlassEnabled;
  final ValueChanged<bool>? onFrostedGlassChanged;

  const ThemeAppearancePage({
    super.key,
    required this.appearanceMode,
    required this.onAppearanceChanged,
    this.frostedGlassEnabled = true,
    this.onFrostedGlassChanged,
  });

  @override
  State<ThemeAppearancePage> createState() => _ThemeAppearancePageState();
}

class _ThemeAppearancePageState extends State<ThemeAppearancePage> {
  late AppearanceMode _selectedMode;
  late bool _frostedGlassEnabled;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.appearanceMode;
    _frostedGlassEnabled = widget.frostedGlassEnabled;
  }

  void _select(AppearanceMode mode) {
    setState(() => _selectedMode = mode);
    widget.onAppearanceChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    final glass = FrostedTheme.of(context);

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
            child: Material(
              color: glass.panel,
              child: Column(
                children: [
                  _AppearanceOption(
                    icon: CupertinoIcons.sun_max_fill,
                    title: '亮色',
                    selected: _selectedMode == AppearanceMode.light,
                    onTap: () => _select(AppearanceMode.light),
                  ),
                  const Divider(height: 1, indent: 58),
                  _AppearanceOption(
                    icon: CupertinoIcons.moon_stars_fill,
                    title: '暗色',
                    selected: _selectedMode == AppearanceMode.dark,
                    onTap: () => _select(AppearanceMode.dark),
                  ),
                  const Divider(height: 1, indent: 58),
                  _AppearanceOption(
                    icon: CupertinoIcons.doc_text_fill,
                    title: '咖啡纸',
                    selected: _selectedMode == AppearanceMode.coffeePaper,
                    onTap: () => _select(AppearanceMode.coffeePaper),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Material(
              color: glass.panel,
              child: SwitchListTile.adaptive(
                key: const ValueKey('frosted-glass-switch'),
                title: const Text('毛玻璃效果'),
                subtitle: const Text('关闭后停用界面模糊与图片氛围背景，保留配色和布局'),
                value: _frostedGlassEnabled,
                onChanged: widget.onFrostedGlassChanged == null
                    ? null
                    : (enabled) {
                        setState(() => _frostedGlassEnabled = enabled);
                        widget.onFrostedGlassChanged!(enabled);
                      },
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
  final bool selected;
  final VoidCallback onTap;

  const _AppearanceOption({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final glass = FrostedTheme.of(context);
    final highlight =
        selected && glass.appearanceMode == AppearanceMode.coffeePaper;
    return Semantics(
      selected: selected,
      child: Ink(
        color: highlight ? glass.selection.withValues(alpha: 0.45) : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon,
                    size: 22,
                    color: selected ? colors.primary : colors.onSurfaceVariant),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? colors.primary : colors.onSurface,
                    ),
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
        ),
      ),
    );
  }
}
