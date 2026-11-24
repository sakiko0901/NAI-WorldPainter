import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displays the current inpaint frame within the full-resolution selection.
class InpaintStreamPreview extends StatefulWidget {
  final Uint8List bytes;
  final Uint8List maskBytes;

  const InpaintStreamPreview({
    super.key,
    required this.bytes,
    required this.maskBytes,
  });

  @override
  State<InpaintStreamPreview> createState() => _InpaintStreamPreviewState();
}

class _InpaintStreamPreviewState extends State<InpaintStreamPreview> {
  ImageInfo? _frame;
  ImageInfo? _mask;
  late ImageStream _frameStream;
  late ImageStream _maskStream;

  late final _frameListener = ImageStreamListener((info, synchronousCall) {
    _frame?.dispose();
    _frame = info;
    if (!synchronousCall) setState(() {});
  }, onError: (_, __) {});

  late final _maskListener = ImageStreamListener((info, synchronousCall) {
    _mask?.dispose();
    _mask = info;
    if (!synchronousCall) setState(() {});
  }, onError: (_, __) {});

  @override
  void initState() {
    super.initState();
    _maskStream = MemoryImage(widget.maskBytes)
        .resolve(ImageConfiguration.empty)
      ..addListener(_maskListener);
    _resolveFrame();
  }

  @override
  void didUpdateWidget(covariant InpaintStreamPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.maskBytes, widget.maskBytes)) {
      _maskStream.removeListener(_maskListener);
      _mask?.dispose();
      _mask = null;
      _maskStream = MemoryImage(widget.maskBytes)
          .resolve(ImageConfiguration.empty)
        ..addListener(_maskListener);
    }
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _frameStream.removeListener(_frameListener);
      // Retain the previous frame until this one has decoded.
      _resolveFrame();
    }
  }

  void _resolveFrame() {
    _frameStream = MemoryImage(widget.bytes).resolve(ImageConfiguration.empty)
      ..addListener(_frameListener);
  }

  @override
  void dispose() {
    _frameStream.removeListener(_frameListener);
    _maskStream.removeListener(_maskListener);
    _frame?.dispose();
    _mask?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _InpaintFramePainter(frame: _frame, mask: _mask),
      );
}

class _InpaintFramePainter extends CustomPainter {
  final ImageInfo? frame;
  final ImageInfo? mask;

  const _InpaintFramePainter({required this.frame, required this.mask});

  // The request mask is an opaque grayscale PNG. Use its red channel as
  // coverage so the surrounding source image stays visible.
  static const _maskCoverage = ColorFilter.matrix([
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final image = frame?.image;
    final selection = mask?.image;
    if (image == null || selection == null || size.isEmpty) return;

    final destination = Offset.zero & size;
    canvas.saveLayer(destination, Paint());
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.drawImageRect(
      selection,
      Rect.fromLTWH(
          0, 0, selection.width.toDouble(), selection.height.toDouble()),
      destination,
      Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = _maskCoverage
        ..blendMode = BlendMode.dstIn,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InpaintFramePainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.mask != mask;
}
