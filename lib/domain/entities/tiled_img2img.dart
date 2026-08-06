enum Img2ImgMode {
  normal,
  tiled,
}

class TiledImg2ImgConfig {
  static const int tileSize = 640;
  static const int stride = 320;
  static const int requestSize = 1024;
  static const int maxTiles = 16;
  static const int maxCanvasDimension = 4096;
  static const int maxCanvasPixels = 16 * 1024 * 1024;
  static const double outputScale = 1.6;
}

class Img2ImgTile {
  final int index;
  final int row;
  final int column;
  final int cropX;
  final int cropY;
  final int cropWidth;
  final int cropHeight;
  final int requestWidth;
  final int requestHeight;

  const Img2ImgTile({
    required this.index,
    required this.row,
    required this.column,
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
    required this.requestWidth,
    required this.requestHeight,
  });
}

class TiledImg2ImgProgress {
  final int completed;
  final int total;

  const TiledImg2ImgProgress(this.completed, this.total);
}
