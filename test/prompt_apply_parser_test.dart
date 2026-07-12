import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/prompt_apply_parser.dart';

void main() {
  group('parseAppliedSegments', () {
    group('JSON code block', () {
      test(
          'parses positive/negative/characters with two roles, second role has no negative',
          () {
        const content = '''
这是一些建议：

```json
{
  "positive": "masterpiece, best quality, 1girl",
  "negative": "lowres, bad anatomy",
  "characters": [
    {"positive": "blonde hair, blue eyes", "negative": "green hair"},
    {"positive": "red hair, red eyes"}
  ]
}
```
''';
        final result = parseAppliedSegments(content);
        expect(result.positive, 'masterpiece, best quality, 1girl');
        expect(result.negative, 'lowres, bad anatomy');
        expect(result.characterPrompts.length, 2);
        expect(result.characterPrompts[0], 'blonde hair, blue eyes');
        expect(result.characterPrompts[1], 'red hair, red eyes');
        expect(result.characterNegatives.length, 2);
        expect(result.characterNegatives[0], 'green hair');
        expect(result.characterNegatives[1],
            ''); // No negative for second character
        expect(result.isEmpty, false);
      });

      test('parses single character without negative', () {
        const content = '''
```json
{
  "positive": "scenery, landscape",
  "characters": [
    {"positive": "sunset, mountains"}
  ]
}
```
''';
        final result = parseAppliedSegments(content);
        expect(result.positive, 'scenery, landscape');
        expect(result.negative, isNull);
        expect(result.characterPrompts.length, 1);
        expect(result.characterPrompts[0], 'sunset, mountains');
        expect(result.characterNegatives[0], '');
        expect(result.isEmpty, false);
      });
    });

    group('bare JSON', () {
      test('parses bare JSON without code block', () {
        const content = '''
这是建议：
{"positive": "1boy, school uniform", "negative": "bad hands", "characters": []}
''';
        final result = parseAppliedSegments(content);
        expect(result.positive, '1boy, school uniform');
        expect(result.negative, 'bad hands');
        expect(result.characterPrompts, isEmpty);
        expect(result.isEmpty, false);
      });

      test('parses bare JSON with characters', () {
        const content = '''
{"positive": "test", "characters": [{"positive": "char1"}, {"positive": "char2", "negative": "neg2"}]}
''';
        final result = parseAppliedSegments(content);
        expect(result.positive, 'test');
        expect(result.characterPrompts.length, 2);
        expect(result.characterPrompts[0], 'char1');
        expect(result.characterPrompts[1], 'char2');
        expect(result.characterNegatives[0], '');
        expect(result.characterNegatives[1], 'neg2');
      });
    });

    group('missing fields JSON', () {
      test('handles JSON with only negative and character negative', () {
        const content = '''
```json
{
  "negative": "blurry, low quality",
  "characters": [
    {"negative": "wrong hair color"}
  ]
}
```
''';
        final result = parseAppliedSegments(content);
        expect(result.positive, isNull);
        expect(result.negative, 'blurry, low quality');
        expect(result.characterPrompts.length, 1);
        expect(result.characterPrompts[0], '');
        expect(result.characterNegatives[0], 'wrong hair color');
        expect(result.isEmpty, false);
      });
    });

    group('fallback labelled code blocks', () {
      test(
          'parses labelled code blocks for positive, character1, character1 negative, negative',
          () {
        const content = '''
正向：
```
masterpiece, best quality
```

角色1：
```
blonde hair, blue eyes
```

角色1负向：
```
green hair
```

负向：
```
lowres, bad anatomy
```
''';
        final result = parseAppliedSegments(content);
        expect(result.positive, 'masterpiece, best quality');
        expect(result.negative, 'lowres, bad anatomy');
        expect(result.characterPrompts.length, 1);
        expect(result.characterPrompts[0], 'blonde hair, blue eyes');
        expect(result.characterNegatives[0], 'green hair');
        expect(result.isEmpty, false);
      });

      test('parses multiple positive blocks and aggregates them', () {
        const content = '''
正向：
```
1girl
```

通用底模词：
```
masterpiece
```
''';
        final result = parseAppliedSegments(content);
        expect(result.positive, '1girl, masterpiece');
        expect(result.isEmpty, false);
      });

      test('parses character blocks with index', () {
        const content = '''
角色1：
```
char1 prompt
```

角色2：
```
char2 prompt
```

角色2负向：
```
char2 negative
```
''';
        final result = parseAppliedSegments(content);
        expect(result.characterPrompts.length, 2);
        expect(result.characterPrompts[0], 'char1 prompt');
        expect(result.characterPrompts[1], 'char2 prompt');
        expect(result.characterNegatives[0], '');
        expect(result.characterNegatives[1], 'char2 negative');
      });
    });

    group('plain explanation only', () {
      test('returns empty when no code blocks or JSON', () {
        const content = '''
这是一些解释文字，没有任何代码块或 JSON。
只是普通的文本说明。
''';
        final result = parseAppliedSegments(content);
        expect(result.isEmpty, true);
        expect(result.positive, isNull);
        expect(result.negative, isNull);
        expect(result.characterPrompts, isEmpty);
      });

      test('returns empty when only unlabeled code blocks', () {
        const content = '''
这是一些说明：

```
some random code
```
''';
        final result = parseAppliedSegments(content);
        expect(result.isEmpty, true);
      });
    });

    group('JSON priority over labelled blocks', () {
      test('prefers JSON over labelled blocks when both present', () {
        const content = '''
正向：
```
labelled positive
```

```json
{
  "positive": "json positive",
  "negative": "json negative"
}
```
''';
        final result = parseAppliedSegments(content);
        // JSON should take priority
        expect(result.positive, 'json positive');
        expect(result.negative, 'json negative');
      });
    });
  });

  group('splitPromptContent', () {
    test('splits content into segments', () {
      const content = '''
Text before

```dart
code here
```

Text after
''';
      final segments = splitPromptContent(content);
      expect(segments.length, 3);
      expect(segments[0].isCode, false);
      expect(segments[1].isCode, true);
      expect(segments[1].text, 'code here');
      expect(segments[2].isCode, false);
    });

    test('extracts label from text before code block', () {
      const content = '''
正向：
```
prompt text
```
''';
      final segments = splitPromptContent(content);
      expect(segments.length, 2);
      expect(segments[0].isCode, false);
      expect(segments[1].isCode, true);
      expect(segments[1].label, '正向');
    });
  });

  group('extractPromptLabel', () {
    test('extracts label with colon', () {
      expect(extractPromptLabel('正向：'), '正向');
      expect(extractPromptLabel('负向:'), '负向');
    });

    test('extracts label from line with markdown', () {
      expect(extractPromptLabel('**角色1：**'), '角色1');
      expect(extractPromptLabel('__通用底模词：__'), '通用底模词');
    });

    test('returns empty string for no label', () {
      expect(extractPromptLabel('just some text'), '');
    });
  });

  group('label classification', () {
    test('isCharacterLabel identifies character labels', () {
      expect(isCharacterLabel('角色1'), true);
      expect(isCharacterLabel('角色 2'), true);
      expect(isCharacterLabel('角色1正向'), true);
      expect(isCharacterLabel('正向'), false);
      expect(isCharacterLabel('负向'), false);
      expect(isCharacterLabel(''), false);
    });

    test('isNegativeLabel identifies negative labels', () {
      expect(isNegativeLabel('负向'), true);
      expect(isNegativeLabel('负面'), true);
      expect(isNegativeLabel('角色1负向'), true);
      expect(isNegativeLabel('正向'), false);
      expect(isNegativeLabel(''), false);
    });

    test('isPositiveLabel identifies positive labels', () {
      expect(isPositiveLabel('正向'), true);
      expect(isPositiveLabel('正面'), true);
      expect(isPositiveLabel('底模'), true);
      expect(isPositiveLabel('通用'), true);
      expect(isPositiveLabel('通用底模词'), true);
      expect(isPositiveLabel('负向'), false);
      expect(isPositiveLabel('角色1'), false);
      expect(isPositiveLabel(''), false);
    });
  });
}
