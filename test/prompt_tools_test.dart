import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/emphasis_controller.dart';
import 'package:nai_huishi/presentation/widgets/prompt_editor_field.dart';
import 'package:nai_huishi/presentation/widgets/prompt_footer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('NAI weight resets and background tints preserve the source text', () {
    const text = '{1.3::cat::, dog}, /*disabled:2::fox::*/, 0.7::bird::';
    final spans = emphasisSpans(text);
    expect(spans.map((span) => span.text).join(), text);

    Color? colorAt(String word) {
      final offset = text.indexOf(word);
      var start = 0;
      for (final span in spans) {
        final end = start + span.text!.length;
        if (offset >= start && offset < end) return span.style?.backgroundColor;
        start = end;
      }
      return null;
    }

    expect(colorAt('cat')!.withAlpha(255), const Color(0xffed5807));
    expect(colorAt('dog'), isNull);
    expect(colorAt('fox'), isNull);
    expect(colorAt('bird')!.withAlpha(255), const Color(0xff079ced));
    expect(emphasisSpans('1.3::cat::', numericEnabled: false).single.style,
        isNull);
  });
  testWidgets(
      'footer stays separate from scrolling editor and hides in expanded editor',
      (tester) async {
    final controller = TextEditingController(text: 'blue sky');
    addTearDown(controller.dispose);
    bool? requestedTransparency;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: PromptEditorField(
                  controller: controller,
                  hintText: '',
                  onChanged: (_) {},
                  textColor: Colors.black,
                  editorTitle: '正向提示词',
                  showFooter: true,
                  onTransparentBackgroundChanged: (value) =>
                      requestedTransparency = value,
                  onExpandedSubmit: (_) async {},
                )))));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('透明背景'));
    await tester.pump();
    expect(requestedTransparency, true);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(controller.text, 'blue sky');
    await tester.tap(find.byTooltip('放大编辑'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.byType(PromptFooter)),
        findsNothing);
    expect(find.descendant(of: sheet, matching: find.byType(TextField)),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
