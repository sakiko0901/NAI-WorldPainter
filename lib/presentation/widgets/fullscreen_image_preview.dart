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
      duration: const Duration(milliseconds: 360),
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
      _animateTo(Matrix4.identity());
      _zoomed = false;
    } else {
      final position = details.localPosition;
      final target = Matrix4.identity()
        ..translate(-position.dx * 1.15, -position.dy * 1.15)
        ..scale(2.15);
      _animateTo(target);
      _zoomed = true;
    }
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
              transformationController: _controller,
              minScale: 0.8,
              maxScale: 5,
              onInteractionStart: (_) => _zoomAnimationController.stop(),
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
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
