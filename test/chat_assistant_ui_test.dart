import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_settings_sheet.dart';
import 'package:nai_huishi/presentation/pages/llm_provider_edit_page.dart';
import 'support/chat_memory_fake.dart';

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('assistant settings and searchable models fit $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = createChatMemoryHarness();
      addTearDown(h.dispose);
      await tester.runAsync(h.viewModel.ensureInitialized);
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: buildNaiHuishiTheme(brightness),
          home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () =>
                              showChatSettingsSheet(context, h.viewModel),
                          child: const Text('设置')))))));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('助手设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('main-test-model'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'vision');
      await tester.pumpAndSettle();
      expect(find.text('main-test-model').hitTestable(), findsNothing);
      expect(find.text('vision-test-model').hitTestable(), findsOneWidget);
      await tester.tap(find.text('暂不选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通用'));
      await tester.pumpAndSettle();
      expect(find.text('上下文条数'), findsNothing);
      expect(find.text('多模态'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('supplier model cards fit narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await tester.runAsync(h.viewModel.ensureInitialized);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: RepaintBoundary(
            key: key,
            child: LlmProviderEditPage(
                vm: h.viewModel, providerId: 'test-provider'))));
    await tester.pumpAndSettle();
    expect(find.text('检测连接'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
