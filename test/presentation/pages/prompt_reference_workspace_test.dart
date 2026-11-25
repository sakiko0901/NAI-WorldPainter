import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/repositories/character_reference_catalog_repository.dart';
import 'package:nai_huishi/domain/entities/character_reference_asset.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/pages/character_reference_library_page.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:path/path.dart' as p;
import '../../support/frontend_generation_fake.dart';

class _ReferenceFake extends FrontendGenerationFake {
  @override
  bool get supportsVibeReferences => true;
  @override
  bool get supportsPreciseReferences => true;
  @override
  int get maxVibeReferences => 16;

  @override
  Future<void> addPreciseReference(String path,
      {String referenceType = 'character&style'}) async {
    referenceMode = ReferenceMode.precise;
    vibeReferences = const [];
    preciseReferences = [
      ...preciseReferences,
      PreciseReferenceImage(path: path, referenceType: referenceType),
    ];
    notifyListeners();
  }
}

class _EmptyReferenceCatalog extends CharacterReferenceCatalogRepository {
  @override
  Future<List<CharacterReferenceAsset>> load({bool refresh = false}) async =>
      const [];

  @override
  Future<List<SavedCharacterReference>> listSaved() async => const [];
}

void main() {
  testWidgets('reference presets open from the workspace and respect switching',
      (tester) async {
    const vibe = CharacterReferenceImage(path: 'current-vibe.png');
    const asset = CharacterReferenceAsset(
      id: 'reference',
      game: '作品',
      category: '角色',
      name: '测试角色',
      variant: '',
      width: 2,
      height: 2,
      bytes: 0,
      thumbnailUrls: [],
      downloadUrls: [],
    );
    final vm = _ReferenceFake()..vibeReferences = [vibe];
    sl.registerSingleton<GenerationViewModel>(vm);
    sl.registerSingleton<CharacterReferenceCatalogRepository>(
        _EmptyReferenceCatalog());
    addTearDown(() async {
      await sl.reset();
      vm.dispose();
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: const GeneratePage(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('生成参数'));
    await tester.pumpAndSettle();
    const entry = ValueKey('workspace-reference-presets');
    await tester.ensureVisible(find.byKey(entry));
    await tester.tap(find.byKey(entry));
    await tester.pumpAndSettle();

    final pageFinder = find.byType(CharacterReferenceLibraryPage);
    expect(pageFinder, findsOneWidget);
    final page = tester.widget<CharacterReferenceLibraryPage>(pageFinder);
    expect(page.onApplyVibe, isNotNull);
    final application = page.onApplyPrecise!(
        const SavedCharacterReference(asset: asset, path: 'saved.png'));
    await tester.pumpAndSettle();
    expect(find.text('切换为角色精确参考？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await application, isFalse);
    expect(vm.vibeReferences, [vibe]);
    expect(vm.preciseReferences, isEmpty);
    expect(pageFinder, findsOneWidget);

    vm.vibeReferences = const [];
    final root = Directory.systemTemp.createTempSync('reference-workspace-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => root.path);
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      root.deleteSync(recursive: true);
    });
    final bytes = image.encodePng(image.Image(width: 2, height: 2));
    final saved = File(p.join(root.path, 'saved.png'))..writeAsBytesSync(bytes);
    expect(
      await tester.runAsync(() => page.onApplyPrecise!(
          SavedCharacterReference(asset: asset, path: saved.path))),
      isTrue,
    );
    expect(vm.referenceMode, ReferenceMode.precise);
    expect(vm.preciseReferences.single.referenceType, 'character');
    expect(vm.preciseReferences.single.path, isNot(saved.path));
    saved.deleteSync();
    expect(File(vm.preciseReferences.single.path).readAsBytesSync(), bytes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('coffee paper themes the Vibe replace-options sheet',
      (tester) async {
    const reference = CharacterReferenceImage(path: 'missing-vibe.png');
    final vm = _ReferenceFake()..vibeReferences = [reference];
    sl.registerSingleton<GenerationViewModel>(vm);
    addTearDown(() async {
      await sl.reset();
      vm.dispose();
    });
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = buildNaiHuishiAppearanceTheme(AppearanceMode.coffeePaper);
    await tester
        .pumpWidget(MaterialApp(theme: theme, home: const GeneratePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('生成参数'));
    await tester.pumpAndSettle();

    final vibe = find.text('氛围转移 · 1/16');
    await tester.ensureVisible(vibe);
    await tester.tap(vibe);
    await tester.pumpAndSettle();
    final replace = find.text('替换');
    await tester.ensureVisible(replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();

    final title = find.text('选择氛围来源');
    expect(title, findsOneWidget);
    expect(find.text('选择本地图片'), findsOneWidget);
    expect(find.text('从 Vibe 编码库选择'), findsOneWidget);
    final surface = find.ancestor(
      of: title,
      matching: find.byWidgetPredicate((widget) =>
          widget is Material &&
          widget.color == theme.bottomSheetTheme.modalBackgroundColor),
    );
    expect(surface, findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(vm.vibeReferences, [reference]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'settings hosts the reference cards and preserves the prompt on return',
      (tester) async {
    final vm = _ReferenceFake()..prompt = 'soft light, blue sky';
    sl.registerSingleton<GenerationViewModel>(vm);
    addTearDown(() async {
      await sl.reset();
      vm.dispose();
    });
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: const GeneratePage()));
    await tester.pump();
    expect(find.text('参考图像'), findsNothing);
    expect(find.text('soft light, blue sky'), findsOneWidget);
    await tester.ensureVisible(find.text('透明背景'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('透明背景'));
    await tester.pump();
    expect(vm.transparentBackground, true);
    expect(vm.prompt, 'soft light, blue sky');
    await tester.tap(find.byTooltip('生成参数'));
    await tester.pumpAndSettle();
    expect(find.text('参考图像'), findsOneWidget);
    expect(find.text('氛围转移 · 0/16'), findsOneWidget);
    expect(find.text('角色精确参考 · 0/4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    vm.referenceMode = ReferenceMode.precise;
    vm.preciseReferences = [
      const PreciseReferenceImage(path: 'missing-preview.png', fidelity: .4)
    ];
    vm.notifyListeners();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('角色精确参考 · 1/4'));
    await tester.tap(find.text('角色精确参考 · 1/4'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fidelity · 保真度: 0.4'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭生成参数'));
    await tester.pumpAndSettle();
    expect(find.text('soft light, blue sky'), findsOneWidget);
    expect(vm.prompt, 'soft light, blue sky');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'V5 precise reference card exposes Outfit, Prefer same outfit, -5..5 strength and hides Fidelity',
      (tester) async {
    final vm = _V5ReferenceFake()
      ..referenceMode = ReferenceMode.precise
      ..preciseReferences = const [
        PreciseReferenceImage(
          path: 'missing-v5.png',
          referenceType: 'character',
          strength: -1.5,
        ),
      ];
    sl.registerSingleton<GenerationViewModel>(vm);
    addTearDown(() async {
      await sl.reset();
      vm.dispose();
    });
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiAppearanceTheme(AppearanceMode.coffeePaper),
      home: const GeneratePage(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('生成参数'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('角色精确参考 · 1/4'));
    await tester.tap(find.text('角色精确参考 · 1/4'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('precise-prefer-same-outfit')),
        findsOneWidget);
    expect(find.textContaining('Fidelity'), findsNothing);
    expect(find.text('Strength · 强度: -1.50'), findsOneWidget);
    final strengthColumn = find
        .ancestor(
          of: find.text('Strength · 强度: -1.50'),
          matching: find.byType(Column),
        )
        .first;
    final slider = tester.widget<Slider>(
      find.descendant(of: strengthColumn, matching: find.byType(Slider)),
    );
    expect(slider.min, -5.0);
    expect(slider.max, 5.0);

    await tester.ensureVisible(
        find.byKey(const ValueKey('precise-prefer-same-outfit')));
    await tester.tap(find.byKey(const ValueKey('precise-prefer-same-outfit')));
    await tester.pumpAndSettle();
    expect(vm.preciseReferences.single.preferSameOutfit, isTrue);
    expect(
      vm.preciseReferences.single.wireCaption(supportsOutfit: true),
      'character_mainoutfit',
    );

    await tester.ensureVisible(find.text('角色 · Character'));
    await tester.tap(find.text('角色 · Character'));
    await tester.pumpAndSettle();
    expect(find.text('衣装 · Outfit'), findsOneWidget);
    await tester.tap(find.text('衣装 · Outfit').last);
    await tester.pumpAndSettle();
    expect(vm.preciseReferences.single.referenceType, 'costume');
    expect(
        find.byKey(const ValueKey('precise-prefer-same-outfit')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _V5ReferenceFake extends _ReferenceFake {
  @override
  bool get isV5Model => true;

  @override
  Future<void> updatePreciseReference(
    int index,
    PreciseReferenceImage reference,
  ) async {
    final next = [...preciseReferences];
    next[index] = reference;
    preciseReferences = next;
    notifyListeners();
  }
}
