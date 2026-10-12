import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_comparison.dart';

late Directory _imageDirectory;
late String _beforePath;
late String _afterPath;
late String _nextBeforePath;
late String _nextAfterPath;

const _comparisonKey = ValueKey('comparison-under-test');
const _dragKey = ValueKey('inpaint-comparison-drag');
const _revealKey = ValueKey('inpaint-comparison-reveal');
const _semanticsLabel = '重绘前后滑动对比';

Future<String> _writeSolidPng(String name, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Offset.zero & const ui.Size(8, 8),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  final file =
      File('${_imageDirectory.path}${Platform.pathSeparator}$name.png');
  await file.writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  image.dispose();
  picture.dispose();
  return file.path;
}

Widget _host({
  required String beforePath,
  required String afterPath,
  required ValueChanged<bool> onGestureActive,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 180,
            child: InpaintComparison(
              key: _comparisonKey,
              beforePath: beforePath,
              afterPath: afterPath,
              onGestureActive: onGestureActive,
            ),
          ),
        ),
      ),
    );

Rect _imageRect(WidgetTester tester, int index) =>
    tester.getRect(find.byType(Image).at(index));

double _revealWidth(WidgetTester tester) {
  final clip = tester.widget<ClipRect>(find.byKey(_revealKey));
  return (clip.clipper! as InpaintRevealClipper)
      .getClip(const Size(320, 180))
      .width;
}

String _semanticsValue(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.label == _semanticsLabel,
  );
  return tester.widget<Semantics>(finder).properties.value!;
}

String _imagePath(WidgetTester tester, int index) {
  final image = tester.widget<Image>(find.byType(Image).at(index));
  return (image.image as FileImage).file.path;
}

void _setTestView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 240);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _dragToEdge(WidgetTester tester, {required bool left}) async {
  final rect = tester.getRect(find.byKey(_dragKey));
  final gesture = await tester.startGesture(rect.center);
  await tester.pump();
  await gesture.moveTo(
    Offset(left ? rect.left - 24 : rect.right + 24, rect.center.dy),
  );
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    _imageDirectory = await Directory.systemTemp.createTemp(
      'inpaint-comparison-test-',
    );
    _beforePath = await _writeSolidPng('before-a', const Color(0xffff0000));
    _afterPath = await _writeSolidPng('after-a', const Color(0xff0000ff));
    _nextBeforePath = await _writeSolidPng(
      'before-b',
      const Color(0xff00ff00),
    );
    _nextAfterPath = await _writeSolidPng(
      'after-b',
      const Color(0xffffff00),
    );
  });

  tearDownAll(() async {
    await _imageDirectory.delete(recursive: true);
  });

  testWidgets(
      'images keep the same bounds and candidate paths update while split stays put',
      (tester) async {
    _setTestView(tester);

    await tester.pumpWidget(
      _host(
        beforePath: _beforePath,
        afterPath: _afterPath,
        onGestureActive: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(2));
    expect(_imagePath(tester, 0), _beforePath);
    expect(_imagePath(tester, 1), _afterPath);
    expect(_imageRect(tester, 0), _imageRect(tester, 1));

    final dragRect = tester.getRect(find.byKey(_dragKey));
    await tester.dragFrom(dragRect.center, const Offset(-73.6, 0));
    await tester.pumpAndSettle();
    expect(_semanticsValue(tester), '重绘后显示 27%');
    final splitBeforeUpdate = _revealWidth(tester);

    await tester.pumpWidget(
      _host(
        beforePath: _nextBeforePath,
        afterPath: _nextAfterPath,
        onGestureActive: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(_imagePath(tester, 0), _nextBeforePath);
    expect(_imagePath(tester, 1), _nextAfterPath);
    expect(_imageRect(tester, 0), _imageRect(tester, 1));
    expect(_semanticsValue(tester), '重绘后显示 27%');
    expect(_revealWidth(tester), closeTo(splitBeforeUpdate, 0.001));
  });

  testWidgets('dragging the reveal can reach both zero and full width', (
    tester,
  ) async {
    _setTestView(tester);

    await tester.pumpWidget(
      _host(
        beforePath: _beforePath,
        afterPath: _afterPath,
        onGestureActive: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    await _dragToEdge(tester, left: true);
    expect(_revealWidth(tester), 0);
    expect(_semanticsValue(tester), '重绘后显示 0%');

    await _dragToEdge(tester, left: false);
    expect(_revealWidth(tester), 320);
    expect(_semanticsValue(tester), '重绘后显示 100%');
  });

  testWidgets('pointer up and cancel both release gesture activity', (
    tester,
  ) async {
    _setTestView(tester);
    final states = <bool>[];
    await tester.pumpWidget(
      _host(
        beforePath: _beforePath,
        afterPath: _afterPath,
        onGestureActive: states.add,
      ),
    );
    await tester.pumpAndSettle();

    var rect = tester.getRect(find.byKey(_dragKey));
    var gesture = await tester.startGesture(rect.center);
    await tester.pump();
    expect(states.last, isTrue);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(states.last, isFalse);

    rect = tester.getRect(find.byKey(_dragKey));
    gesture = await tester.startGesture(rect.center);
    await tester.pump();
    expect(states.last, isTrue);
    await gesture.moveTo(rect.center + const Offset(48, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(states.last, isFalse);
  });

  testWidgets('semantics increase and decrease the reveal fraction', (
    tester,
  ) async {
    _setTestView(tester);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(
          beforePath: _beforePath,
          afterPath: _afterPath,
          onGestureActive: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      final finder = find.semantics.byAction(ui.SemanticsAction.increase);
      var node = finder.evaluate().single;
      var data = node.getSemanticsData();
      expect(data.value, '重绘后显示 50%');
      expect(data.increasedValue, '重绘后显示 60%');
      expect(data.decreasedValue, '重绘后显示 40%');
      expect(data.hasAction(ui.SemanticsAction.increase), isTrue);
      expect(data.hasAction(ui.SemanticsAction.decrease), isTrue);

      tester.semantics.increase(finder);
      await tester.pump();
      expect(_revealWidth(tester), closeTo(192, 0.001));
      node = finder.evaluate().single;
      expect(node.getSemanticsData().value, '重绘后显示 60%');

      tester.semantics.decrease(finder);
      await tester.pump();
      expect(_revealWidth(tester), closeTo(160, 0.001));
      expect(finder.evaluate().single.getSemanticsData().value, '重绘后显示 50%');
    } finally {
      semantics.dispose();
    }
  });
}
