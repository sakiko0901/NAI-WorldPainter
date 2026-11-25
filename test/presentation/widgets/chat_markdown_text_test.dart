import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_markdown_text.dart';

void main() {
  testWidgets(
      'renders bold, hanging bullets, and Danbooru inline code pills cleanly',
      (tester) async {
    const sample = '已通过词库确认 Danbooru 对应标签为 `evanescia_(honkai:_star_rail)`。\n\n'
        '**主要改动： **\n'
        '- **人物与标签**: 将原人物替换为 `evanescia_(honkai:_star_rail)`。\n'
        '- **构图与细节**: 保留玻璃窗贴面特写视角。\n\n'
        '```text\n'
        'evanescia_(honkai:_star_rail), silver hair\n'
        '```';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNaiHuishiAppearanceTheme(AppearanceMode.coffeePaper),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ChatMarkdownText(
              text: sample,
              editorialSerif: true,
              baseStyle: TextStyle(fontSize: 15.5, height: 1.68),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No raw markdown asterisks should remain on screen.
    expect(find.textContaining('**'), findsNothing);
    // Inline code preserves Danbooru underscores verbatim and remains selectable.
    expect(
      find.textContaining('evanescia_(honkai:_star_rail)'),
      findsNWidgets(3),
    );
    // Hanging bullets rendered with real dot markers.
    expect(find.text('•'), findsNWidgets(2));
    // Fenced code block rendered cleanly.
    expect(
      find.text('evanescia_(honkai:_star_rail), silver hair'),
      findsOneWidget,
    );
    // Editorial mixed typography: Latin runs use serif while CJK stays sans-serif.
    final firstParagraph =
        tester.widget<SelectableText>(find.byType(SelectableText).first);
    final rootSpan = firstParagraph.textSpan!;
    expect(rootSpan.style?.fontFamily, 'sans-serif');
    expect(
      rootSpan.children!.any(
        (span) =>
            span is TextSpan &&
            span.text == 'Danbooru' &&
            span.style?.fontFamily == 'serif',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
