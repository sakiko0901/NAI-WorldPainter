import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_settings_sheet.dart';
import 'package:nai_huishi/presentation/pages/llm_provider_edit_page.dart';
import 'package:nai_huishi/presentation/pages/llm_provider_manage_page.dart';
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

  testWidgets(
      'Gemini preset fills official URL and saves a manually selected key',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = createChatMemoryHarness();
    addTearDown(h.dispose);
    await tester.runAsync(h.viewModel.ensureInitialized);
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: LlmProviderManagePage(vm: h.viewModel),
    ));
    await tester.tap(find.byTooltip('添加供应商'));
    await tester.pumpAndSettle();
    for (final preset in LlmProviderPreset.values) {
      expect(find.text(preset.label), findsOneWidget);
      expect(find.text(preset.baseUrl), findsOneWidget);
    }
    await tester.tap(find.text('Gemini'));
    await tester.pumpAndSettle();
    expect(find.text('Gemini 官方接口'), findsOneWidget);
    expect(find.text(LlmProviderPreset.gemini.baseUrl), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, '输入 API Key'), 'first');
    await tester.tap(find.text('添加备用 Key'));
    await tester.pumpAndSettle();
    final backupField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '备用 Key 2');
    await tester.ensureVisible(backupField);
    await tester.enterText(backupField, 'second');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final select = find.byKey(const ValueKey('llm-gemini-active-key-field'));
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Key 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存供应商'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final saved = h.viewModel.providers.singleWhere((p) => p.name == 'Gemini');
    expect(saved.protocol, LlmApiProtocol.gemini);
    expect(saved.baseUrl, LlmProviderPreset.gemini.baseUrl);
    expect(saved.backupApiKeys, ['second']);
    expect(saved.geminiKeyIndex, 1);
    expect(h.viewModel.activeGeminiKeyIndex(saved), 1);
    expect(tester.takeException(), isNull);
  });
}
