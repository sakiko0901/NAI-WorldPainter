import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/png_metadata_service.dart';
import 'package:nai_huishi/data/datasources/remote/wd_tagger_api_service.dart';
import 'package:nai_huishi/domain/usecases/analyze_image_tags.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/image_metadata_editor_page.dart';
import 'package:nai_huishi/presentation/pages/image_tag_page.dart';
import 'package:nai_huishi/presentation/viewmodels/image_tag_viewmodel.dart';

void main() {
  late Directory temporaryDirectory;
  late _SaveImageFake saveImage;

  setUp(() {
    temporaryDirectory =
        Directory.systemTemp.createTempSync('metadata_editor_widget_');
    saveImage = _SaveImageFake();
    sl.registerSingleton<SaveImageUseCase>(saveImage);
  });

  tearDown(() async {
    await sl.reset();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'loads the selected PNG, exports edited metadata, preserves source',
      (tester) async {
    final source = _writePng(temporaryDirectory, 'source.png');
    final originalBytes = source.readAsBytesSync();

    await tester.pumpWidget(_page(source.path));
    await _waitForImage(tester);

    final prompt = find.byKey(const ValueKey('metadata-prompt'));
    expect(tester.widget<TextFormField>(prompt).controller!.text,
        'original phrase');
    await tester.enterText(prompt, 'updated phrase');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.byKey(_exportKey));
    await _pumpUntil(
      tester,
      () => saveImage.savedBytes != null && _exportReady(tester),
    );

    final output = Uint8List.fromList(saveImage.savedBytes!);
    final parsed = PngMetadataService.read(output);
    expect(parsed.comment['prompt'], 'updated phrase');
    expect(parsed.text['Description'], 'updated phrase');
    expect(source.readAsBytesSync(), orderedEquals(originalBytes));
    expect(source.existsSync(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('strip mode exports a PNG without prompt metadata',
      (tester) async {
    final source = _writePng(temporaryDirectory, 'strip-source.png');

    await tester.pumpWidget(_page(source.path, strip: true));
    await _waitForImage(tester);

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('metadata-strip')))
          .value,
      isTrue,
    );
    expect(find.byKey(const ValueKey('metadata-prompt')), findsNothing);

    await tester.tap(find.byKey(_exportKey));
    await _pumpUntil(
      tester,
      () => saveImage.savedBytes != null && _exportReady(tester),
    );

    final parsed = PngMetadataService.read(
      Uint8List.fromList(saveImage.savedBytes!),
    );
    expect(parsed.comment.containsKey('prompt'), isFalse);
    expect(parsed.text.containsKey('Description'), isFalse);
    expect(jsonEncode(parsed.comment), isNot(contains('original phrase')));
    expect(jsonEncode(parsed.text), isNot(contains('original phrase')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a useful error when gallery save reports failure',
      (tester) async {
    final source = _writePng(temporaryDirectory, 'failed-save.png');
    saveImage.result = false;

    await tester.pumpWidget(_page(source.path));
    await _waitForImage(tester);
    await tester.tap(find.byKey(_exportKey));
    await _pumpUntil(tester, () {
      return find.byKey(_errorKey).evaluate().isNotEmpty &&
          _exportReady(tester);
    });

    expect(find.textContaining('导出失败'), findsOneWidget);
    expect(find.textContaining('保存到相册失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not offer PNG export for an unsupported JPEG',
      (tester) async {
    final source =
        File('${temporaryDirectory.path}${Platform.pathSeparator}photo.jpg');
    source.writeAsBytesSync(img.encodeJpg(img.Image(width: 1, height: 1)));

    await tester.pumpWidget(_page(source.path));
    await _pumpUntil(tester, () => find.byKey(_errorKey).evaluate().isNotEmpty);

    expect(find.byKey(_exportKey), findsNothing);
    expect(find.textContaining('读取失败'), findsOneWidget);
    expect(saveImage.savedBytes, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image-tag actions pass the current PNG and strip mode',
      (tester) async {
    final source = _writePng(temporaryDirectory, 'tag-entry.png');
    final viewModel = _ImageTagViewModelFake(source.path);
    addTearDown(viewModel.dispose);
    sl.registerSingleton<ImageTagViewModel>(viewModel);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('METADATA_UI_QA_CAPTURE')) {
      await _loadQaFont();
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: _tagScreenshotKey,
        child: MaterialApp(
          theme: buildNaiHuishiTheme(Brightness.dark),
          home: const ImageTagPage(),
        ),
      ),
    );
    await tester.pump();
    if (const bool.fromEnvironment('METADATA_UI_QA_CAPTURE')) {
      await _settleImages(tester);
      await _captureQaScreenshot(
        tester,
        _tagScreenshotKey,
        'image-tag-entry-393.png',
      );
    }

    await tester.tap(find.byKey(const ValueKey('image-tag-edit-metadata')));
    await tester.pump(const Duration(milliseconds: 350));
    await _waitForImage(tester);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('metadata-prompt')),
          )
          .controller!
          .text,
      'original phrase',
    );

    Navigator.of(tester.element(find.byType(ImageMetadataEditorPage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('image-tag-strip-metadata')));
    await tester.pump(const Duration(milliseconds: 350));
    await _waitForImage(tester);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('metadata-strip')),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 320-pixel viewport with the keyboard visible',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final source = _writePng(temporaryDirectory, 'narrow.png');

    await tester.pumpWidget(
      RepaintBoundary(
        key: _qaScreenshotKey,
        child: _page(source.path),
      ),
    );
    await _waitForImage(tester);
    final prompt = find.byKey(const ValueKey('metadata-prompt'));
    await tester.scrollUntilVisible(
      prompt,
      140,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(prompt);
    await tester.enterText(prompt, 'narrow screen phrase');
    await tester.pump();

    expect(tester.getRect(find.byKey(_exportKey)).bottom,
        lessThanOrEqualTo(720 - 280));

    if (const bool.fromEnvironment('METADATA_UI_QA_CAPTURE')) {
      await _captureQaScreenshot(
        tester,
        _qaScreenshotKey,
        'metadata-editor-320-keyboard.png',
      );
    }

    expect(tester.takeException(), isNull);
  });
}

const _exportKey = ValueKey('metadata-export');
const _errorKey = ValueKey('metadata-error');
const _qaScreenshotKey = ValueKey('metadata-editor-qa-screenshot');
const _tagScreenshotKey = ValueKey('image-tag-entry-qa-screenshot');

bool _exportReady(WidgetTester tester) {
  final button = find.byKey(_exportKey);
  return button.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(button).onPressed != null;
}

Future<void> _waitForImage(WidgetTester tester) async {
  await _pumpUntil(tester, () {
    return _exportReady(tester) || find.byKey(_errorKey).evaluate().isNotEmpty;
  });
  final error = find.byKey(_errorKey);
  if (error.evaluate().isNotEmpty) {
    fail('PNG loading failed: ${tester.widget<Text>(error).data}');
  }
}

Widget _page(String imagePath, {bool strip = false}) => MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: ImageMetadataEditorPage(
        initialImagePath: imagePath,
        initialStripMetadata: strip,
      ),
    );

File _writePng(Directory directory, String name) {
  final base = img.Image(width: 1, height: 1);
  final baseBytes = Uint8List.fromList(img.encodePng(base));
  final bytes = PngMetadataService.rewrite(baseBytes, {
    'Comment': jsonEncode({
      'prompt': 'original phrase',
      'uc': 'original negative',
      'steps': 24,
    }),
    'Description': 'original phrase',
    'Software': 'NovelAI',
  });
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  file.writeAsBytesSync(bytes, flush: true);
  return file;
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    if (condition()) return;
  }
  fail('Timed out waiting for the metadata widget operation to complete.');
}

Future<void> _loadQaFont() async {
  final fontPath = Platform.environment['FRONTEND_QA_FONT'];
  if (fontPath == null) return;
  final bytes = File(fontPath).readAsBytesSync();
  for (final family in ['Microsoft YaHei', 'Roboto']) {
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  }
}

Future<void> _settleImages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    if (images.isNotEmpty &&
        images.every((image) {
          final status = tester.binding.imageCache.statusForKey(image.image);
          return !status.pending && (status.live || status.keepAlive);
        })) {
      return;
    }
  }
  fail('The ImageTagPage preview image did not finish rendering.');
}

Future<void> _captureQaScreenshot(
  WidgetTester tester,
  Key boundaryKey,
  String fileName,
) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  final screenshot = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return Uint8List.fromList(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
  final directory = Directory('.tmp/metadata-ui-qa')
    ..createSync(recursive: true);
  File('${directory.path}${Platform.pathSeparator}$fileName')
      .writeAsBytesSync(screenshot!);
}

class _SaveImageFake implements SaveImageUseCase {
  List<int>? savedBytes;
  bool result = true;

  @override
  Future<bool> savePngBytesToGallery(List<int> pngBytes) async {
    savedBytes = List<int>.from(pngBytes);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageTagViewModelFake extends ImageTagViewModel {
  _ImageTagViewModelFake(String imagePath)
      : super(
          useCase: AnalyzeImageTagsUseCase(
            remote: WdTaggerApiService(Dio()),
          ),
        ) {
    this.imagePath = imagePath;
  }

  @override
  Future<void> loadCache() async {}
}
