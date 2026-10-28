import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/inpaint_source_transparency.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/domain/services/inpaint_rasterizer.dart';

void main() {
  test('precise compositing excludes green pixels outside round mask', () {
    const rasterizer = InpaintRasterizer();
    final base = img.Image(width: 64, height: 64, numChannels: 4)
      ..clear(img.ColorRgba8(90, 80, 70, 255));
    final mask = rasterizer.rasterize(
        source: base,
        worldRect: const InpaintViewport(x: 0, y: 0, width: 64, height: 64),
        outputWidth: 64,
        outputHeight: 64,
        preserveRoundBrush: true,
        strokes: [
          InpaintStroke(
              target: InpaintPaintTarget.mask,
              mode: InpaintStrokeMode.paint,
              type: InpaintStrokeType.path,
              size: 24,
              points: const [InpaintPoint(32, 32)])
        ]).mask;
    final generated = img.Image.from(base);
    for (final pixel in mask) {
      generated.setPixelRgba(pixel.x, pixel.y, pixel.r > 0 ? 180 : 0,
          pixel.r > 0 ? 100 : 255, 0, 255);
    }
    final oldLayer = rasterizer.maskGeneratedLayer(
        generated: generated, mask: mask, base: base, outwardFeatherPixels: 8);
    final oldComposite = img.Image.from(base);
    img.compositeImage(oldComposite, oldLayer);
    expect(oldComposite.getPixel(19, 32).g, greaterThan(80),
        reason: 'Outward feather reproduces the unwanted green ring');
    final layer = rasterizer.maskGeneratedLayer(
        generated: generated,
        mask: mask,
        base: base,
        outwardFeatherPixels: 8,
        clipToMask: true);
    final composed = img.Image.from(base);
    img.compositeImage(composed, layer);
    for (final pixel in mask) {
      if (pixel.r == 0) {
        expect(layer.getPixel(pixel.x, pixel.y).a, 0);
        expect(composed.getPixel(pixel.x, pixel.y).g, 80);
      }
    }
    expect(layer.getPixel(32, 32).a, 255);
    expect(layer.getPixel(20, 32).a, inExclusiveRange(0, 255));
    final request = img.decodePng(rasterizer.encodeMask(mask))!;
    expect(request.getPixel(16, 32).r, 255);
    expect(mask.getPixel(16, 32).r, 0);
  });
  const rasterizer = InpaintRasterizer();
  const world = InpaintViewport(x: 0, y: 0, width: 128, height: 128);
  img.Image source() => img.Image(width: 128, height: 128, numChannels: 4)
    ..clear(img.ColorRgba8(20, 40, 60, 255));
  InpaintStroke stroke(double x, double y,
          {bool square = false, bool erase = false, double size = 16}) =>
      InpaintStroke(
        target: InpaintPaintTarget.mask,
        mode: erase ? InpaintStrokeMode.erase : InpaintStrokeMode.paint,
        type: InpaintStrokeType.path,
        size: size,
        square: square,
        points: [InpaintPoint(x, y)],
      );
  img.Image render(List<InpaintStroke> strokes, {int expansion = 8}) =>
      rasterizer
          .rasterize(
            source: source(),
            worldRect: world,
            outputWidth: 128,
            outputHeight: 128,
            strokes: strokes,
            expandPixels: expansion,
            preserveRoundBrush: true,
          )
          .mask;

  test('round coverage and encoded mask match the brush even with expansion',
      () {
    for (final expansion in [0, 8, 32]) {
      final mask = render([stroke(65.5, 65.5)], expansion: expansion);
      final encoded =
          img.decodePng(rasterizer.encodeMask(mask, alignToLatentGrid: false))!;
      expect(encoded.numChannels, 1);
      for (final pixel in encoded) {
        final dx = pixel.x + 0.5 - 65.5;
        final dy = pixel.y + 0.5 - 65.5;
        expect(pixel.r > 0, dx * dx + dy * dy <= 64,
            reason: 'expansion=$expansion at ${pixel.x},${pixel.y}');
        expect(pixel.r, mask.getPixel(pixel.x, pixel.y).r);
      }
    }
  });

  test('mixing square strokes never expands a separate round stroke', () {
    final round = stroke(94, 94);
    final square = stroke(24, 24, square: true);
    final circleOnly = render([round]);
    for (final strokes in [
      [round, square],
      [square, round]
    ]) {
      final mixed = render(strokes);
      expect(
          mixed.getPixel(9, 24).r, 255); // Expanded square remains available.
      for (var y = 70; y < 128; y++) {
        for (var x = 70; x < 128; x++) {
          expect(mixed.getPixel(x, y).r, circleOnly.getPixel(x, y).r);
        }
      }
    }
  });

  test('erasers cut expanded masks in order and round paint can fill the hole',
      () {
    final square = stroke(64, 64, square: true, size: 48);
    final erase = stroke(64, 64, erase: true);
    final erased = render([square, erase]);
    expect(erased.getPixel(64, 64).r, 0);
    expect(erased.getPixel(64, 57).r, 0);
    expect(erased.getPixel(64, 54).r, 255);
    final repainted = render([square, erase, stroke(64, 64, size: 4)]);
    expect(repainted.getPixel(64, 64).r, 255);
    expect(repainted.getPixel(64, 57).r, 0);
  });

  test('preview and generation agree for mixed brushes and scaled frames', () {
    final base = source();
    base.setPixelRgba(10, 10, 0, 0, 0, 0);
    final strokes = [
      stroke(24, 24, square: true),
      stroke(92, 92),
      stroke(24, 24, erase: true, size: 6)
    ];
    for (final rect in [
      world,
      const InpaintViewport(x: -8.5, y: 3.2, width: 140, height: 125)
    ]) {
      final full = rasterizer
          .rasterize(
              source: base,
              worldRect: rect,
              outputWidth: 160,
              outputHeight: 128,
              strokes: strokes,
              expandPixels: 8,
              preserveRoundBrush: true)
          .mask;
      final preview = rasterizer.rasterizeMask(
          source: InpaintSourceTransparency.fromImage(base),
          worldRect: rect,
          outputWidth: 160,
          outputHeight: 128,
          strokes: strokes,
          expandPixels: 8,
          preserveRoundBrush: true);
      expect(preview.getBytes(), orderedEquals(full.getBytes()));
    }
  });
}
