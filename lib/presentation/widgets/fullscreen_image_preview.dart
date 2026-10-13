import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showFullscreenImagePreview(
  BuildContext context, {
  String? imagePath,
  String? imageUrl,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _FullscreenImagePreview(
            imagePath: imagePath, imageUrl: imageUrl);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _FullscreenImagePreview extends StatefulWidget {
  final String? imagePath;
  final String? imageUrl;

  const _FullscreenImagePreview({this.imagePath, this.imageUrl});

  @override
  State<_FullscreenImagePreview> createState() =>
      _FullscreenImagePreviewState();
}

class _FullscreenImagePreviewState extends State<_FullscreenImagePreview>
    with SingleTickerProviderStateMixin {
  late final TransformationController _controller;
  late final AnimationController _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        final value = _zoomAnimation?.value;
        if (value != null) _controller.value = value;
      });
  }

  @override
  void dispose() {
    _zoomAnimationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _zoomAnimationController.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
      return;
    }
    _zoomAnimation = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _zoomAnimationController,
      curve: Curves.easeOutCubic,
    ));
    _zoomAnimationController.forward(from: 0);
  }

  void _toggleZoom(TapDownDetails details) {
    if (_zoomed) {
      _resetZoom();
    } else {
      final position = details.localPosition;
      final target = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.15, -position.dy * 1.15, 0, 1)
        ..scaleByDouble(2.15, 2.15, 1, 1);
      _animateTo(target);
      setState(() => _zoomed = true);
    }
  }

  void _resetZoom() {
    _animateTo(Matrix4.identity());
    if (_zoomed) setState(() => _zoomed = false);
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    final nextZoomed = _controller.value.getMaxScaleOnAxis() > 1.02;
    if (nextZoomed == _zoomed) return;
    setState(() => _zoomed = nextZoomed);
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (widget.imagePath != null && File(widget.imagePath!).existsSync()) {
      child = Image.file(File(widget.imagePath!), fit: BoxFit.contain);
    } else if (widget.imageUrl != null) {
      child = Image.network(widget.imageUrl!, fit: BoxFit.contain);
    } else {
      child = Icon(Icons.broken_image,
          size: 72, color: Theme.of(context).colorScheme.onSurfaceVariant);
    }

    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            onDoubleTapDown: _toggleZoom,
            child: InteractiveViewer(
              key: const ValueKey('fullscreen-image-viewer'),
              transformationController: _controller,
              minScale: 1,
              maxScale: 5,
              onInteractionStart: (_) => _zoomAnimationController.stop(),
              onInteractionUpdate: _onInteractionUpdate,
              child: SizedBox.expand(
                child: Center(child: child),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _zoomed ? '重置缩放' : '适应窗口',
                      onPressed: _resetZoom,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        maximumSize: const Size(40, 40),
                        padding: EdgeInsets.zero,
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.28),
                      ),
                      icon: const Icon(Icons.fit_screen_outlined, size: 20),
                    ),
                    const SizedBox(width: 5),
                    IconButton(
                      tooltip: '关闭预览',
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        maximumSize: const Size(40, 40),
                        padding: EdgeInsets.zero,
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.28),
                      ),
                      icon: const Icon(
                        CupertinoIcons.xmark,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
