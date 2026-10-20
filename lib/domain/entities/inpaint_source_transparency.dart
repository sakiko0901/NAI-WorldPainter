import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Exact source transparency for mask previews, without retaining decoded RGB.
/// An empty bitset represents a fully opaque source.
class InpaintSourceTransparency {
  final int width;
  final int height;
  final Uint8List _bits;

  InpaintSourceTransparency._(this.width, this.height, this._bits);

  factory InpaintSourceTransparency.fromImage(img.Image source) {
    final bits = Uint8List((source.width * source.height + 7) ~/ 8);
    var hasTransparentPixel = false;
    for (final pixel in source) {
      if (pixel.a == 0) {
        final index = pixel.y * source.width + pixel.x;
        bits[index >> 3] |= 1 << (index & 7);
        hasTransparentPixel = true;
      }
    }
    return InpaintSourceTransparency._(
      source.width,
      source.height,
      hasTransparentPixel ? bits : Uint8List(0),
    );
  }

  int get storageBytes => _bits.length;

  bool isTransparent(int x, int y) {
    if (_bits.isEmpty) return false;
    final index = y * width + x;
    return (_bits[index >> 3] & (1 << (index & 7))) != 0;
  }
}
