import 'package:flutter/material.dart';

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

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDark
      ? Colors.black.withValues(alpha: 0.78)
      : Colors.black.withValues(alpha: 0.72);
  final borderColor = isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.12);
  final textColor = Colors.white;
  final iconColor = Colors.white;

  late OverlayEntry entry;
  final notifier = ValueNotifier<double>(0);
  entry = OverlayEntry(
    builder: (_) => Center(
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
                  maxWidth: MediaQuery.sizeOf(context).width - 32,
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
                      Icon(icon, size: 16, color: iconColor),
                      SizedBox(width: 8),
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
    ),
  );

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
