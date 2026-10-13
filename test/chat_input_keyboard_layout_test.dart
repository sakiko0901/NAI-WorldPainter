import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_input_bar.dart';

void main() {
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
