import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Img2ImgCropResult {
  final int x;
  final int y;
  final int width;
  final int height;
  final int targetWidth;
  final int targetHeight;

  const Img2ImgCropResult({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.targetWidth,
    required this.targetHeight,
  });
}

Rect largestCropRectForRatio(Rect bounds, double ratio, {Offset? center}) {
  var width = bounds.width;
  var height = width / ratio;
  if (height > bounds.height) {
    height = bounds.height;
    width = height * ratio;
  }
  final wantedCenter = center ?? bounds.center;
  final halfWidth = width / 2;
  final halfHeight = height / 2;
  final centerX = wantedCenter.dx.clamp(
    bounds.left + halfWidth,
    bounds.right - halfWidth,
  );
  final centerY = wantedCenter.dy.clamp(
    bounds.top + halfHeight,
    bounds.bottom - halfHeight,
  );
  return Rect.fromCenter(
    center: Offset(centerX, centerY),
    width: width,
    height: height,
  );
}

enum _CropHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class Img2ImgCropDialog extends StatefulWidget {
  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final int initialTargetIndex;
  final (int, int)? initialTarget;

  const Img2ImgCropDialog({
    super.key,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    this.initialTargetIndex = 1,
    this.initialTarget,
  });

  @override
  State<Img2ImgCropDialog> createState() => _Img2ImgCropDialogState();
}

class _Img2ImgCropDialogState extends State<Img2ImgCropDialog> {
  final _targets = <(int, int)>[
    (832, 1216),
    (1024, 1024),
    (1216, 832),
  ];
  static const _accent = Color(0xFFFFC400);

  late int _targetIndex;
  Size _stageSize = Size.zero;
  Rect _cropRect = Rect.zero;
  double _imageScale = 1;
  Offset _imageOffset = Offset.zero;

  double _startImageScale = 1;
  Offset _startImageOffset = Offset.zero;
  Offset _startFocalPoint = Offset.zero;
  Rect _startCropRect = Rect.zero;
  Offset _resizeDelta = Offset.zero;
  bool _moveCrop = false;

  (int, int) get _target => _targets[_targetIndex];
  double get _targetRatio => _target.$1 / _target.$2;

  @override
  void initState() {
    super.initState();
    _targetIndex = widget.initialTargetIndex.clamp(0, _targets.length - 1);
    final initial = widget.initialTarget;
    if (initial != null && initial.$1 > 0 && initial.$2 > 0) {
      if (!_targets.contains(initial)) _targets.add(initial);
      _targetIndex = _targets.indexOf(initial);
    }
  }

  double get _baseScale {
    if (_stageSize == Size.zero) return 1;
    return math.min(
      _stageSize.width / widget.imageWidth,
      _stageSize.height / widget.imageHeight,
    );
  }

  double get _totalImageScale => _baseScale * _imageScale;

  Rect get _imageRect {
    final width = widget.imageWidth * _totalImageScale;
    final height = widget.imageHeight * _totalImageScale;
    return Rect.fromCenter(
      center: _stageSize.center(Offset.zero) + _imageOffset,
      width: width,
      height: height,
    );
  }

  void _initializeStage(Size size) {
    if (size == Size.zero) return;
    final changed = _stageSize != size;
    _stageSize = size;
    if (changed || _cropRect == Rect.zero) {
      _imageScale = 1;
      _imageOffset = Offset.zero;
      _cropRect = largestCropRectForRatio(
          _imageRect.intersect(Offset.zero & _stageSize), _targetRatio);
    }
  }

  void _reset() {
    setState(() {
      _imageScale = 1;
      _imageOffset = Offset.zero;
      _cropRect = largestCropRectForRatio(
          _imageRect.intersect(Offset.zero & _stageSize), _targetRatio);
    });
  }

  Offset _clampImageOffset(Offset value, double scale) {
    final total = _baseScale * scale;
    final width = widget.imageWidth * total;
    final height = widget.imageHeight * total;
    final center = _stageSize.center(Offset.zero);
    final minX = _cropRect.right - center.dx - width / 2;
    final maxX = _cropRect.left - center.dx + width / 2;
    final minY = _cropRect.bottom - center.dy - height / 2;
    final maxY = _cropRect.top - center.dy + height / 2;
    return Offset(
      value.dx.clamp(math.min(minX, maxX), math.max(minX, maxX)),
      value.dy.clamp(math.min(minY, maxY), math.max(minY, maxY)),
    );
  }

  Rect _translateCrop(Rect source, Offset delta) {
    final bounds = _imageRect.intersect(Offset.zero & _stageSize);
    var moved = source.shift(delta);
    if (moved.left < bounds.left) {
      moved = moved.shift(Offset(bounds.left - moved.left, 0));
    }
    if (moved.right > bounds.right) {
      moved = moved.shift(Offset(bounds.right - moved.right, 0));
    }
    if (moved.top < bounds.top) {
      moved = moved.shift(Offset(0, bounds.top - moved.top));
    }
    if (moved.bottom > bounds.bottom) {
      moved = moved.shift(Offset(0, bounds.bottom - moved.bottom));
    }
    return moved;
  }

  void _resizeCrop(_CropHandle handle, Offset delta) {
    const minShortSide = 72.0;
    final bounds = _imageRect.intersect(Offset.zero & _stageSize);
    final start = _startCropRect;
    final ratio = _targetRatio;
    late double proposedWidth;

    switch (handle) {
      case _CropHandle.topLeft:
      case _CropHandle.bottomLeft:
      case _CropHandle.left:
        proposedWidth = start.width - delta.dx;
      case _CropHandle.topRight:
      case _CropHandle.bottomRight:
      case _CropHandle.right:
        proposedWidth = start.width + delta.dx;
      case _CropHandle.top:
        proposedWidth = (start.height - delta.dy) * ratio;
      case _CropHandle.bottom:
        proposedWidth = (start.height + delta.dy) * ratio;
    }

    final minWidth = ratio >= 1 ? minShortSide * ratio : minShortSide;
    final maxWidth = math.min(bounds.width, bounds.height * ratio);
    final width =
        proposedWidth.clamp(minWidth, math.max(minWidth, maxWidth)).toDouble();
    final height = width / ratio;

    Rect next;
    switch (handle) {
      case _CropHandle.topLeft:
        next = Rect.fromLTRB(
          start.right - width,
          start.bottom - height,
          start.right,
          start.bottom,
        );
      case _CropHandle.topRight:
        next = Rect.fromLTRB(
          start.left,
          start.bottom - height,
          start.left + width,
          start.bottom,
        );
      case _CropHandle.bottomLeft:
        next = Rect.fromLTRB(
          start.right - width,
          start.top,
          start.right,
          start.top + height,
        );
      case _CropHandle.bottomRight:
        next = Rect.fromLTRB(
          start.left,
          start.top,
          start.left + width,
          start.top + height,
        );
      case _CropHandle.top:
        next = Rect.fromCenter(
          center: Offset(start.center.dx, start.bottom - height / 2),
          width: width,
          height: height,
        );
      case _CropHandle.bottom:
        next = Rect.fromCenter(
          center: Offset(start.center.dx, start.top + height / 2),
          width: width,
          height: height,
        );
      case _CropHandle.left:
        next = Rect.fromCenter(
          center: Offset(start.right - width / 2, start.center.dy),
          width: width,
          height: height,
        );
      case _CropHandle.right:
        next = Rect.fromCenter(
          center: Offset(start.left + width / 2, start.center.dy),
          width: width,
          height: height,
        );
    }
    setState(() => _cropRect = _translateCrop(next, Offset.zero));
  }

  Img2ImgCropResult _result() {
    final total = _totalImageScale;
    final imageRect = _imageRect;
    final target = _target;
    final divisor = _greatestCommonDivisor(target.$1, target.$2);
    final ratioWidth = target.$1 ~/ divisor;
    final ratioHeight = target.$2 ~/ divisor;
    final availableWidth = _cropRect.width / total;
    final availableHeight = _cropRect.height / total;
    final units = math.max(
      1,
      math
          .min(
            availableWidth / ratioWidth,
            availableHeight / ratioHeight,
          )
          .floor(),
    );
    final width = math.min(widget.imageWidth, units * ratioWidth);
    final height = math.min(widget.imageHeight, units * ratioHeight);
    final centerX = (_cropRect.center.dx - imageRect.left) / total;
    final centerY = (_cropRect.center.dy - imageRect.top) / total;
    final x = (centerX - width / 2).round().clamp(0, widget.imageWidth - width);
    final y =
        (centerY - height / 2).round().clamp(0, widget.imageHeight - height);
    return Img2ImgCropResult(
      x: x,
      y: y,
      width: width,
      height: height,
      targetWidth: target.$1,
      targetHeight: target.$2,
    );
  }

  int _greatestCommonDivisor(int a, int b) {
    while (b != 0) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    return a.abs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(CupertinoIcons.xmark, size: 28),
                  ),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择图生图区域',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '拖动裁剪框或图片，双指缩放',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _result()),
                    child: const Text(
                      '完成',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.black,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    _initializeStage(size);
                    final imageRect = _imageRect;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (details) {
                        _startImageScale = _imageScale;
                        _startImageOffset = _imageOffset;
                        _startFocalPoint = details.localFocalPoint;
                        _startCropRect = _cropRect;
                        _moveCrop = details.pointerCount == 1 &&
                            _cropRect.contains(details.localFocalPoint);
                      },
                      onScaleUpdate: (details) {
                        final movement =
                            details.localFocalPoint - _startFocalPoint;
                        setState(() {
                          if (details.pointerCount >= 2) {
                            final nextScale = (_startImageScale * details.scale)
                                .clamp(1.0, 8.0);
                            _imageScale = nextScale;
                            _imageOffset = _clampImageOffset(
                              _startImageOffset + movement,
                              nextScale,
                            );
                          } else if (_moveCrop) {
                            _cropRect =
                                _translateCrop(_startCropRect, movement);
                          } else {
                            _imageOffset = _clampImageOffset(
                              _startImageOffset + movement,
                              _imageScale,
                            );
                          }
                        });
                      },
                      child: Stack(
                        children: [
                          Positioned.fromRect(
                            rect: imageRect,
                            child: Image.file(
                              File(widget.imagePath),
                              fit: BoxFit.fill,
                            ),
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              size: size,
                              painter: _CropShadePainter(_cropRect),
                            ),
                          ),
                          Positioned.fromRect(
                            rect: _cropRect,
                            child: const IgnorePointer(
                              child: CustomPaint(
                                painter: _CropFramePainter(_accent),
                              ),
                            ),
                          ),
                          ..._buildHandles(),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final entry in _targets.asMap().entries)
                        ChoiceChip(
                          label: Text(switch (entry.key) {
                            0 => '纵向',
                            1 => '方形',
                            2 => '横向',
                            _ => '${entry.value.$1} × ${entry.value.$2}',
                          }),
                          selected: _targetIndex == entry.key,
                          onSelected: (_) => setState(() {
                            final center = _cropRect.center;
                            _targetIndex = entry.key;
                            _cropRect = largestCropRectForRatio(
                                _imageRect.intersect(Offset.zero & _stageSize),
                                _targetRatio,
                                center: center);
                          }),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: '重置',
                    onPressed: _reset,
                    icon: const Icon(
                      CupertinoIcons.arrow_counterclockwise,
                      color: _accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildHandles() {
    final handles = <(_CropHandle, Offset)>[
      (_CropHandle.topLeft, _cropRect.topLeft),
      (_CropHandle.top, Offset(_cropRect.center.dx, _cropRect.top)),
      (_CropHandle.topRight, _cropRect.topRight),
      (_CropHandle.right, Offset(_cropRect.right, _cropRect.center.dy)),
      (_CropHandle.bottomRight, _cropRect.bottomRight),
      (_CropHandle.bottom, Offset(_cropRect.center.dx, _cropRect.bottom)),
      (_CropHandle.bottomLeft, _cropRect.bottomLeft),
      (_CropHandle.left, Offset(_cropRect.left, _cropRect.center.dy)),
    ];
    return handles.map((entry) {
      final handle = entry.$1;
      final point = entry.$2;
      return Positioned(
        left: point.dx - 22,
        top: point.dy - 22,
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) {
            _startCropRect = _cropRect;
            _resizeDelta = Offset.zero;
          },
          onPanUpdate: (details) {
            _resizeDelta += details.delta;
            _resizeCrop(handle, _resizeDelta);
          },
          child: const SizedBox.expand(),
        ),
      );
    }).toList();
  }
}

class _CropShadePainter extends CustomPainter {
  final Rect cropRect;

  const _CropShadePainter(this.cropRect);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(cropRect);
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );
  }

  @override
  bool shouldRepaint(covariant _CropShadePainter oldDelegate) =>
      oldDelegate.cropRect != cropRect;
}

class _CropFramePainter extends CustomPainter {
  final Color color;

  const _CropFramePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, border);

    final accent = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;
    const length = 28.0;
    final width = size.width;
    final height = size.height;
    canvas.drawLine(Offset.zero, const Offset(length, 0), accent);
    canvas.drawLine(Offset.zero, const Offset(0, length), accent);
    canvas.drawLine(Offset(width, 0), Offset(width - length, 0), accent);
    canvas.drawLine(Offset(width, 0), Offset(width, length), accent);
    canvas.drawLine(Offset(0, height), Offset(length, height), accent);
    canvas.drawLine(Offset(0, height), Offset(0, height - length), accent);
    canvas.drawLine(
      Offset(width, height),
      Offset(width - length, height),
      accent,
    );
    canvas.drawLine(
      Offset(width, height),
      Offset(width, height - length),
      accent,
    );
    canvas.drawLine(
      Offset(width / 2 - 16, 0),
      Offset(width / 2 + 16, 0),
      accent,
    );
    canvas.drawLine(
      Offset(width / 2 - 16, height),
      Offset(width / 2 + 16, height),
      accent,
    );
    canvas.drawLine(
      Offset(0, height / 2 - 16),
      Offset(0, height / 2 + 16),
      accent,
    );
    canvas.drawLine(
      Offset(width, height / 2 - 16),
      Offset(width, height / 2 + 16),
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant _CropFramePainter oldDelegate) =>
      oldDelegate.color != color;
}
