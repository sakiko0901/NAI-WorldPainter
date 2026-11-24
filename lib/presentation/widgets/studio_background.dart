import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

/// The ambient image is filtered once; foreground panels keep their content sharp.
class StudioBackground extends StatelessWidget {
  final ImageProvider? image;
  final double? headerGridInset;
  final bool showHeaderArtwork;

  const StudioBackground({
    super.key,
    this.image,
    this.headerGridInset,
    this.showHeaderArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) {
      final gridInset = headerGridInset;
      return IgnorePointer(
        child: ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: gridInset == null || MediaQuery.highContrastOf(context)
              ? null
              : Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: gridInset),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size(
                            double.infinity, showHeaderArtwork ? 360 : 184),
                        painter: _HeaderGridPainter(
                          theme.colorScheme.onSurface,
                          showArtwork: showHeaderArtwork,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
    }
    final glass = FrostedTheme.of(context);
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (glass.appearanceMode == AppearanceMode.coffeePaper)
              ColoredBox(color: theme.scaffoldBackgroundColor)
            else
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
            if (image != null && glass.blurEnabled)
              Opacity(
                opacity: 0.07,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
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

class _HeaderGridPainter extends CustomPainter {
  const _HeaderGridPainter(this.ink, {required this.showArtwork});

  final Color ink;
  final bool showArtwork;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    final right = size.width - inset;
    if (right <= inset || size.height <= 0) return;

    if (showArtwork) {
      // Blend two versions of the decoration, leaving the page behind it sharp.
      for (final soft in [true, false]) {
        final artworkHeight = size.height.clamp(0.0, 264.0).toDouble();
        _paintArtwork(
          canvas,
          Size(size.width, artworkHeight),
          right,
          _fadingPaint(artworkHeight, .12, soft: soft),
        );
        _paintGrid(
          canvas,
          size,
          inset,
          right,
          _fadingPaint(size.height, .12, soft: soft)..strokeWidth = .65,
        );
      }
      return;
    }

    final paint = Paint()
      ..strokeWidth = .65
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [ink.withValues(alpha: .12), ink.withValues(alpha: 0)],
        [0, 1],
      );
    _paintGrid(canvas, size, inset, right, paint);
  }

  Paint _fadingPaint(double height, double opacity, {required bool soft}) {
    final weights = soft
        ? const [.70, .78, 0.0, 0.0, 0.0]
        : const [0.0, 0.0, 1.0, .55, 0.0];
    return Paint()
      ..maskFilter =
          soft ? const ui.MaskFilter.blur(ui.BlurStyle.normal, 4) : null
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, height),
        [for (final weight in weights) ink.withValues(alpha: opacity * weight)],
        const [0, .12, .39, .65, 1],
      );
  }

  void _paintGrid(
      Canvas canvas, Size size, double inset, double right, Paint paint) {
    const spacing = 56.0;
    for (var x = inset; x <= right; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 12.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(inset, y), Offset(right, y), paint);
    }
  }

  void _paintArtwork(Canvas canvas, Size size, double right, Paint paint) {
    final width = size.width;
    final height = size.height;
    // Staggered planes suggest a pair of cutting mats behind the tool list.
    canvas.drawPath(
      Path()
        ..moveTo(width * .52, 14)
        ..lineTo(right - 18, 14)
        ..lineTo(right, 32)
        ..lineTo(right, height * .82)
        ..lineTo(width * .80, height * .82)
        ..close(),
      paint,
    );
    paint.color = Colors.white.withValues(alpha: .47);
    canvas.drawPath(
      Path()
        ..moveTo(width * .64, 40)
        ..lineTo(right, 40)
        ..lineTo(right, height)
        ..lineTo(width * .92, height)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HeaderGridPainter oldDelegate) =>
      ink != oldDelegate.ink || showArtwork != oldDelegate.showArtwork;
}
