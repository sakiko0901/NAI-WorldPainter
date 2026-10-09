import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/agents/tools/comic_panel_prompt_tools.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';

void main() {
  ComicPanel panel = const ComicPanel(
    id: 'panel',
    index: 1,
    title: '开场',
    prompt: '1girl, classroom',
    rect: ComicRect(x: 0, y: 0, width: 1, height: 1),
  );

  final tools = ComicPanelPromptTools(
    panel: panel,
    save: (value) async => panel = value,
  );

  test('漫画 Agent 只读取绑定分镜', () async {
    final result = await tools.read.call({});

    expect(result.success, isTrue);
    expect(result.text, contains('1girl, classroom'));
  });

  test('漫画 Agent 追加 tag 并保留已有内容', () async {
    final result = await tools.write.call({
      'content': 'classroom, close-up',
      'mode': 'append',
    });

    expect(result.success, isTrue);
    expect(panel.prompt, '1girl, classroom, close-up');
  });

  test('漫画 Agent 可以替换绑定分镜 tag', () async {
    final result = await tools.write.call({
      'content': '1girl, smile',
      'mode': 'replace',
    });

    expect(result.success, isTrue);
    expect(panel.prompt, '1girl, smile');
  });
}
