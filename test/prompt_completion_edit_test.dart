import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/utils/prompt_completion_edit.dart';

TextEditingValue caret(String marked) {
  final at = marked.indexOf('|');
  return TextEditingValue(
      text: marked.replaceFirst('|', ''),
      selection: TextSelection.collapsed(offset: at));
}

void main() {
  test('replaces whole current tag while preserving surrounding text', () {
    final value = caret('1girl, blu|e h, smile');
    final edit = PromptCompletionEdit.parse(value)!;
    expect(edit.query, 'blue_h');
    final result = edit.apply(value, 'blue_hair');
    expect(result.text, '1girl, blue hair, smile');
    expect(result.selection.extentOffset, '1girl, blue hair, '.length);
  });

  test('keeps NovelAI bracket and numeric weights', () {
    for (final entry in {
      '{{blue h|}}': '{{blue hair}}, ',
      '[blue h|]': '[blue hair], ',
      '1.25::blue h|::': '1.25::blue hair::, ',
      '1.25::smile, blue h|::': '1.25::smile, blue hair::, ',
      '(blue h|:1.2)': '(blue hair:1.2), ',
      'artist:blue h|': 'artist:blue hair, ',
    }.entries) {
      final value = caret(entry.key);
      expect(PromptCompletionEdit.parse(value)!.apply(value, 'blue_hair').text,
          entry.value,
          reason: entry.key);
    }
  });

  test('literal parentheses and emoticons remain valid', () {
    for (final tag in ['hatsune_miku_(vocaloid)', ':3', '(o_o)', '>_<']) {
      expect(PromptCompletionEdit.parse(caret('$tag|'))!.query, tag);
    }
  });

  test('composition, selection and weight digits do not trigger replacement',
      () {
    expect(
        PromptCompletionEdit.parse(const TextEditingValue(
            text: '蓝色',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 0, end: 2))),
        isNull);
    expect(
        PromptCompletionEdit.parse(const TextEditingValue(
            text: 'blue hair',
            selection: TextSelection(baseOffset: 0, extentOffset: 4))),
        isNull);
    expect(PromptCompletionEdit.parse(caret('1.2|5::blue hair::')), isNull);
  });

  test('existing tags normalize weights, spaces and case', () {
    final edit = PromptCompletionEdit.parse(
        caret('{{Blue Hair}}, 1.2::red_eyes::, sm|'))!;
    expect(edit.existing, {'blue_hair', 'red_eyes'});
    expect(edit.artistOnly, false);
    expect(PromptCompletionEdit.parse(caret('artist:ab|'))!.artistOnly, true);
  });

  test('related insertion preserves weighted source and following tag', () {
    final value = caret('1.2::blue hair|::, smile');
    expect(
        PromptCompletionEdit.parse(value)!
            .apply(value, 'long_hair', related: true)
            .text,
        '1.2::blue hair::, long hair, smile');
  });

  test('line breaks and comma preference are respected', () {
    final value = caret('smile\nblue h|\nred eyes');
    expect(PromptCompletionEdit.parse(value)!.apply(value, 'blue_hair').text,
        'smile\nblue hair\nred eyes');
    final end = caret('blue h|');
    expect(
        PromptCompletionEdit.parse(end)!
            .apply(end, 'blue_hair', autoComma: false)
            .text,
        'blue hair');
  });
}
