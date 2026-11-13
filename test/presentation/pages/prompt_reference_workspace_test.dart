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
}
