import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/utils/comic_storyboard_importer.dart';

void main() {
  test('逐行 Tag 导入为有序分镜', () {
    final panels = ComicStoryboardImporter.parse('1girl, smile\n1boy, city');

    expect(panels, hasLength(2));
    expect(panels[0].title, '分镜 1');
    expect(panels[1].prompt, '1boy, city');
  });

  test('CSV 导入标题、提示词和台词', () {
    final panels = ComicStoryboardImporter.parse(
      'title,prompt,dialogue\n开场,"1girl, smile",你好',
    );

    expect(panels, hasLength(1));
    expect(panels.single.title, '开场');
    expect(panels.single.prompt, '1girl, smile');
    expect(panels.single.dialogues.single.text, '你好');
  });

  test('JSON 导入保留对话和自定义分镜位置', () {
    final panels = ComicStoryboardImporter.parse('''
      {
        "panels": [
          {
            "title": "开场",
            "prompt": "1girl",
            "rect": {"x": 0.2, "y": 0.3, "width": 0.4, "height": 0.5},
            "dialogues": [{"speaker": "少女", "text": "你好"}]
          }
        ]
      }
    ''');

    expect(panels.single.rect.x, 0.2);
    expect(panels.single.dialogues.single.speaker, '少女');
  });
}
