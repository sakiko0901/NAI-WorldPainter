import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_input_bar.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_scroll_surface.dart';

void main() {
  testWidgets('glass filters the actual backdrop and leaves the center sharp',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();

    Future<Uint8List> render(
        {required bool blur, bool contrast = false}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark, frostedGlassEnabled: blur),
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(320, 600), highContrast: contrast),
          child: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ChatScrollSurface(
                header: const SizedBox(height: 62),
                footer: ChatInputBar(
                  isSending: false,
                  onSend: (_,
                      {imageBase64,
                      imageBase64s = const [],
                      textAttachment}) {},
                ),
                bodyBuilder: (_) => const CustomPaint(painter: _Stripes()),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return (await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return Uint8List.fromList(data!.buffer.asUint8List());
      }))!;
    }

    double rangeAt(Uint8List pixels, int y) {
      final values = [
        for (var x = 120; x < 200; x++) pixels[(y * 320 + x) * 4],
      ]..sort();
      return (values.last - values.first).toDouble();
    }

    final sharp = await render(blur: false);
    final blurred = await render(blur: true);
    // A tinted rectangle (or a filter isolated inside ShaderMask's empty
    // saveLayer) cannot pass this: the stripe detail must actually be blurred.
    expect(rangeAt(blurred, 48), lessThan(rangeAt(sharp, 48) * .25));
    expect(rangeAt(blurred, 90), greaterThan(rangeAt(blurred, 48)));
    expect(rangeAt(blurred, 250), rangeAt(sharp, 250));
    // Measure contrast independently of the tinted scrim. Every scanline must
    // blend into the next: a set of clipped sigma bands produces sudden jumps.
    final recovery = [
      for (var row = 38; row <= 110; row++)
        rangeAt(blurred, row) / rangeAt(sharp, row),
    ];
    for (var i = 1; i < recovery.length; i++) {
      expect((recovery[i] - recovery[i - 1]).abs(), lessThan(.045),
          reason: 'blur transition must stay continuous at row ${i + 38}');
    }

    final composer =
        tester.getRect(find.byKey(const ValueKey('chat-composer-surface')));
    final y = composer.top.round() + 9;
    expect(rangeAt(blurred, y), lessThanOrEqualTo(2));
    // The disabled fallback is opaque. Enabled glass must transmit the
    // averaged bright backdrop without transmitting its stripe edges.
    expect(blurred[(y * 320 + 160) * 4],
        greaterThan(sharp[(y * 320 + 160) * 4] + 12));
    await render(blur: true, contrast: true);
    expect(
        tester
            .widgetList<BackdropFilter>(find.byType(BackdropFilter))
            .where((filter) => filter.enabled),
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header spreads edges progressively without dimming the source',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Scaffold(
          body: RepaintBoundary(
        key: key,
        child: ChatScrollSurface(
          header: const SizedBox(height: 62),
          footer: const SizedBox(height: 64),
          bodyBuilder: (_) => const CustomPaint(painter: _HalfPlane()),
        ),
      )),
    ));
    await tester.pumpAndSettle();
    final pixels = (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return Uint8List.fromList(bytes!.buffer.asUint8List());
    }))!;
    double value(int x, int y) => pixels[(y * 320 + x) * 4].toDouble();
    double normalized(int x, int y) =>
        (value(x, y) - value(50, y)) / (value(270, y) - value(50, y));
    int spread(int y) {
      final left = Iterable<int>.generate(200, (i) => i + 60)
          .firstWhere((x) => normalized(x, y) >= .1);
      final right = Iterable<int>.generate(200, (i) => i + 60)
          .firstWhere((x) => normalized(x, y) >= .9);
      return right - left;
    }

    final widths = [
      for (final y in [10, 30, 50, 70, 90, 110]) spread(y)
    ];
    expect(widths.first, greaterThan(18));
    expect(widths[1], greaterThan(widths[2]));
    expect(widths[2], greaterThan(widths[3]));
    expect(widths[3], greaterThan(widths[4]));
    expect(widths.last, 0);
    for (final y in [10, 30, 50]) {
      // A single strong blur crossfaded with the sharp source leaves a steep
      // central edge. That fails this test even if overall contrast is lower.
      expect(normalized(160, y) - normalized(159, y), lessThan(.25));
      // Preserve the light in the backdrop; a dark scrim is not a blur.
      expect(value(270, y), greaterThan(220));
    }
    expect(tester.takeException(), isNull);
  });
}

class _HalfPlane extends CustomPainter {
  const _HalfPlane();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    canvas.drawRect(
        Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height),
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_HalfPlane oldDelegate) => false;
}

class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var x = 0.0; x < size.width; x += 4) {
      paint.color = (x ~/ 4).isEven ? Colors.white : Colors.black;
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}
