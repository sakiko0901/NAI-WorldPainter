import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/app_destination.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_message_bubble.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_scroll_surface.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_settings_sheet.dart';
import 'package:nai_huishi/presentation/widgets/studio_navigation_bar.dart';

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

  for (final role in LlmMessageRole.values) {
    testWidgets('message actions follow the layout for ${role.name}',
        (tester) async {
      screen(tester);
      var retried = false;
      final key = GlobalKey();
      final readStarted = AgentEvent(
        toolName: 'read_current_prompts',
        toolCallId: 'read',
        arguments: const {},
        status: 'running',
        createdAt: DateTime(2026),
      );
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.dark),
        builder: (_, child) => RepaintBoundary(key: key, child: child!),
        home: Scaffold(
          body: ColoredBox(
            color: theme(Brightness.dark).scaffoldBackgroundColor,
            child: Align(
              alignment: Alignment.topCenter,
              child: ChatMessageBubble(
                message: LlmMessage(
                  id: 1,
                  sessionId: 'preview',
                  role: role,
                  content: '想要温柔的逆光，头发边缘有淡淡的光晕。',
                  createdAt: DateTime(2026),
                  agentTimeline: role == LlmMessageRole.assistant
                      ? [
                          AgentEvent(
                            toolName: 'write_prompt',
                            toolCallId: 'write',
                            arguments: const {
                              'target': 'positive',
                              'content': 'soft light',
                            },
                            status: 'done',
                            result: ToolResult.success('提示词已写入'),
                            createdAt: DateTime(2026, 1, 1, 0, 0, 3),
                          ),
                          readStarted,
                          readStarted.copyWith(
                            status: 'done',
                            result: ToolResult.success('已读取当前提示词框'),
                          ),
                        ]
                      : null,
                ),
                messageIndex: 0,
                onRetry: () => retried = true,
                onBranch: role == LlmMessageRole.assistant ? () {} : null,
                onUndoPrompt: role == LlmMessageRole.assistant
                    ? () => retried = true
                    : null,
                onReturnToParent:
                    role == LlmMessageRole.assistant ? () {} : null,
                onEditAndResend: role == LlmMessageRole.user ? (_) {} : null,
              ),
            ),
          ),
        ),
      ));
      final message = find.byType(SelectableText);
      final reveal = find.byKey(const ValueKey('message-actions-reveal'));
      if (role == LlmMessageRole.assistant) {
        expect(reveal, findsNothing);
        final undo = find.byTooltip('恢复上一版提示词');
        expect(undo.hitTestable(), findsOneWidget);
        final operations = find.text('操作过程 · 2 项');
        final read = find.text('读取提示词框');
        final write = find.text('写入提示词');
        final readResult = find.text('已读取当前提示词框');
        final writeResult = find.text('提示词已写入');
        final details = find.byKey(const ValueKey('chat-operations-sheet'));
        expect(read, findsOneWidget);
        expect(write, findsOneWidget);
        expect(readResult, findsNothing);
        expect(writeResult, findsNothing);
        expect(tester.getTopLeft(operations).dy,
            lessThan(tester.getTopLeft(read).dy));
        expect(
            tester.getTopLeft(read).dy, lessThan(tester.getTopLeft(write).dy));
        expect(tester.getTopLeft(write).dy,
            lessThan(tester.getTopLeft(message).dy));
        await capture(tester, key, 'message-actions-assistant');
        await tester.tap(find.text('查看详情'));
        await tester.pumpAndSettle();
        expect(details, findsOneWidget);
        expect(find.descendant(of: details, matching: find.text('操作过程')),
            findsOneWidget);
        final detailRead = find.descendant(of: details, matching: read);
        final detailWrite = find.descendant(of: details, matching: write);
        expect(detailRead, findsOneWidget);
        expect(detailWrite, findsOneWidget);
        expect(tester.getTopLeft(detailRead).dy,
            lessThan(tester.getTopLeft(detailWrite).dy));
        expect(
            find.descendant(of: details, matching: readResult), findsOneWidget);
        expect(find.descendant(of: details, matching: writeResult),
            findsOneWidget);
        await capture(tester, key, 'message-operations-assistant');
        final close = find.byTooltip('关闭操作过程');
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(details, findsNothing);
        await tester.tap(write);
        await tester.pumpAndSettle();
        expect(details, findsOneWidget);
        expect(
            find.descendant(of: details, matching: writeResult).hitTestable(),
            findsOneWidget);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(readResult, findsNothing);
        expect(writeResult, findsNothing);
        await tester.tap(undo);
        expect(retried, isTrue);
        expect(tester.takeException(), isNull);
        return;
      }
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
      await capture(tester, key, 'message-actions-${role.name}');
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
  }

  testWidgets('details scroll to the operation opened from the message',
      (tester) async {
    screen(tester);
    await tester.pumpWidget(MaterialApp(
      theme: theme(Brightness.dark),
      home: Scaffold(
        body: ChatMessageBubble(
          message: LlmMessage(
            id: 1,
            sessionId: 'preview',
            role: LlmMessageRole.assistant,
            content: '操作已完成。',
            createdAt: DateTime(2026),
            agentTimeline: [
              for (var index = 1; index <= 20; index++)
                AgentEvent(
                  toolName: '步骤 $index',
                  toolCallId: 'operation-reused',
                  arguments: const {},
                  status: 'done',
                  result: ToolResult.success('完成第 $index 步'),
                  createdAt: DateTime(2026, 1, 1, 0, 0, index),
                ),
            ],
          ),
          messageIndex: 0,
        ),
      ),
    ));

    expect(find.text('步骤 1'), findsNothing);
    await tester.tap(find.text('步骤 20'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('chat-operations-sheet'));
    final first = find.descendant(of: sheet, matching: find.text('步骤 1'));
    final last = find.descendant(of: sheet, matching: find.text('步骤 20'));
    expect(last.hitTestable(), findsOneWidget);
    expect(first.hitTestable(), findsNothing);

    final scroll = find.descendant(
        of: sheet, matching: find.byType(SingleChildScrollView));
    await tester.drag(scroll, const Offset(0, 1900));
    await tester.pumpAndSettle();
    expect(first.hitTestable(), findsOneWidget);
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
    // The lazy list can refine its estimated extent once the final row is laid out.
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.byKey(const ValueKey(23))).dy,
        lessThanOrEqualTo(844 - 190));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('integrated chat keeps messages behind glass $brightness',
        (tester) async {
      screen(tester);
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 16);
      addTearDown(tester.view.resetPadding);
      final h = (await tester.runAsync(() async {
        final h = createChatMemoryHarness();
        final session = await h.chatRepository.createSession();
        for (var i = 0; i < 8; i++) {
          await h.chatRepository.saveUserMessage(
              sessionId: session.id, userText: '想画黄昏的海边，风吹起头发，光线自然一点。');
          await h.chatRepository.saveAgentRunResult(
            sessionId: session.id,
            assistantText: '可以先确定人物和光线，再补充环境细节。\n\n'
                'soft backlighting, windswept hair, warm sunset, '
                'ocean, gentle waves, cinematic lighting\n\n'
                '让夕阳从人物侧后方照过来，头发边缘留一点柔和的轮廓光。'
                '背景保持开阔，海面只保留少量细碎反光，避免抢走人物的注意力。\n\n'
                '如果想让画面更安静，可以降低对比度，让天空和海面自然衔接。',
          );
        }
        await h.viewModel.ensureInitialized();
        return h;
      }))!;
      addTearDown(() async {
        await sl.reset();
        h.dispose();
      });
      sl.registerSingleton<LlmChatViewModel>(h.viewModel);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme(brightness),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            extendBody: true,
            body: ChatDrawer(embedded: true, onClose: () {}),
            bottomNavigationBar: StudioNavigationBar(
              selected: AppDestination.assistant,
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, 250));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(list).dy, 0);
      expect(tester.getBottomRight(list).dy, 844);
      expect(tester.getBottomRight(find.byType(TextField)).dy,
          lessThan(tester.getTopLeft(find.byType(StudioNavigationBar)).dy));
      await capture(tester, key, 'chat-integrated-${brightness.name}');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'prompt cards preserve drafts and save independently $brightness',
        (tester) async {
      screen(tester);
      final h = (await tester.runAsync(() async {
        final h = createChatMemoryHarness();
        await h.viewModel.ensureInitialized();
        return h;
      }))!;
      addTearDown(h.dispose);
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
