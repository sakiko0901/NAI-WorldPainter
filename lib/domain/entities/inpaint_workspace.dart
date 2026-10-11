import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';

/// 局部重绘工作区内的绘制目标。
enum InpaintPaintTarget { mask, image }

enum InpaintStrokeMode { paint, erase }

enum InpaintStrokeType { path, rectangle }

enum InpaintCandidateStatus { pending, kept, primary }

/// Square brush grid size in source-image pixels.
const double inpaintBrushGridCellSize = 8;

/// Returns the grid cells covered by a square brush stroke, joined with a
/// Bresenham line so quick pointer movements do not leave gaps.
Set<(int, int)> inpaintSquareBrushCells(InpaintStroke stroke) {
  if (!stroke.square || stroke.points.isEmpty) return {};
  final diameter =
      math.max(1, (stroke.size / inpaintBrushGridCellSize).round());
  final half = diameter ~/ 2;
  final shift = diameter.isEven ? 0.5 : 0.0;
  final points = stroke.points
      .map((point) => (
            (point.x / inpaintBrushGridCellSize + shift).floor(),
            (point.y / inpaintBrushGridCellSize + shift).floor(),
          ))
      .toList(growable: false);
  final cells = <(int, int)>{};

  for (var index = 0; index < points.length; index++) {
    final from = index == 0 ? points[index] : points[index - 1];
    final to = points[index];
    var x = from.$1;
    var y = from.$2;
    final dx = (to.$1 - x).abs();
    final dy = (to.$2 - y).abs();
    final sx = x < to.$1 ? 1 : -1;
    final sy = y < to.$2 ? 1 : -1;
    var error = dx - dy;
    while (true) {
      for (var oy = -half; oy < diameter - half; oy++) {
        for (var ox = -half; ox < diameter - half; ox++) {
          cells.add((x + ox, y + oy));
        }
      }
      if (x == to.$1 && y == to.$2) break;
      final twice = error * 2;
      if (twice > -dy) {
        error -= dy;
        x += sx;
      }
      if (twice < dx) {
        error += dx;
        y += sy;
      }
    }
  }
  return cells;
}

class InpaintPoint extends Equatable {
  final double x;
  final double y;

  const InpaintPoint(this.x, this.y);

  Offset get offset => Offset(x, y);

  @override
  List<Object?> get props => [x, y];
}

class InpaintStroke extends Equatable {
  final InpaintPaintTarget target;
  final InpaintStrokeMode mode;
  final InpaintStrokeType type;
  final double size;
  final int color;
  final double opacity;
  final List<InpaintPoint> points;
  final InpaintPoint? start;
  final Rect? rectangle;

  /// 笔刷形状：true = 方形，false = 圆形（默认）。
  final bool square;

  const InpaintStroke({
    required this.target,
    required this.mode,
    required this.type,
    required this.size,
    this.color = 0xffff4d4f,
    this.opacity = 0.35,
    this.points = const [],
    this.start,
    this.rectangle,
    this.square = false,
  });

  @override
  List<Object?> get props => [
        target,
        mode,
        type,
        size,
        color,
        opacity,
        points,
        start,
        rectangle,
        square,
      ];
}

class InpaintTransform extends Equatable {
  final double scale;
  final double offsetX;
  final double offsetY;

  const InpaintTransform({
    this.scale = 1,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  InpaintTransform copyWith(
          {double? scale, double? offsetX, double? offsetY}) =>
      InpaintTransform(
        scale: scale ?? this.scale,
        offsetX: offsetX ?? this.offsetX,
        offsetY: offsetY ?? this.offsetY,
      );

  InpaintPoint screenToWorld(InpaintPoint point) => InpaintPoint(
        (point.x - offsetX) / scale,
        (point.y - offsetY) / scale,
      );

  @override
  List<Object?> get props => [scale, offsetX, offsetY];
}

class InpaintViewport extends Equatable {
  final double x;
  final double y;
  final double width;
  final double height;

  const InpaintViewport({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  InpaintViewport move(double dx, double dy) => InpaintViewport(
        x: x + dx,
        y: y + dy,
        width: width,
        height: height,
      );

  InpaintViewport resize(double factor, double aspectRatio) {
    final nextWidth = (width * factor).clamp(96.0, 3200.0).toDouble();
    final nextHeight = nextWidth / aspectRatio;
    return InpaintViewport(
      x: x + (width - nextWidth) / 2,
      y: y + (height - nextHeight) / 2,
      width: nextWidth,
      height: nextHeight,
    );
  }

  @override
  List<Object?> get props => [x, y, width, height];
}

/// 屏幕坐标系下的选择框（宽高比固定为输出分辨率）。
class InpaintBox extends Equatable {
  final double x;
  final double y;
  final double width;
  final double height;

  const InpaintBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  InpaintBox translate(double dx, double dy) => InpaintBox(
        x: x + dx,
        y: y + dy,
        width: width,
        height: height,
      );

  @override
  List<Object?> get props => [x, y, width, height];
}

class InpaintFeather extends Equatable {
  final int top;
  final int right;
  final int bottom;
  final int left;

  const InpaintFeather(
      {this.top = 0, this.right = 0, this.bottom = 0, this.left = 0});

  bool get isZero => top == 0 && right == 0 && bottom == 0 && left == 0;

  @override
  List<Object?> get props => [top, right, bottom, left];
}

class InpaintCandidate extends Equatable {
  final String id;
  final String imagePath;

  /// 重绘前的基础图（截取自选框范围，输出分辨率大小）。
  final String baseImagePath;

  /// 本轮工作区会话的完整底图，用于应用候选时合并。
  final String workspaceImagePath;
  final String maskImagePath;

  /// 生成时选框对应的图像世界坐标范围。
  final InpaintViewport worldRect;
  final InpaintCandidateStatus status;
  final int? seed;

  const InpaintCandidate({
    required this.id,
    required this.imagePath,
    required this.baseImagePath,
    required this.workspaceImagePath,
    required this.maskImagePath,
    required this.worldRect,
    this.status = InpaintCandidateStatus.pending,
    this.seed,
  });

  InpaintCandidate copyWith({
    String? baseImagePath,
    String? workspaceImagePath,
    String? maskImagePath,
    InpaintCandidateStatus? status,
  }) =>
      InpaintCandidate(
        id: id,
        imagePath: imagePath,
        baseImagePath: baseImagePath ?? this.baseImagePath,
        workspaceImagePath: workspaceImagePath ?? this.workspaceImagePath,
        maskImagePath: maskImagePath ?? this.maskImagePath,
        worldRect: worldRect,
        status: status ?? this.status,
        seed: seed,
      );

  @override
  List<Object?> get props => [
        id,
        imagePath,
        baseImagePath,
        workspaceImagePath,
        maskImagePath,
        worldRect,
        status,
        seed,
      ];
}

/// A generated inpaint patch displayed above the immutable source image.
class InpaintResultLayer extends Equatable {
  final String id;
  final String name;
  final String imagePath;
  final int width;
  final int height;
  final InpaintViewport worldRect;
  final bool visible;

  const InpaintResultLayer({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.width,
    required this.height,
    required this.worldRect,
    this.visible = true,
  });

  InpaintResultLayer copyWith({bool? visible}) => InpaintResultLayer(
        id: id,
        name: name,
        imagePath: imagePath,
        width: width,
        height: height,
        worldRect: worldRect,
        visible: visible ?? this.visible,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        imagePath,
        width,
        height,
        worldRect,
        visible,
      ];
}

class InpaintWorkspaceResult extends Equatable {
  final String? sourceImagePath;
  final String? maskImagePath;
  final String prompt;
  final String negativePrompt;
  final double inpaintStrength;
  final bool disabledOriginalImage;
  final bool colorCorrect;

  const InpaintWorkspaceResult({
    required this.sourceImagePath,
    required this.maskImagePath,
    required this.prompt,
    required this.negativePrompt,
    required this.inpaintStrength,
    required this.disabledOriginalImage,
    required this.colorCorrect,
  });

  @override
  List<Object?> get props => [
        sourceImagePath,
        maskImagePath,
        prompt,
        negativePrompt,
        inpaintStrength,
        disabledOriginalImage,
        colorCorrect,
      ];
}

class InpaintWorkspaceSnapshot extends Equatable {
  final InpaintTransform transform;
  final InpaintViewport viewport;
  final List<InpaintStroke> strokes;

  const InpaintWorkspaceSnapshot({
    required this.transform,
    required this.viewport,
    required this.strokes,
  });

  @override
  List<Object?> get props => [transform, viewport, strokes];
}
