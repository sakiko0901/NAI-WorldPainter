import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_message_bubble.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_scroll_surface.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_settings_sheet.dart';

import 'support/chat_memory_fake.dart';

// Optional local previews use the same widgets and assertions as the tests.
const previewDirectory = String.fromEnvironment('UI_PREVIEW_DIR');
const previewFont = String.fromEnvironment('UI_PREVIEW_FONT');

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (previewDirectory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(previewDirectory).create(recursive: true);
    await File('$previewDirectory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (previewFont.isNotEmpty) {
      final loader = FontLoader('Preview');
      loader
          .addFont(File(previewFont).readAsBytes().then(ByteData.sublistView));
      await loader.load();
      for (final entry in {
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        'packages/cupertino_icons/CupertinoIcons':
            'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      }.entries) {
        final icons = FontLoader(entry.key)
          ..addFont(rootBundle.load(entry.value));
        await icons.load();
      }
    }
  });

  ThemeData theme(Brightness brightness) {
    final value = buildNaiHuishiTheme(brightness);
    return previewFont.isEmpty
        ? value
        : value.copyWith(
            textTheme: value.textTheme.apply(fontFamily: 'Preview'));
  }

  void screen(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('message actions unfold downward and reverse without jumping',
      (tester) async {
    screen(tester);
    var retried = false;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.dark),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF15181C),
            child: Align(
              alignment: Alignment.topCenter,
              child: ChatMessageBubble(
                message: LlmMessage(
                  sessionId: 'preview',
                  role: LlmMessageRole.user,
                  content: '想要温柔的逆光，头发边缘有淡淡的光晕。',
                  createdAt: DateTime(2026),
                ),
                messageIndex: 0,
                onRetry: () => retried = true,
                onEditAndResend: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    final message = find.byType(SelectableText);
    final reveal = find.byKey(const ValueKey('message-actions-reveal'));
    final originalTop = tester.getTopLeft(message).dy;
    expect(tester.getSize(reveal).height, 0);
    await tester.tap(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final partialHeight = tester.getSize(reveal).height;
    expect(partialHeight, greaterThan(0));
    expect(tester.getTopLeft(message).dy, originalTop);
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).height, greaterThan(partialHeight));
    await capture(tester, key, 'message-actions');
    await tester.tapAt(tester.getTopLeft(message) + const Offset(15, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(reveal).height, greaterThan(0));
    await tester.tapAt(tester.getTopRight(message) + const Offset(-15, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('重试'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
    expect(tester.getSize(reveal).height, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'conversation scrolls behind controls and keeps its ends reachable',
      (tester) async {
    screen(tester);
    final key = GlobalKey();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final footerHeight = ValueNotifier(84.0);
    addTearDown(footerHeight.dispose);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.dark),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF15181C),
            child: ValueListenableBuilder<double>(
              valueListenable: footerHeight,
              builder: (context, height, _) => ChatScrollSurface(
                header: const SizedBox(
                    height: 62,
                    child: Row(children: [
                      Icon(Icons.menu),
                      Spacer(),
                      Icon(Icons.settings)
                    ])),
                footer: SizedBox(
                    height: height, child: const Center(child: Text('输入消息…'))),
                bodyBuilder: (insets) => ListView.builder(
                  controller: scroll,
                  padding: insets,
                  itemCount: 24,
                  itemBuilder: (_, i) => ChatMessageBubble(
                    key: ValueKey(i),
                    message: LlmMessage(
                      sessionId: 'preview',
                      role: i.isEven
                          ? LlmMessageRole.user
                          : LlmMessageRole.assistant,
                      content:
                          '$i · ${i.isEven ? '想要温柔的逆光，头发边缘有淡淡的光晕。' : '可以加入 soft backlighting, rim light，让画面更柔和。'}',
                      createdAt: DateTime(2026),
                    ),
                    messageIndex: i,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.byKey(const ValueKey(0))).dy, greaterThan(62));
    scroll.jumpTo(110);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(ListView)).dy, 0);
    expect(tester.getTopLeft(find.byKey(const ValueKey(0))).dy, lessThan(0));
    await capture(tester, key, 'chat-edge-blur');
    footerHeight.value = 190;
    await tester.pumpAndSettle();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.byKey(const ValueKey(23))).dy,
        lessThanOrEqualTo(844 - 190));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'prompt cards preserve drafts and save independently $brightness',
        (tester) async {
      screen(tester);
      final h = createChatMemoryHarness();
      addTearDown(h.dispose);
      await tester.runAsync(h.viewModel.ensureInitialized);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme(brightness),
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                        onPressed: () =>
                            showChatSettingsSheet(context, h.viewModel),
                        child: const Text('设置'),
                      ))),
        ),
      ));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通用'));
      await tester.pumpAndSettle();
      expect(find.text('知识库'), findsNothing);
      expect(find.text('重新加载'), findsNothing);
      expect(find.textContaining('按会话版本'), findsNothing);
      await capture(tester, key, 'settings-${brightness.name}');
      await tester.ensureVisible(find.text('系统提示词'));
      await tester.tap(find.text('系统提示词'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保持简洁，先理解画面再编排提示词。');
      await tester.ensureVisible(find.text('系统提示词'));
      await tester.tap(find.text('系统提示词'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('系统提示词'));
      await tester.tap(find.text('系统提示词'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '保持简洁，先理解画面再编排提示词。');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(h.viewModel.systemPrompt, '保持简洁，先理解画面再编排提示词。');
      await tester.ensureVisible(find.text('系统提示词'));
      await tester.tap(find.text('系统提示词'));
      await tester.pumpAndSettle();
      for (final version in ['V5', 'V4.5']) {
        await tester.ensureVisible(find.text('$version 默认提示词'));
        await tester.tap(find.text('$version 默认提示词'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '$version soft lighting');
        await tester.enterText(fields.at(1), '$version lowres');
        await tester.ensureVisible(find.text('保存 $version'));
        await tester.tap(find.text('保存 $version'));
        await tester.pumpAndSettle();
        await capture(tester, key, 'prompt-$version-${brightness.name}');
        await tester.ensureVisible(find.text('$version 默认提示词'));
        await tester.tap(find.text('$version 默认提示词'));
        await tester.pumpAndSettle();
      }
      expect(h.viewModel.defaultStyleWordsV5, 'V5 soft lighting');
      expect(h.viewModel.defaultNegativeWordsV5, 'V5 lowres');
      expect(h.viewModel.defaultStyleWordsV45, 'V4.5 soft lighting');
      expect(h.viewModel.defaultNegativeWordsV45, 'V4.5 lowres');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
