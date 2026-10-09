import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/services/comic_overlay_renderer.dart';

class ComicCanvas extends StatefulWidget {
  final ComicPanel panel;
  final String imagePath;
  final String? selectedOverlayId;
  final ValueChanged<String> onSelectOverlay;
  final ValueChanged<ComicOverlay> onUpdateOverlay;
  final bool brushMode;
  final ValueChanged<ComicPoint>? onBrushStart;
  final ValueChanged<ComicPoint>? onBrushUpdate;
  final VoidCallback? onBrushEnd;

  const ComicCanvas({
    super.key,
    required this.panel,
    required this.imagePath,
    required this.selectedOverlayId,
    required this.onSelectOverlay,
    required this.onUpdateOverlay,
    this.brushMode = false,
    this.onBrushStart,
    this.onBrushUpdate,
    this.onBrushEnd,
  });

  @override
  State<ComicCanvas> createState() => _ComicCanvasState();
}

class _ComicCanvasState extends State<ComicCanvas> {
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void didUpdateWidget(covariant ComicCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _imageSize = null;
      _loadImageSize();
    }
  }

  Future<void> _loadImageSize() async {
    final file = File(widget.imagePath);
    if (!await file.exists()) return;
    try {
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (mounted) {
        setState(() => _imageSize = Size(
              frame.image.width.toDouble(),
              frame.image.height.toDouble(),
            ));
      }
    } catch (_) {
      // Image.file renders its own error state for corrupted image assets.
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.imagePath);
    if (!file.existsSync()) return const Center(child: Text('分镜主图不可用'));
    final imageSize = _imageSize;
    if (imageSize == null)
      return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (context, constraints) {
      final aspect = imageSize.width / imageSize.height;
      var width = constraints.maxWidth;
      var height = width / aspect;
      if (height > constraints.maxHeight) {
        height = constraints.maxHeight;
        width = height * aspect;
      }
      final canvasSize = Size(width, height);
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: Image.file(file, fit: BoxFit.fill)),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _OverlayPainter(widget.panel.overlays),
                  ),
                ),
              ),
              if (widget.brushMode)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => widget.onBrushStart?.call(
                      ComicPoint(
                        x: (event.localPosition.dx / canvasSize.width)
                            .clamp(0.0, 1.0),
                        y: (event.localPosition.dy / canvasSize.height)
                            .clamp(0.0, 1.0),
                      ),
                    ),
                    onPointerMove: (event) => widget.onBrushUpdate?.call(
                      ComicPoint(
                        x: (event.localPosition.dx / canvasSize.width)
                            .clamp(0.0, 1.0),
                        y: (event.localPosition.dy / canvasSize.height)
                            .clamp(0.0, 1.0),
                      ),
                    ),
                    onPointerUp: (_) => widget.onBrushEnd?.call(),
                  ),
                )
              else
                ...widget.panel.overlays
                    .where((overlay) => overlay.visible)
                    .map((overlay) => _OverlayHitBox(
                          overlay: overlay,
                          canvasSize: canvasSize,
                          selected: overlay.id == widget.selectedOverlayId,
                          onSelect: () => widget.onSelectOverlay(overlay.id),
                          onUpdate: widget.onUpdateOverlay,
                        )),
            ],
          ),
        ),
      );
    });
  }
}

class _OverlayPainter extends CustomPainter {
  final List<ComicOverlay> overlays;

  const _OverlayPainter(this.overlays);

  @override
  void paint(Canvas canvas, Size size) {
    ComicOverlayRenderer.drawAll(canvas, size, overlays);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) =>
      oldDelegate.overlays != overlays;
}

class _OverlayHitBox extends StatelessWidget {
  final ComicOverlay overlay;
  final Size canvasSize;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<ComicOverlay> onUpdate;

  const _OverlayHitBox({
    required this.overlay,
    required this.canvasSize,
    required this.selected,
    required this.onSelect,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final rect = ComicOverlayRenderer.rectFor(canvasSize, overlay.rect);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        onTap: onSelect,
        onPanUpdate: (details) {
          final x = (overlay.rect.x + details.delta.dx / canvasSize.width)
              .clamp(0.0, 1.0 - overlay.rect.width);
          final y = (overlay.rect.y + details.delta.dy / canvasSize.height)
              .clamp(0.0, 1.0 - overlay.rect.height);
          onUpdate(overlay.copyWith(
            rect: ComicRect(
              x: x,
              y: y,
              width: overlay.rect.width,
              height: overlay.rect.height,
            ),
          ));
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            if (selected && overlay.type == ComicOverlayType.bubble)
              _TailHandle(overlay: overlay, rect: rect, onUpdate: onUpdate),
            if (selected)
              Positioned(
                right: -9,
                bottom: -9,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final width = (overlay.rect.width +
                            details.delta.dx / canvasSize.width)
                        .clamp(0.08, 1.0 - overlay.rect.x);
                    final height = (overlay.rect.height +
                            details.delta.dy / canvasSize.height)
                        .clamp(0.06, 1.0 - overlay.rect.y);
                    onUpdate(overlay.copyWith(
                      rect: ComicRect(
                        x: overlay.rect.x,
                        y: overlay.rect.y,
                        width: width,
                        height: height,
                      ),
                    ));
                  },
                  child: _ControlHandle(
                    icon: Icons.open_in_full,
                    color: Theme.of(context).colorScheme.primary,
                    foreground: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TailHandle extends StatelessWidget {
  final ComicOverlay overlay;
  final Rect rect;
  final ValueChanged<ComicOverlay> onUpdate;

  const _TailHandle({
    required this.overlay,
    required this.rect,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final target = ComicOverlayRenderer.tailTargetFor(rect, overlay);
    return Positioned(
      left: target.dx - rect.left - 11,
      top: target.dy - rect.top - 11,
      child: GestureDetector(
        onPanUpdate: (details) {
          final next = target + details.delta;
          onUpdate(overlay.copyWith(
            tailX: (next.dx - rect.left) / rect.width,
            tailY: (next.dy - rect.top) / rect.height,
          ));
        },
        child: _ControlHandle(
          icon: Icons.near_me,
          color: Theme.of(context).colorScheme.tertiary,
          foreground: Theme.of(context).colorScheme.onTertiary,
        ),
      ),
    );
  }
}

class _ControlHandle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color foreground;

  const _ControlHandle({
    required this.icon,
    required this.color,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 13, color: foreground),
      );
}
