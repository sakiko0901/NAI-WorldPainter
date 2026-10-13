import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

class FrostedSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  const FrostedSurface(
      {super.key,
      required this.child,
      this.padding = EdgeInsets.zero,
      this.radius = 18,
      this.blur = 18});

  @override
  Widget build(BuildContext context) {
    final glass = FrostedTheme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: highContrast
            ? Theme.of(context).colorScheme.surface
            : glass.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glass.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(padding: padding, child: child),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur <= 0 || highContrast
          ? content
          : BackdropFilter.grouped(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: content),
    );
  }
}
