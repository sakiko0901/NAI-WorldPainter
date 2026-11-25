import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import '../../support/frontend_generation_fake.dart';

class _ReferenceFake extends FrontendGenerationFake {
  @override
  bool get supportsVibeReferences => true;
  @override
  bool get supportsPreciseReferences => true;
  @override
  int get maxVibeReferences => 16;
}

void main() {
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
    expect(find.byKey(const ValueKey('precise-prefer-same-outfit')),
        findsNothing);
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
