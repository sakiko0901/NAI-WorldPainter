import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

/// Keeps the complete image sharp while its surroundings fill the workspace.
class ImageTagWorkspace extends StatelessWidget {
  final String? imagePath;
  final bool busy;
  final VoidCallback onPickImage;

  const ImageTagWorkspace({
    super.key,
    required this.imagePath,
    required this.busy,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final minHeight = (screenHeight * .66).clamp(360.0, 760.0);
    final maxHeight = (screenHeight * .78).clamp(420.0, 920.0);
    final softenBackground =
        glass.blurEnabled && !MediaQuery.highContrastOf(context);

    return LayoutBuilder(builder: (context, constraints) {
      final path = imagePath;
      final image = path == null
          ? null
          : ResizeImage.resizeIfNeeded(
              (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              null,
              FileImage(File(path)),
            );
      return Semantics(
        button: true,
        enabled: !busy,
        label: path == null ? '选择解析图片' : '更换解析图片',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onPickImage,
          child: ClipRRect(
            key: const ValueKey('image-tag-workspace'),
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: minHeight, maxHeight: maxHeight),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ColoredBox(color: glass.stage),
                  ),
                  if (image != null && softenBackground)
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Image(
                            image: image,
                            fit: BoxFit.cover,
                            opacity: AlwaysStoppedAnimation(
                                theme.brightness == Brightness.dark ? .5 : .35),
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  if (image == null)
                    _placeholder(context, '点击选择图片')
                  else
                    Image(
                      key: ValueKey('image-tag-preview-$path'),
                      image: image,
                      width: constraints.maxWidth,
                      fit: BoxFit.contain,
                      semanticLabel: '待解析的完整图片',
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) =>
                          _placeholder(context, '无法读取图片，点击重新选择'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _placeholder(BuildContext context, String label) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.photo_on_rectangle, size: 48, color: color),
            const SizedBox(height: 14),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
