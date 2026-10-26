import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

/// The ambient image is filtered once; foreground panels keep their content sharp.
class StudioBackground extends StatelessWidget {
  final ImageProvider? image;

  const StudioBackground({super.key, this.image});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.07),
                    theme.scaffoldBackgroundColor,
                    theme.colorScheme.primary.withValues(alpha: 0.025),
                  ],
                ),
              ),
            ),
            if (image != null && FrostedTheme.of(context).blurEnabled)
              Opacity(
                opacity: theme.brightness == Brightness.dark ? 0.09 : 0.07,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                  child: Image(
                    image: image!,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
