import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/local/png_metadata_edit.dart';
import 'package:nai_huishi/data/datasources/local/png_metadata_service.dart';

void main() {
  final original = PngMetadataDocument(
    text: {
      'Description': 'old description',
      'prompt': 'old prompt',
      'uc': 'old negative',
      'negative_prompt': 'old negative alias',
      'seed': '42',
      'custom': 'retained',
    },
    comment: {
      'prompt': 'old prompt',
      'uc': 'old negative',
      'negative_prompt': 'old negative alias',
      'seed': 42,
      'steps': 28,
      'v4_prompt': {
        'caption': {
          'base_caption': 'old base',
          'char_captions': [
            {
              'char_caption': 'character prompt',
              'centers': [
                {'x': 0.2, 'y': 0.7},
              ],
            },
          ],
        },
        'use_coords': true,
      },
      'v4_negative_prompt': {
        'caption': {'base_caption': 'old negative base'},
      },
      'reference_image_multiple': ['encoded reference'],
      'unknown_flag': true,
    },
  );

  test('edits all base prompt aliases while retaining characters and extras',
      () {
    final values = PngMetadataEdit.values(original)
      ..['prompt'] = '新的提示词, landscape'
      ..['uc'] = 'new negative'
      ..['seed'] = '123'
      ..['scale'] = '5.5';
    final text = PngMetadataEdit.build(original, values,
        extraJson: jsonEncode(PngMetadataEdit.extraComment(original)));
    final comment = jsonDecode(text['Comment']!) as Map<String, dynamic>;
    expect(text['Description'], values['prompt']);
    expect(text['prompt'], values['prompt']);
    expect(text['uc'], values['uc']);
    expect(text['negative_prompt'], values['uc']);
    expect(comment['prompt'], values['prompt']);
    expect(comment['negative_prompt'], values['uc']);
    expect(comment['v4_prompt']['caption']['base_caption'], values['prompt']);
    expect(
        comment['v4_negative_prompt']['caption']['base_caption'], values['uc']);
    expect(comment['v4_prompt']['caption']['char_captions'],
        (original.comment['v4_prompt'] as Map)['caption']['char_captions']);
    expect(comment['reference_image_multiple'], ['encoded reference']);
    expect(comment['unknown_flag'], isTrue);
    expect(text['custom'], 'retained');
    expect(comment['seed'], 123);
    expect(comment['scale'], 5.5);
    expect(original.comment['prompt'], 'old prompt');
    expect((original.comment['v4_prompt'] as Map)['caption']['base_caption'],
        'old base');
  });

  test('empty fields remove numeric values and empty prompts replace aliases',
      () {
    final fields = PngMetadataEdit.values(original)
      ..['prompt'] = ''
      ..['uc'] = ''
      ..['seed'] = '  '
      ..['steps'] = '';
    final text = PngMetadataEdit.build(original, fields, extraJson: '{}');
    final comment = jsonDecode(text['Comment']!) as Map;
    expect(text['Description'], '');
    expect(text['prompt'], '');
    expect(text['negative_prompt'], '');
    expect(text.containsKey('seed'), isFalse);
    expect(comment.containsKey('seed'), isFalse);
    expect(comment.containsKey('steps'), isFalse);
    expect(comment.containsKey('v4_prompt'), isFalse);
    expect(comment.containsKey('reference_image_multiple'), isFalse);
    expect(comment['prompt'], '');
    expect(comment['uc'], '');
  });

  test('numeric and JSON validation reject invalid changes instead of fallback',
      () {
    for (final value in ['hello', '1.5', 'NaN']) {
      expect(PngMetadataEdit.validateValue('seed', value), isNotNull);
    }
    for (final value in ['NaN', 'Infinity', '-Infinity', 'hello']) {
      expect(PngMetadataEdit.validateValue('scale', value), isNotNull);
    }
    expect(PngMetadataEdit.validateValue('seed', '-1'), isNull);
    expect(PngMetadataEdit.validateValue('steps', '0'), isNotNull);
    expect(PngMetadataEdit.validateValue('height', '-1'), isNotNull);
    expect(PngMetadataEdit.validateValue('width', '0'), isNotNull);
    expect(PngMetadataEdit.validateValue('scale', '5.75'), isNull);
    expect(PngMetadataEdit.validateValue('scale', ''), isNull);
    for (final json in ['[]', 'null', 'broken']) {
      expect(PngMetadataEdit.validateExtraJson(json), isNotNull);
      expect(() => PngMetadataEdit.build(original, {}, extraJson: json),
          throwsFormatException);
    }
    expect(
        () => PngMetadataEdit.build(
            original, {...PngMetadataEdit.values(original), 'seed': 'abc'},
            extraJson: '{}'),
        throwsFormatException);
  });

  test('reads v4-only base captions and new numbers keep numeric JSON types',
      () {
    final document = PngMetadataDocument(text: {}, comment: {
      'v4_prompt': {
        'caption': {'base_caption': 'v4 prompt'},
      },
      'v4_negative_prompt': {
        'caption': {'base_caption': 'v4 negative'},
      },
    });
    final fields = PngMetadataEdit.values(document);
    expect(fields['prompt'], 'v4 prompt');
    expect(fields['uc'], 'v4 negative');
    final result = PngMetadataEdit.build(document,
        {...fields, 'steps': '20', 'width': '1024', 'cfg_rescale': '0.25'},
        extraJson: jsonEncode(PngMetadataEdit.extraComment(document)));
    final comment = jsonDecode(result['Comment']!) as Map;
    expect(comment['steps'], isA<int>());
    expect(comment['width'], 1024);
    expect(comment['cfg_rescale'], 0.25);
  });
}
