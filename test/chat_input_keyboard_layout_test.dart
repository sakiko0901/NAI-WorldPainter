import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_input_bar.dart';

void main() {
  Future<void> pumpComposer(
    WidgetTester tester, {
    bool reduceMotion = false,
    VoidCallback? onOpenStylePresets,
    bool isSending = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 720),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: Column(children: [
            const Expanded(child: SizedBox()),
            ChatInputBar(
              isSending: isSending,
              onSend: (_,
                  {imageBase64, imageBase64s = const [], textAttachment}) {},
              onOpenStylePresets: onOpenStylePresets,
            ),
          ]),
        ),
      ),
    ));
  }

  testWidgets('composer expands smoothly on focus and contracts on blur',
      (tester) async {
    await pumpComposer(tester);
    final surface = find.byKey(const ValueKey('chat-composer-surface'));
    final resting = tester.getRect(surface);
    expect(resting.height, 56);
    final inputElement = tester.element(find.byType(TextField));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final expanding = tester.getRect(surface);
    await tester.pumpAndSettle();
    final focused = tester.getRect(surface);
    expect(focused.height, greaterThan(resting.height + 40));
    expect(tester.element(find.byType(TextField)), same(inputElement));
    expect(expanding.width, greaterThan(resting.width));
    expect(expanding.width, lessThan(focused.width));
    expect(focused.left, lessThan(resting.left));
    expect(focused.right, greaterThan(resting.right));
    expect(focused.center.dx, resting.center.dx);

    await tester.tapAt(const Offset(180, 100));
    await tester.pumpAndSettle();
    expect(tester.getRect(surface).width, resting.width);
    expect(tester.getRect(surface).height, resting.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment menu keeps draft and focus and opens style presets',
      (tester) async {
    var styleOpened = false;
    await pumpComposer(tester, onOpenStylePresets: () => styleOpened = true);
    await tester.enterText(find.byType(TextField), 'a quiet forest');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    for (final label in ['添加照片', '添加文档', '画风收藏']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue);
    await tester.tap(find.text('画风收藏'));
    await tester.pumpAndSettle();
    expect(styleOpened, isTrue);
    expect(find.text('添加照片').hitTestable(), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'a quiet forest');
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment menu dismisses outside and respects reduced motion',
      (tester) async {
    await pumpComposer(tester, reduceMotion: true);
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pump();
    expect(find.text('添加照片').hitTestable(), findsOneWidget);
    await tester.tapAt(const Offset(180, 100));
    await tester.pump();
    expect(find.text('添加照片').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment menu cannot open while sending', (tester) async {
    await pumpComposer(tester, isSending: true);
    final addButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '添加附件');
    expect(tester.widget<IconButton>(addButton).onPressed, isNull);
    expect(find.text('添加照片').hitTestable(), findsNothing);
  });

  testWidgets('attachment, long model and draft fit a short narrow composer',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final directory = Directory.systemTemp.createTempSync('composer-image-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/pixel.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
    const picker = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, (_) async => [file.path]);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null));
    List<String>? sentImages;
    String? sentText;
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 600), textScaler: TextScaler.linear(1.5)),
        child: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(
                  maxHeight: 190,
                  isSending: false,
                  modelName:
                      'a-very-long-provider-model-name-with-capabilities',
                  onSelectModel: () async {},
                  onSend: (text,
                      {imageBase64, imageBase64s = const [], textAttachment}) {
                    sentText = text;
                    sentImages = imageBase64s;
                  },
                ))),
      ),
    ));
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加照片'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('添加照片'));
      for (var i = 0; i < 50 && find.byType(Image).evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    final surface = find.byKey(const ValueKey('chat-composer-surface'));
    expect(find.descendant(of: surface, matching: find.byType(Image)),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), '保留这张参考图\n第二行\n第三行');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('chat-composer-model')).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byTooltip('收起添加菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pumpAndSettle();
    expect(sentImages, [base64Encode(file.readAsBytesSync())]);
    expect(sentText, contains('保留这张参考图'));
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final parentResizes in [true, false]) {
    testWidgets(
        'chat input avoids keyboard with parent resizing $parentResizes',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(MaterialApp(
          theme: buildNaiHuishiTheme(Brightness.dark),
          home: Scaffold(
              resizeToAvoidBottomInset: parentResizes,
              body: Column(children: [
                const Expanded(child: SizedBox()),
                ChatInputBar(
                    includeKeyboardInset: !parentResizes,
                    isSending: false,
                    onSend: (_,
                        {imageBase64,
                        imageBase64s = const [],
                        textAttachment}) {}),
              ]))));
      await tester.enterText(find.byType(TextField), 'keep this draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TextField)).bottom,
          lessThanOrEqualTo(300));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'keep this draft');
      expect(tester.takeException(), isNull);
    });
  }
}
