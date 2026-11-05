import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/image_tag_workspace.dart';

void main() {
  late Directory directory;
  var picks = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('image-tag-workspace-');
    picks = 0;
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    directory.deleteSync(recursive: true);
  });

  Future<void> openWorkspace(
    WidgetTester tester, {
    String? path,
    bool blur = true,
    bool busy = false,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(brightness, frostedGlassEnabled: blur),
      home: Scaffold(
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ImageTagWorkspace(
                imagePath: path,
                busy: busy,
                onPickImage: () => picks++,
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> settleImages(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      if (images.isNotEmpty && images.every((image) => image.image != null)) {
        return;
      }
    }
    fail('Workspace image did not load');
  }

  testWidgets('empty workspace is larger and opens the image picker',
      (tester) async {
    await openWorkspace(tester);
    final frame = find.byKey(const ValueKey('image-tag-workspace'));
    final size = tester.getSize(frame);
    expect(size.width, 377);
    expect(size.height, greaterThan(852 * .58));
    await tester.tap(find.text('点击选择图片'));
    expect(picks, 1);
    expect(tester.takeException(), isNull);
  });

  for (final dimensions in [
    const Size(240, 360),
    const Size(360, 180),
    const Size(120, 600)
  ]) {
    testWidgets('keeps complete $dimensions image inside one shared edge',
        (tester) async {
      final file = File('${directory.path}/preview.png')
        ..writeAsBytesSync(img.encodePng(img.Image(
          width: dimensions.width.toInt(),
          height: dimensions.height.toInt(),
        )));
      await openWorkspace(tester, path: file.path);
      await settleImages(tester);
      final foreground = find.byKey(ValueKey('image-tag-preview-${file.path}'));
      final frame = find.byKey(const ValueKey('image-tag-workspace'));
      expect(tester.widget<Image>(foreground).fit, BoxFit.contain);
      expect(tester.getSize(foreground).width, tester.getSize(frame).width);
      expect(tester.getSize(frame).height, lessThanOrEqualTo(852 * .78));
      expect(find.ancestor(of: foreground, matching: find.byType(ClipRRect)),
          findsOneWidget);
      expect(find.byType(ImageFiltered), findsOneWidget);
      await tester.tap(foreground);
      expect(picks, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'blur setting disables ambient image and busy state blocks replacement',
      (tester) async {
    final file = File('${directory.path}/preview.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 120, height: 180)));
    await openWorkspace(tester,
        path: file.path, blur: false, busy: true, brightness: Brightness.light);
    await settleImages(tester);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image-tag-workspace')));
    expect(picks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing image offers replacement without a broken layout',
      (tester) async {
    await openWorkspace(tester, path: '${directory.path}/missing.png');
    for (var i = 0;
        i < 60 && find.text('无法读取图片，点击重新选择').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.tap(find.text('无法读取图片，点击重新选择'));
    expect(picks, 1);
    expect(tester.takeException(), isNull);
  });
}
