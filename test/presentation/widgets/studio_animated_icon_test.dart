import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/studio_animated_icon.dart';
import 'package:nai_huishi/presentation/widgets/studio_entrance.dart';

void main() {
  testWidgets('offscreen and offstage icons stay still during page entry',
      (tester) async {
    final page = AnimationController(
        vsync: tester, value: 1, duration: const Duration(milliseconds: 420));
    addTearDown(page.dispose);
    await tester.pumpWidget(MaterialApp(
        home: StudioEntranceScope(
      animation: page,
      child: const Stack(children: [
        Positioned(top: 10, child: StudioAnimatedIcon(CupertinoIcons.cube_box)),
        Positioned(
            top: 900, child: StudioAnimatedIcon(CupertinoIcons.waveform)),
        Offstage(child: StudioAnimatedIcon(CupertinoIcons.search)),
      ]),
    )));
    page.forward(from: 0);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint, skipOffstage: false))
        .map((w) => w.painter)
        .whereType<StudioIconPainter>()
        .toList();
    expect(
        painters.singleWhere((p) => p.kind == StudioIconKind.box).clock.value,
        lessThan(1));
    for (final kind in [StudioIconKind.waveform, StudioIconKind.search]) {
      expect(painters.singleWhere((p) => p.kind == kind).clock.value, 1);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'visible rows stagger independently, settle, and do not replay on rebuild',
      (tester) async {
    final page = AnimationController(
        vsync: tester, value: 1, duration: const Duration(milliseconds: 420));
    addTearDown(page.dispose);
    Widget host({bool reduce = false, bool active = true}) => MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: TickerMode(
              enabled: active,
              child: StudioEntranceScope(
                animation: page,
                child: const Column(children: [
                  StudioAnimatedIcon(CupertinoIcons.cube_box),
                  SizedBox(height: 80),
                  StudioAnimatedIcon(CupertinoIcons.waveform),
                  SizedBox(height: 80),
                  StudioAnimatedIcon(CupertinoIcons.arrow_down_circle),
                ]),
              )),
        ));
    List<StudioIconPainter> painters() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<StudioIconPainter>()
        .toList();
    await tester.pumpWidget(host());
    page.forward(from: 0);
    await tester.pump();
    await tester.pump();
    expect(painters().map((p) => p.delay), [0, 180, 360]);
    await tester.pump(const Duration(milliseconds: 450));
    expect(page.isCompleted, isTrue);
    expect(painters().every((p) => p.clock.value < 1), isTrue);
    await tester.pumpAndSettle();
    expect(painters().every((p) => p.clock.value == 1), isTrue);
    await tester.pumpWidget(host());
    expect(painters().every((p) => p.clock.value == 1), isTrue);
    page.forward(from: 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(host(reduce: true));
    expect(painters().every((p) => p.clock.value == 1), isTrue);
    await tester.pumpWidget(host(active: false));
    expect(painters().every((p) => p.clock.value == 1), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'every vector animates and returns exactly to rest; box body stays fixed',
      (tester) async {
    Future<List<int>> pixels(StudioIconKind kind, double t) async {
      final recorder = ui.PictureRecorder();
      StudioIconPainter(
              kind: kind, clock: AlwaysStoppedAnimation(t), color: Colors.black)
          .paint(Canvas(recorder), const Size(96, 96));
      final picture = recorder.endRecording();
      final image = await picture.toImage(96, 96);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = data!.buffer.asUint8List().toList();
      image.dispose();
      picture.dispose();
      return result;
    }

    await tester.runAsync(() async {
      for (final kind in StudioIconKind.values) {
        final start = await pixels(kind, 0);
        final moving = await pixels(kind, .16);
        final end = await pixels(kind, 1);
        expect(moving, isNot(orderedEquals(start)),
            reason: '${kind.name} moves');
        expect(end, orderedEquals(start), reason: '${kind.name} settles');
        if (kind == StudioIconKind.box) {
          expect(moving.sublist(60 * 96 * 4),
              orderedEquals(start.sublist(60 * 96 * 4)));
        }
      }
    });
  });
}
