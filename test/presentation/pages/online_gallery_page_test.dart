import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/online_gallery.dart';
import 'package:nai_huishi/domain/repositories/online_gallery_repository.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/online_gallery_page.dart';
import 'package:nai_huishi/presentation/pages/settings_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';

import '../../support/frontend_generation_fake.dart';

void main() {
  late FrontendGenerationFake generation;
  late _GalleryRepositoryFake repository;
  late Directory fixtureDirectory;
  late String fixtureImagePath;

  setUp(() async {
    await sl.reset();
    generation = _GenerationFake();
    sl.registerSingleton<GenerationViewModel>(generation);
    fixtureDirectory = Directory.systemTemp.createTempSync('gallery-widget-');
    fixtureImagePath =
        '${fixtureDirectory.path}${Platform.pathSeparator}art.png';
    File(fixtureImagePath).writeAsBytesSync(_paintedPng());
    repository = _GalleryRepositoryFake(fixtureImagePath);
  });

  tearDown(() async {
    await sl.reset();
    generation.dispose();
    if (!const bool.fromEnvironment('GALLERY_CAPTURE')) {
      fixtureDirectory.deleteSync(recursive: true);
    }
  });

  testWidgets('source picker lists all eight sources and filters are scoped',
      (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(OnlineGalleryScreen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('online-gallery-source-menu')));
    await tester.pumpAndSettle();
    for (final source in OnlineGallerySource.values) {
      expect(
        find.byKey(ValueKey('online-gallery-source-${source.id}')),
        findsOneWidget,
      );
    }
    await tester.tap(find.text('Civitai'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('online-gallery-grid')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-online-gallery-filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('online-gallery-time-filter')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('online-gallery-tags-model-filter')),
        findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('online-gallery-cancel-filters')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'two-column results return from detail with query and scroll intact',
      (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(OnlineGalleryScreen(repository: repository)));
    await tester.pumpAndSettle();

    final firstCard = tester.getRect(
      find.byKey(ValueKey(repository.items[0].key)),
    );
    final secondCard = tester.getRect(
      find.byKey(ValueKey(repository.items[1].key)),
    );
    expect(firstCard.width, closeTo(secondCard.width, 1));
    expect((firstCard.left - secondCard.left).abs(), greaterThan(100));
    final query = find.byKey(const ValueKey('online-gallery-query'));
    await tester.enterText(query, 'purple_hair');
    await tester.tap(find.byKey(const ValueKey('online-gallery-submit')));
    await tester.pumpAndSettle();

    final listScrollable = find
        .descendant(
          of: find
              .byKey(const PageStorageKey<String>('online-gallery-results')),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(listScrollable).position.jumpTo(165);
    await tester.pumpAndSettle();
    final targetItem = repository.items[8];
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(targetItem.key)),
      180,
      scrollable: listScrollable,
    );
    await tester.pumpAndSettle();
    final beforeDetailOffset =
        tester.state<ScrollableState>(listScrollable).position.pixels;
    await tester.tap(find.byKey(ValueKey(targetItem.key)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('online-gallery-detail')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('online-gallery-detail')), findsNothing);
    final restoredOffset =
        tester.state<ScrollableState>(listScrollable).position.pixels;
    expect(restoredOffset, beforeDetailOffset);
    tester.state<ScrollableState>(listScrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.ensureVisible(query);
    expect(tester.widget<TextField>(query).controller!.text, 'purple_hair');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'prompt reuse only updates selected drafts and keeps missing negative',
      (tester) async {
    _setViewport(tester);
    final navigatorKey = GlobalKey<NavigatorState>();
    var returnedToCreate = false;
    generation
      ..prompt = 'existing positive'
      ..negativePrompt = 'existing negative'
      ..selectedModel = 'nai-diffusion-5-full';
    (generation as _GenerationFake).seed = 2468;
    repository.items = [
      repository.items.first.copyWith(
        prompt: 'gallery positive',
        negativePrompt: '',
      ),
    ];

    await tester.pumpWidget(_host(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => OnlineGalleryScreen(
                    repository: repository,
                    onNavigateToGenerate: () {
                      returnedToCreate = true;
                      navigatorKey.currentState!
                          .popUntil((route) => route.isFirst);
                    },
                  ),
                ),
              ),
              child: const Text('Open gallery'),
            ),
          ),
        ),
      ),
      navigatorKey: navigatorKey,
    ));
    await tester.tap(find.text('Open gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(repository.items.first.key)));
    await tester.pumpAndSettle();
    final detailScrollable = find
        .descendant(
          of: find.byKey(
            const PageStorageKey<String>('online-gallery-detail-scroll'),
          ),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('角色提示词'),
      180,
      scrollable: detailScrollable,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('copy-gallery-character-0')),
      findsOneWidget,
    );
    expect(
      repository.requestedPreviewUrls,
      contains('synthetic://gallery-0/cover-full'),
    );
    await tester
        .tap(find.byKey(const ValueKey('online-gallery-apply-to-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('online-gallery-prompt-preview-sheet')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prompt-apply-append')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-online-gallery-prompt-apply')),
    );
    await tester.pumpAndSettle();

    expect(generation.prompt, 'existing positive, gallery positive');
    expect(generation.negativePrompt, 'existing negative');
    expect(generation.selectedModel, 'nai-diffusion-5-full');
    expect((generation as _GenerationFake).seed, 2468);
    expect((generation as _GenerationFake).generateCalls, 0);
    expect(returnedToCreate, isTrue);
    expect(find.byKey(const ValueKey('online-gallery-screen')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorite detail keeps the saved safety mode', (tester) async {
    _setViewport(tester);
    final favorite = OnlineGalleryItem(
      source: OnlineGallerySource.civitai,
      id: 'favorite-civitai',
      title: 'Favorite with mature rating',
      media: repository.items.first.media,
      metadata: const {'safeOnly': false},
    );
    repository.favoriteItems = [favorite];
    await tester.pumpWidget(_host(OnlineGalleryScreen(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('online-gallery-favorites')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(favorite.key)));
    await tester.pumpAndSettle();

    expect(repository.lastDetailSafeOnly, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download menu offers current/all and caps one batch at 100',
      (tester) async {
    _setViewport(tester);
    repository.items = [
      repository.items.first.copyWith(
        media: List.generate(
          101,
          (index) => OnlineGalleryMedia(
            id: 'large-$index',
            previewUrl: 'synthetic://large/$index',
            displayUrl: 'synthetic://large/full/$index',
            width: 640,
            height: 960,
          ),
        ),
        metadata: const {'safeOnly': true},
      ),
    ];
    await tester.pumpWidget(_host(OnlineGalleryScreen(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(repository.items.first.key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('下载当前图'), findsOneWidget);
    expect(find.text('下载前 100 张（共 101 张）'), findsOneWidget);
    await tester.tap(find.text('下载前 100 张（共 101 张）'));
    await tester.pumpAndSettle();

    expect(repository.lastDownloadedCount, 100);
    expect(repository.downloadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AITag summary cards still request a repository preview',
      (tester) async {
    _setViewport(tester);
    repository.items = [
      const OnlineGalleryItem(
        source: OnlineGallerySource.aitag,
        id: 'summary-without-media',
        title: 'AITag result',
      ),
    ];
    await tester.pumpWidget(_host(OnlineGalleryScreen(repository: repository)));
    await tester.pumpAndSettle();

    expect(repository.previewCalls, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail retry replaces a failed future and loads content',
      (tester) async {
    _setViewport(tester);
    repository.detailFailures = 1;
    await tester.pumpWidget(_host(OnlineGalleryScreen(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(repository.items.first.key)));
    await tester.pumpAndSettle();

    expect(find.text('详情加载失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('Twilight study 0'), findsOneWidget);
    expect(find.text('作品信息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter settings clear preview cache and report retained data',
      (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(OnlineGalleryScreen(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-online-gallery-filters')));
    await tester.pumpAndSettle();

    final sheetScrollable = find
        .descendant(
          of: find.byKey(const ValueKey('online-gallery-filter-sheet')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('clear-online-gallery-cache')),
      180,
      scrollable: sheetScrollable,
    );
    await tester.tap(find.byKey(const ValueKey('clear-online-gallery-cache')));
    await tester.pumpAndSettle();

    expect(repository.clearCacheCalls, 1);
    expect(
      find.text('预览缓存已清理，收藏和已保存原图会保留'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact keyboard layout scrolls safely at 320 by 640',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 268);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      _host(OnlineGalleryScreen(repository: repository), textScale: 1.3),
    );
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('online-gallery-query'));
    await tester.tap(editor);
    await tester.enterText(editor, 'portrait');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('open-online-gallery-filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('online-gallery-filter-sheet')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings exposes gallery before Danbooru and opens it',
      (tester) async {
    _setViewport(tester);
    _registerSettingsFakes(repository);
    await tester.pumpWidget(_host(SettingsPage(
      appearanceMode: AppearanceMode.dark,
      onAppearanceChanged: (_) {},
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Danbooru 查词'));

    final galleryRect = tester.getRect(find.text('在线图库'));
    final danbooruRect = tester.getRect(find.text('Danbooru 查词'));
    expect(galleryRect.top, lessThan(danbooruRect.top));

    await tester.tap(find.text('在线图库'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('online-gallery-screen')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture synthetic gallery screens for visual review',
      (tester) async {
    if (!const bool.fromEnvironment('GALLERY_CAPTURE')) return;
    await _loadCaptureFonts();
    _setViewport(tester);
    _registerSettingsFakes(repository);
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(_host(
      SettingsPage(
        appearanceMode: AppearanceMode.dark,
        onAppearanceChanged: (_) {},
      ),
      boundaryKey: boundaryKey,
      galleryCaptureFonts: true,
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('在线图库'));
    final settingsScroll =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    settingsScroll.position.jumpTo(
      (settingsScroll.position.pixels - 56).clamp(0.0, double.infinity),
    );
    await tester.pumpAndSettle();
    await _capture(tester, boundaryKey, 'tools-entry', fixtureImagePath);

    await tester.tap(find.text('在线图库'));
    await tester.pumpAndSettle();
    await _capture(tester, boundaryKey, 'gallery-list', fixtureImagePath);

    await tester.tap(find.byKey(const ValueKey('open-online-gallery-filters')));
    await tester.pumpAndSettle();
    await _capture(tester, boundaryKey, 'gallery-filters', fixtureImagePath);
    await tester
        .tap(find.byKey(const ValueKey('online-gallery-cancel-filters')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey(repository.items.first.key)));
    await tester.pumpAndSettle();
    await _capture(tester, boundaryKey, 'gallery-detail', fixtureImagePath);
    await tester
        .tap(find.byKey(const ValueKey('online-gallery-apply-to-create')));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      boundaryKey,
      'gallery-prompt-preview',
      fixtureImagePath,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _host(
  Widget home, {
  GlobalKey<NavigatorState>? navigatorKey,
  GlobalKey? boundaryKey,
  double textScale = 1,
  bool galleryCaptureFonts = false,
}) {
  var theme = buildNaiHuishiTheme(Brightness.dark);
  if (galleryCaptureFonts) {
    const fallback = ['Microsoft YaHei', 'Roboto'];
    const family = 'GalleryQA';
    final textTheme = theme.textTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
    );
    final primaryTextTheme = theme.primaryTextTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
    );
    final appBarTitle = (theme.appBarTheme.titleTextStyle ??
            theme.textTheme.titleLarge ??
            const TextStyle())
        .copyWith(fontFamily: family, fontFamilyFallback: fallback);
    final chipLabel = (theme.chipTheme.labelStyle ??
            theme.textTheme.labelLarge ??
            const TextStyle())
        .copyWith(
      fontFamily: family,
      fontFamilyFallback: fallback,
    );
    theme = theme.copyWith(
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      appBarTheme: theme.appBarTheme.copyWith(titleTextStyle: appBarTitle),
      chipTheme: theme.chipTheme.copyWith(labelStyle: chipLabel),
    );
  }
  return MaterialApp(
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: home,
    builder: (context, child) => RepaintBoundary(
      key: boundaryKey,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
}

Future<void> _loadCaptureFonts() async {
  const flutterRoot = r'E:\NAI-WorldPainter\.tools\flutter';
  const pubCache = r'E:\NAI-WorldPainter\.tools\pub-cache';
  final zhFontPath = Platform.environment['GALLERY_QA_FONT'] ??
      r'C:\Windows\Fonts\NotoSansSC-VF.ttf';
  final fontFiles = <String, String>{
    'GalleryQA': zhFontPath,
    'Microsoft YaHei': zhFontPath,
    'Noto Sans CJK SC': zhFontPath,
    'Roboto':
        '$flutterRoot/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
    'MaterialIcons':
        '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    'packages/cupertino_icons/CupertinoIcons':
        '$pubCache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
  };
  for (final entry in fontFiles.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) {
      throw FileSystemException(
          'Required capture font was not found', file.path);
    }
    final bytes = ByteData.sublistView(file.readAsBytesSync());
    await (FontLoader(entry.key)..addFont(Future.value(bytes))).load();
  }
}

void _setViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
  String fixturePath,
) async {
  await _waitForFileImageWidgets(tester, fixturePath);
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.tmp/gallery-captures/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _waitForFileImageWidgets(
  WidgetTester tester,
  String fixturePath,
) async {
  final imageElements = find.byType(Image).evaluate().toList(growable: false);
  if (imageElements.isEmpty) return;
  final element = imageElements.first;
  final imageWidget = element.widget as Image;
  final stream = imageWidget.image.resolve(
    createLocalImageConfiguration(element),
  );
  final completer = Completer<void>();
  Object? imageError;
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      info.dispose();
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
    onError: (Object error, StackTrace? stackTrace) {
      imageError = error;
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
  );
  stream.addListener(listener);
  for (var attempt = 0; attempt < 12; attempt++) {
    if (completer.isCompleted && imageError != null) {
      throw StateError('Fixture FileImage failed to decode: $imageError');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    final decodedImages = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((image) => image.image != null)
        .toList(growable: false);
    if (decodedImages.isNotEmpty) {
      stream.removeListener(listener);
      await tester.pumpAndSettle();
      expect(decodedImages.first.image!.width, greaterThan(0));
      expect(decodedImages.first.image!.height, greaterThan(0));
      return;
    }
  }
  stream.removeListener(listener);
  throw TimeoutException(
    'No decoded RawImage from fixture $fixturePath; '
    'streamDone=${completer.isCompleted}, error=$imageError, '
    'imageWidgets=${find.byType(Image).evaluate().length}, '
    'rawImages=${find.byType(RawImage).evaluate().length}',
  );
}

Uint8List _paintedPng() {
  const width = 320;
  const height = 480;
  final scanlines = Uint8List(height * (1 + width * 3));
  for (var y = 0; y < height; y++) {
    final row = y * (1 + width * 3);
    scanlines[row] = 0;
    for (var x = 0; x < width; x++) {
      final offset = row + 1 + x * 3;
      final glow = math.max(
          0,
          1 -
              math.sqrt(
                math.pow((x - 212) / 145, 2) + math.pow((y - 152) / 196, 2),
              ));
      scanlines[offset] =
          (34 + y * 0.16 + glow * 95).round().clamp(0, 255).toInt();
      scanlines[offset + 1] =
          (30 + y * 0.12 + glow * 53).round().clamp(0, 255).toInt();
      scanlines[offset + 2] =
          (70 + y * 0.19 + glow * 84).round().clamp(0, 255).toInt();
    }
  }
  final signature = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  final header = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8)
    ..setUint8(9, 2)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  return Uint8List.fromList([
    ...signature,
    ..._pngChunk('IHDR', header.buffer.asUint8List()),
    ..._pngChunk('IDAT', Uint8List.fromList(ZLibEncoder().convert(scanlines))),
    ..._pngChunk('IEND', Uint8List(0)),
  ]);
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  final checksumInput = Uint8List.fromList([...typeBytes, ...data]);
  final crc = _crc32(checksumInput);
  final length = ByteData(4)..setUint32(0, data.length, Endian.big);
  final checksum = ByteData(4)..setUint32(0, crc, Endian.big);
  return Uint8List.fromList([
    ...length.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...checksum.buffer.asUint8List(),
  ]);
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

class _GalleryRepositoryFake implements OnlineGalleryRepository {
  _GalleryRepositoryFake(this.imagePath) {
    items = List.generate(24, (index) => _item('gallery-$index'));
  }

  final String imagePath;
  List<OnlineGalleryItem> items = [];
  final Set<String> _favoriteKeys = {};
  final List<OnlineGalleryQuery> queries = [];
  bool openedSource = false;
  int detailFailures = 0;
  int downloadCalls = 0;
  int clearCacheCalls = 0;
  int? lastDownloadedCount;
  int previewCalls = 0;
  bool? lastDetailSafeOnly;
  List<OnlineGalleryItem> favoriteItems = [];
  final List<String> requestedPreviewUrls = [];

  OnlineGalleryItem _item(String id) => OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: id,
        title: 'Twilight study ${id.split('-').last}',
        author: 'synthetic_artist',
        description: 'Synthetic fixture for Flutter widget review.',
        sourceUrl: 'https://tags.gallery/art/$id',
        prompt: 'twilight, soft light, detailed background',
        negativePrompt: 'low quality, blurry',
        rating: 'safe',
        createdAt: '2026-10-22',
        score: 83,
        favoriteCount: 15,
        viewCount: 210,
        mediaCount: 2,
        media: [
          OnlineGalleryMedia(
            id: '$id-cover',
            previewUrl: 'synthetic://$id/cover',
            displayUrl: 'synthetic://$id/cover-full',
            width: 640,
            height: 960,
          ),
          OnlineGalleryMedia(
            id: '$id-2',
            previewUrl: 'synthetic://$id/2',
            width: 960,
            height: 640,
          ),
        ],
        categoryPath: const ['artist', 'soft lighting'],
        tags: const {
          'artists': ['synthetic_artist'],
          'general': ['twilight', 'soft lighting', 'cityscape'],
        },
        metadata: const {
          'baseModel': 'NAI Diffusion V5',
          'sampler': 'k_euler_ancestral',
          'steps': 28,
          'cfgScale': 5.5,
          'seed': 120045,
          'characterPrompts': [
            {'label': '角色1', 'prompt': 'silver hair, blue eyes'},
          ],
        },
      );

  @override
  Future<OnlineGalleryPage> search(OnlineGalleryQuery query) async {
    queries.add(query);
    final filtered = items
        .map((item) => item.copyWith(
              // Keep the selected source visible in each source-switch fixture.
              sourceUrl: '${query.source.siteUrl}/posts/${item.id}',
            ))
        .toList(growable: false);
    return OnlineGalleryPage(
      items: filtered,
      hasMore: false,
      title: query.source.label,
      collections: const [
        OnlineGalleryCollection(
          id: 'soft',
          title: 'Soft light',
          count: 28,
          type: 'artist',
        ),
      ],
      categories: const [
        OnlineGalleryCategory(
            path: ['artist', 'background'], title: 'Background'),
        OnlineGalleryCategory(path: ['artist', 'lighting'], title: 'Lighting'),
      ],
    );
  }

  @override
  Future<OnlineGalleryItem> detail(
    OnlineGalleryItem item, {
    bool safeOnly = true,
  }) async {
    lastDetailSafeOnly = safeOnly;
    if (detailFailures > 0) {
      detailFailures--;
      throw StateError('Synthetic detail failure');
    }
    return item;
  }

  @override
  Future<List<OnlineGalleryItem>> favorites() async => [
        ...favoriteItems,
        ...items.where((item) => _favoriteKeys.contains(item.key)),
      ];

  @override
  Future<void> setFavorite(OnlineGalleryItem item, bool value) async {
    if (value) {
      _favoriteKeys.add(item.key);
    } else {
      _favoriteKeys.remove(item.key);
    }
  }

  @override
  Future<OnlineGalleryQuery?> loadLastQuery() async => null;

  @override
  Future<void> saveQuery(OnlineGalleryQuery query) async {}

  @override
  Future<String?> previewPath(
    OnlineGalleryItem item,
    OnlineGalleryMedia media,
  ) async {
    previewCalls++;
    requestedPreviewUrls.add(media.previewUrl);
    return imagePath;
  }

  @override
  Future<OnlineGalleryDownloadResult> download(
    OnlineGalleryItem item,
    List<OnlineGalleryMedia> media,
  ) async {
    downloadCalls++;
    lastDownloadedCount = media.length;
    return OnlineGalleryDownloadResult(saved: media.length);
  }

  @override
  Future<void> saveStyle(OnlineGalleryItem item) async {}

  @override
  Future<void> openSource(OnlineGalleryItem item) async {
    openedSource = true;
  }

  @override
  Future<void> clearCache() async {
    clearCacheCalls++;
  }

  @override
  Future<bool> hasGelbooruCredentials() async => true;

  @override
  Future<void> setGelbooruCredentials(
    OnlineGalleryCredentials credentials,
  ) async {}
}

class _GenerationFake extends FrontendGenerationFake {
  int? _seed;
  int generateCalls = 0;

  @override
  int? get seed => _seed;

  @override
  set seed(int? value) => _seed = value;

  @override
  Future<void> generate() async {
    generateCalls++;
  }
}

void _registerSettingsFakes(OnlineGalleryRepository repository) {
  sl.registerSingleton<SettingsViewModel>(
    SettingsViewModel(ManageSettingsUseCase(_SettingsRepositoryFake())),
  );
  sl.registerSingleton<OfficialNovelAiTokenStore>(_NoTokenStore());
  sl.registerSingleton<OnlineGalleryRepository>(repository);
}

class _SettingsRepositoryFake extends Fake implements SettingsRepository {
  @override
  Future<String?> getApiKey() async => null;
  @override
  Future<String> getBaseUrl() async => '';
  @override
  Future<String?> getDefaultModel() async => null;
  @override
  Future<String> getDefaultResolution() async => '832x1216';
  @override
  Future<String> getDefaultSampler() async => 'k_euler';
  @override
  Future<double> getDefaultScale() async => 5;
  @override
  Future<double> getDefaultCfgRescale() async => 0;
  @override
  Future<String> getDefaultNoiseSchedule() async => 'native';
  @override
  Future<String> getDefaultStyleWords() async => '';
  @override
  Future<String> getImageProviderNovelAiBaseUrl() async => '';
  @override
  Future<String?> getImageProviderNovelAiApiKey() async => null;
  @override
  Future<String> getImageProviderNovelAiModel() async => '';
  @override
  Future<String> getImageProviderGptBaseUrl() async => '';
  @override
  Future<String?> getImageProviderGptApiKey() async => null;
  @override
  Future<String> getImageProviderGptModel() async => '';
  @override
  Future<String> getImageProviderNanoBaseUrl() async => '';
  @override
  Future<String?> getImageProviderNanoApiKey() async => null;
  @override
  Future<String> getImageProviderNanoModel() async => '';
  @override
  Future<List<ApiEndpoint>> getEndpoints(ImageProviderType provider) async =>
      [];
  @override
  Future<String?> getActiveEndpointId(ImageProviderType provider) async => null;
  @override
  Future<String?> getActiveModel(ImageProviderType provider) async => null;
}

class _NoTokenStore extends OfficialNovelAiTokenStore {
  @override
  Future<String?> read() async => null;
}
