import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

/// 屏幕中央悬浮 Toast，淡入淡出 + 自动消失。
/// 使用 Overlay，不阻塞用户操作，不依赖 Scaffold。
void showFloatingToast(
  BuildContext context,
  String text, {
  Duration duration = const Duration(milliseconds: 1400),
  IconData? icon,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  final notifier = ValueNotifier<double>(0);
  entry = OverlayEntry(builder: (overlayContext) {
    final theme = Theme.of(overlayContext);
    final glass = FrostedTheme.of(overlayContext);
    final isDark = theme.brightness == Brightness.dark;
    final isCoffeePaper = glass.appearanceMode == AppearanceMode.coffeePaper;
    final bgColor = isCoffeePaper
        ? theme.colorScheme.inverseSurface
        : Colors.black.withValues(alpha: isDark ? 0.78 : 0.72);
    final textColor =
        isCoffeePaper ? theme.colorScheme.onInverseSurface : Colors.white;
    final borderColor = textColor.withValues(alpha: isDark ? 0.08 : 0.12);

    return Center(
      child: IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: notifier,
          builder: (_, opacity, __) => AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 180),
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(overlayContext).width - 32,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: textColor),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 14,
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  });

  overlay.insert(entry);
  // 淡入
  WidgetsBinding.instance.addPostFrameCallback((_) => notifier.value = 1);
  // 持续后淡出移除
  Future.delayed(duration, () {
    notifier.value = 0;
    Future.delayed(const Duration(milliseconds: 220), () {
      entry.remove();
      notifier.dispose();
    });
  });
}
