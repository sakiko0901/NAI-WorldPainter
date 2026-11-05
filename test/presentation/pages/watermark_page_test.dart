import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/data/datasources/local/watermark_library_store.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/watermark_page.dart';
import 'package:nai_huishi/presentation/widgets/watermark_canvas.dart';

void main() {
  late Directory temporary;
  late WatermarkLibraryStore store;
  late _PickerFake picker;
  Uint8List? saved;
  var saveSucceeds = true;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('watermark-page-test-');
    store = WatermarkLibraryStore(
        directory: Directory('${temporary.path}/library'));
    final base = img.Image(width: 240, height: 160, numChannels: 4);
    img.fill(base, color: img.ColorRgba8(255, 255, 255, 255));
    final watermark = img.Image(width: 100, height: 40, numChannels: 4);
    img.fillRect(watermark,
        x1: 10, y1: 10, x2: 90, y2: 30, color: img.ColorRgba8(255, 0, 0, 255));
    final baseFile = File('${temporary.path}/base.png')
      ..writeAsBytesSync(img.encodePng(base));
    final markFile = File('${temporary.path}/signature.png')
      ..writeAsBytesSync(img.encodePng(watermark));
    picker = _PickerFake(baseFile.path, markFile.path);
    saved = null;
    saveSucceeds = true;
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    temporary.deleteSync(recursive: true);
  });

  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (done()) return;
    }
    fail('Watermark operation did not complete');
  }

  Future<void> openPage(WidgetTester tester,
      {Size size = const Size(393, 852),
      Brightness brightness = Brightness.dark}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(brightness),
      home: WatermarkPage(
          library: store,
          picker: picker,
          saveToGallery: (bytes) async {
            if (saveSucceeds) saved = bytes;
            return saveSucceeds;
          }),
    ));
    await settleUntil(
        tester,
        () =>
            tester
                .widget<TextButton>(
                    find.byKey(const ValueKey('watermark-import')))
                .onPressed !=
            null);
  }

  Future<void> importBaseAndMark(WidgetTester tester) async {
    await tester.tap(find.text('导入底图'));
    await settleUntil(
        tester, () => find.byType(WatermarkCanvas).evaluate().isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('watermark-import')));
    await settleUntil(tester, () {
      final canvas =
          tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas));
      return canvas.layers.length == 1 && canvas.enabled;
    });
    await tester.pumpAndSettle();
  }

  testWidgets('whole canvas controls selected mark and tools can collapse',
      (tester) async {
    await openPage(tester);
    await importBaseAndMark(tester);
    final finder = find.byType(WatermarkCanvas);
    final frame = tester.getRect(finder);
    final blank = frame.topLeft + const Offset(25, 25);
    await tester.tapAt(blank);
    await tester.pump();
    expect(tester.widget<WatermarkCanvas>(finder).selectedId, isNotNull);
    await tester.dragFrom(blank, const Offset(40, 25));
    await tester.pumpAndSettle();
    var layer = tester.widget<WatermarkCanvas>(finder).layers.single;
    expect(layer.center.dx, greaterThan(.5));
    expect(layer.center.dy, greaterThan(.5));

    // Transform a corner with one finger, preserving the watermark center.
    final imageHeight = frame.width * 160 / 240;
    final center = Offset(frame.left + layer.center.dx * frame.width,
        frame.center.dy - imageHeight / 2 + layer.center.dy * imageHeight);
    final corner = center +
        Offset(frame.width * layer.widthFraction / 2,
            frame.width * layer.widthFraction * .4 / 2);
    final oldCenter = layer.center;
    final oldWidth = layer.widthFraction;
    await tester.dragFrom(corner, const Offset(30, 35));
    await tester.pumpAndSettle();
    layer = tester.widget<WatermarkCanvas>(finder).layers.single;
    expect(layer.center, oldCenter);
    expect(layer.widthFraction, greaterThan(oldWidth));
    expect(layer.rotation.abs(), greaterThan(.1));

    final widthBeforePinch = layer.widthFraction;
    final left =
        await tester.startGesture(blank + const Offset(45, 0), pointer: 1);
    final right =
        await tester.startGesture(blank + const Offset(105, 0), pointer: 2);
    await tester.pump();
    await left.moveBy(const Offset(-20, 0));
    await right.moveBy(const Offset(20, 15));
    await tester.pump();
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(tester.widget<WatermarkCanvas>(finder).layers.single.widthFraction,
        greaterThan(widthBeforePinch));

    await tester.tap(find.byKey(const ValueKey('watermark-toggle-tools')));
    await tester.pumpAndSettle();
    expect(tester.getSize(finder).height, greaterThan(frame.height));
    expect(find.byKey(const ValueKey('watermark-properties')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'imports, transforms and exports a watermark while keeping the workspace visible',
      (tester) async {
    await openPage(tester);
    await importBaseAndMark(tester);
    var canvas = tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas));
    expect(canvas.layers, hasLength(1));
    final frame = find.byKey(const ValueKey('watermark-workspace'));
    final before = tester.getRect(frame);
    final gestures = find.byKey(const ValueKey('watermark-canvas-gestures'));
    final center = tester.getCenter(gestures);
    final left =
        await tester.startGesture(center - const Offset(15, 0), pointer: 1);
    final right =
        await tester.startGesture(center + const Offset(15, 0), pointer: 2);
    await tester.pump();
    await left.moveTo(center - const Offset(30, 15));
    await right.moveTo(center + const Offset(30, 15));
    await tester.pump();
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    canvas = tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas));
    expect(canvas.layers.single.widthFraction, greaterThan(.3));
    expect(canvas.layers.single.rotation.abs(), greaterThan(.1));
    await tester.dragFrom(tester.getCenter(gestures), const Offset(45, 20));
    await tester.pumpAndSettle();
    canvas = tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas));
    expect(canvas.layers.single.center.dx, greaterThan(.5));
    final size = find.byKey(const ValueKey('watermark-size'));
    await tester.ensureVisible(size);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(size) + const Offset(10, 0));
    await tester.pumpAndSettle();
    final angle = find.byKey(const ValueKey('watermark-rotation'));
    await tester.ensureVisible(angle);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(angle) + const Offset(30, 0));
    await tester.pumpAndSettle();
    canvas = tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas));
    expect(canvas.layers.single.rotation.abs(), greaterThan(.1));
    expect(canvas.layers.single.widthFraction, isNot(.3));
    expect(tester.getRect(frame), before);
    await tester.tap(find.byKey(const ValueKey('watermark-export')));
    await settleUntil(tester, () => saved != null);
    final output = img.decodePng(saved!)!;
    expect(output.width, 240);
    expect(output.height, 160);
    expect(await tester.runAsync(store.load), hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple imports persist and can be reused as separate layers',
      (tester) async {
    picker.multiple = true;
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('watermark-import')));
    await settleUntil(tester, () => find.text('水印库 · 2').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await openPage(tester);
    expect(find.text('水印库 · 2'), findsOneWidget);
    await tester.tap(find.text('导入底图'));
    await settleUntil(
        tester, () => find.byType(WatermarkCanvas).evaluate().isNotEmpty);
    final assets = (await tester.runAsync(store.load))!;
    for (final asset in assets) {
      final tile = find.byKey(ValueKey('watermark-asset-${asset.id}'));
      await tester.scrollUntilVisible(tile, 100,
          scrollable: find
              .descendant(
                  of: find.byKey(const ValueKey('watermark-properties')),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await settleUntil(
          tester,
          () => tester
              .widget<WatermarkCanvas>(find.byType(WatermarkCanvas))
              .enabled);
    }
    expect(tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas)).layers,
        hasLength(2));
    await tester.drag(find.byKey(const ValueKey('watermark-properties')),
        const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('图层操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制图层'));
    await tester.pumpAndSettle();
    expect(tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas)).layers,
        hasLength(3));
    await tester.tap(find.byTooltip('图层操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除图层'));
    await tester.pumpAndSettle();
    expect(tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas)).layers,
        hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'save failure keeps draft available and can be retried on a narrow screen',
      (tester) async {
    await openPage(tester,
        size: const Size(320, 720), brightness: Brightness.light);
    await importBaseAndMark(tester);
    saveSucceeds = false;
    await tester.tap(find.byKey(const ValueKey('watermark-export')));
    await settleUntil(
        tester,
        () => find
            .byKey(const ValueKey('watermark-error'))
            .evaluate()
            .isNotEmpty);
    expect(tester.widget<WatermarkCanvas>(find.byType(WatermarkCanvas)).layers,
        hasLength(1));
    saveSucceeds = true;
    await tester.tap(find.byKey(const ValueKey('watermark-export')));
    await settleUntil(tester, () => saved != null);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _PickerFake extends ImagePicker {
  final String base;
  final String mark;
  bool multiple = false;
  _PickerFake(this.base, this.mark);

  @override
  Future<XFile?> pickImage(
          {required ImageSource source,
          double? maxWidth,
          double? maxHeight,
          int? imageQuality,
          CameraDevice preferredCameraDevice = CameraDevice.rear,
          bool requestFullMetadata = true}) async =>
      XFile(base);

  @override
  Future<List<XFile>> pickMultiImage(
          {double? maxWidth,
          double? maxHeight,
          int? imageQuality,
          int? limit,
          bool requestFullMetadata = true}) async =>
      [XFile(mark), if (multiple) XFile(mark)];
}
