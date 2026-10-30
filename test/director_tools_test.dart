import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/director_tool.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/director_tools_page.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/viewmodels/director_tools_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_comparison.dart';

import 'support/frontend_generation_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late _Settings settings;
  late _Api api;
  late DirectorToolsViewModel vm;
  final input = File('assets/style_presets/style_001.jpg').absolute.path;
  const provider = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    if (!const bool.fromEnvironment('DIRECTOR_CAPTURE')) return;
    final font = File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync();
    for (final family in ['Microsoft YaHei', 'Roboto']) {
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(font))))
          .load();
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font
          in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('director-tools-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, (_) async => folder.path);
    settings = _Settings();
    api = _Api(await File(input).readAsBytes());
    vm = DirectorToolsViewModel(api, OfficialNovelAiApiService(),
        OfficialNovelAiTokenStore(), settings, _Save());
    sl.registerFactory<DirectorToolsViewModel>(() => vm);
  });
  tearDown(() async {
    await sl.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, null);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    for (var attempt = 0;; attempt++) {
      try {
        await folder.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  test('channel changes use the generation model without changing that draft',
      () async {
    addTearDown(vm.dispose);
    await vm.load();
    expect(vm.selectedModel, settings.model);
    await vm.selectChannel(DirectorChannel.ikun);
    expect(vm.selectedModel, settings.model);
    vm.selectInput(input);
    // The generation model may have changed after opening the tool.
    settings.model = 'nai-diffusion-5-full';
    expect(await vm.process(), isTrue);
    expect(api.requests.single, ('ikun', input, 'nai-diffusion-5-full'));
    expect(vm.inputPath, input);
    expect(vm.outputPath, isNotNull);
    expect(File(vm.outputPath!).existsSync(), isTrue);
    expect(settings.modelWrites, 0);
    await vm.selectChannel(DirectorChannel.gateway7877);
    expect(await vm.process(), isTrue);
    expect(api.requests.last, ('7877', input, 'nai-diffusion-5-full'));
  });

  test(
      'does not substitute the first channel model when generation model is absent',
      () async {
    addTearDown(vm.dispose);
    settings.model = null;
    await vm.load();
    vm.selectInput(input);
    expect(await vm.process(), isFalse);
    expect(api.requests, isEmpty);
    expect(vm.errorMessage, contains('生成页'));
  });

  test('processing blocks duplicate work and input changes', () async {
    addTearDown(vm.dispose);
    await vm.load();
    vm.selectInput(input);
    api.completion = Completer<Uint8List>();
    final first = vm.process();
    await Future<void>.delayed(Duration.zero);
    expect(vm.isProcessing, isTrue);
    vm.selectInput('another-image.png');
    vm.selectTool(DirectorToolType.emotion);
    await vm.selectChannel(DirectorChannel.ikun);
    expect(vm.inputPath, input);
    expect(vm.selectedTool, DirectorToolType.declutter);
    expect(vm.selectedChannel, DirectorChannel.gateway7877);
    expect(await vm.process(), isFalse);
    api.completion!.complete(api.bytes);
    expect(await first, isTrue);
    expect(api.requests, hasLength(1));
  });

  for (final brightness in Brightness.values) {
    testWidgets('empty director workspace fits a narrow screen in $brightness',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 680);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester
          .pumpWidget(_host(const DirectorToolsPage(), brightness: brightness));
      await tester.pumpAndSettle();
      expect(find.text('开始导演你的梦'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.textContaining('不需要选择模型'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'director-empty-${brightness.name}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final size in [const Size(320, 680), const Size(844, 393)]) {
    testWidgets(
        'director colorize remains usable at $size with large text and keyboard',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      vm.selectTool(DirectorToolType.colorize);
      await tester.pumpWidget(_host(const DirectorToolsPage(), scale: 2));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.tap(field);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'selected result opens director with that image and processing reveals comparison',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final generation = FrontendGenerationFake();
    sl.registerSingleton<GenerationViewModel>(generation);
    await tester.pumpWidget(_host(const SizedBox(key: ValueKey('preload'))));
    await tester.runAsync(() => precacheImage(FileImage(File(input)),
        tester.element(find.byKey(const ValueKey('preload')))));
    generation.receive(frontendResult(id: 'selected-result', imagePath: input));
    await tester.pumpWidget(_host(const GeneratePage()));
    await tester.pumpAndSettle();
    final more = find.byKey(const ValueKey('result-more-button'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await _capture(tester, 'image-actions');
    await tester.tap(find.text('导演工具'));
    await tester.pumpAndSettle();
    expect(find.byType(DirectorToolsPage), findsOneWidget);
    expect(
        tester
            .widget<DirectorToolsPage>(find.byType(DirectorToolsPage))
            .initialImagePath,
        input);
    expect(vm.inputPath, input);
    final process = find.byKey(const ValueKey('director-process'));
    await _capture(tester, 'director-imported');
    await tester.ensureVisible(process);
    await tester.runAsync(() async {
      await tester.tap(process);
      // Wait for real file IO used to save the generated comparison image.
      while (vm.isProcessing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (vm.outputPath != null) {
        await precacheImage(FileImage(File(vm.outputPath!)),
            tester.element(find.byType(DirectorToolsPage)));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('处理前'), findsOneWidget);
    expect(find.text('处理后'), findsOneWidget);
    final comparison =
        tester.widget<InpaintComparison>(find.byType(InpaintComparison));
    expect(comparison.beforePath, input);
    expect(comparison.afterPath, vm.outputPath);
    expect(comparison.fit, BoxFit.contain);
    final divider = find.byKey(const ValueKey('inpaint-comparison-drag'));
    await tester.drag(divider, const Offset(80, 0));
    await tester.pumpAndSettle();
    final reveal = tester.widget<ClipRect>(
        find.byKey(const ValueKey('inpaint-comparison-reveal')));
    expect((reveal.clipper as InpaintRevealClipper).fraction, greaterThan(0.5));
    await _capture(tester, 'director-comparison');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    generation.dispose();
  });
}

final _captureKey = GlobalKey();

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('DIRECTOR_CAPTURE')) return;
  await tester.pumpAndSettle();
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/director-preview/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _host(Widget child,
        {Brightness brightness = Brightness.dark, double scale = 1}) =>
    RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNaiHuishiTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: child,
        ));

class _Settings implements ManageSettingsUseCase {
  String? model = 'nai-diffusion-4-5-full';
  int modelWrites = 0;
  @override
  Future<List<ApiEndpoint>> getEndpoints(ImageProviderType provider) async => [
        for (final id in [
          AppConstants.novelAiChatCompletionsEndpointId,
          AppConstants.novelAiImageGenerationsEndpointId,
          AppConstants.novelAiOfficialEndpointId
        ])
          ApiEndpoint(
              id: id,
              name: id,
              baseUrl: 'https://example.com',
              apiKey: 'test',
              models: const ['nai-diffusion-3', 'nai-diffusion-4-5-full']),
      ];
  @override
  Future<String?> getActiveEndpointId(ImageProviderType provider) async =>
      AppConstants.novelAiChatCompletionsEndpointId;
  @override
  Future<String?> getActiveModel(ImageProviderType provider) async => model;
  @override
  Future<void> setActiveModel(ImageProviderType provider, String? value) async {
    modelWrites++;
    model = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api extends NovelAiApiService {
  final Uint8List bytes;
  final requests = <(String, String, String)>[];
  Completer<Uint8List>? completion;
  _Api(this.bytes) : super(Dio());
  @override
  Future<Uint8List> processDirectorImage(
      {required String imagePath,
      required String operation,
      required String model,
      required String apiKey,
      required String baseUrl,
      String? prompt,
      int? defry}) async {
    requests.add(('7877', imagePath, model));
    if (completion != null) return completion!.future;
    return bytes;
  }

  @override
  Future<Uint8List> processDirectorImageIkun(
      {required String imagePath,
      required String operation,
      required String model,
      required String apiKey,
      required String baseUrl,
      String? prompt,
      int? defry}) async {
    requests.add(('ikun', imagePath, model));
    if (completion != null) return completion!.future;
    return bytes;
  }
}

class _Save implements SaveImageUseCase {
  @override
  Future<bool> saveToGallery(String path) async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
