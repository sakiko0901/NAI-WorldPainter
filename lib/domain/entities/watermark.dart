import 'dart:math' as math;
import 'dart:ui';

class WatermarkAsset {
  final String id;
  final String name;
  final String path;
  final int width;
  final int height;
  final DateTime createdAt;

  const WatermarkAsset({
    required this.id,
    required this.name,
    required this.path,
    required this.width,
    required this.height,
    required this.createdAt,
  });
}

/// Positions and widths use the original image, independently of screen size.
class WatermarkLayer {
  final String id;
  final String assetId;
  final Offset center;
  final double widthFraction;
  final double rotation;
  final double opacity;

  const WatermarkLayer({
    required this.id,
    required this.assetId,
    this.center = const Offset(.5, .5),
    this.widthFraction = .3,
    this.rotation = 0,
    this.opacity = 1,
  });

  WatermarkLayer copyWith({
    String? id,
    Offset? center,
    double? widthFraction,
    double? rotation,
    double? opacity,
  }) =>
      WatermarkLayer(
        id: id ?? this.id,
        assetId: assetId,
        center: center ?? this.center,
        widthFraction: widthFraction ?? this.widthFraction,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  bool contains(Offset point, Size canvas, Size image) {
    final delta =
        point - Offset(center.dx * canvas.width, center.dy * canvas.height);
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final local = Offset(
        delta.dx * cos + delta.dy * sin, -delta.dx * sin + delta.dy * cos);
    final width = canvas.width * widthFraction;
    return local.dx.abs() <= width / 2 &&
        local.dy.abs() <= width * image.height / image.width / 2;
  }
}
