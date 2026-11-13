import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_input_bar.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/prompt_change_preview.dart';

void main() {
  testWidgets('sending composer exposes an actionable stop control',
      (tester) async {
    var stopped = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInputBar(
      isSending: true,
      onStop: () => stopped = true,
      onSend: (_, {imageBase64, imageBase64s = const [], textAttachment}) {},
    ))));
    await tester.tap(find.byIcon(Icons.stop_rounded));
    expect(stopped, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'prompt review shows additions and removals without narrow screen overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AlertDialog(
      title: Text('检查提示词改动'),
      content: PromptChangePreview(change: {
        'target': 'negative',
        'mode': 'replace',
        'before': 'low quality, extra fingers',
        'after': 'low quality, bad anatomy'
      }),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('− extra fingers'), findsOneWidget);
    expect(find.text('+ bad anatomy'), findsOneWidget);
    expect(find.text('修改前'), findsOneWidget);
    expect(find.text('修改后'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
