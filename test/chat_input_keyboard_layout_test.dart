import 'package:flutter/material.dart';
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
              onSend: (_, {imageBase64, textAttachment}) {},
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
    expect(resting.height, greaterThanOrEqualTo(64));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final expanding = tester.getRect(surface);
    await tester.pumpAndSettle();
    final focused = tester.getRect(surface);
    expect(expanding.width, greaterThan(resting.width));
    expect(expanding.width, lessThan(focused.width));
    expect(focused.left, lessThan(resting.left));
    expect(focused.right, greaterThan(resting.right));
    expect(focused.center.dx, resting.center.dx);

    await tester.tapAt(const Offset(180, 100));
    await tester.pumpAndSettle();
    expect(tester.getRect(surface).width, resting.width);
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
                    onSend: (_, {imageBase64, textAttachment}) {}),
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
