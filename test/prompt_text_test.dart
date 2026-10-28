import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/utils/prompt_text.dart';

void main() {
  test('notebook import normalizes only joining commas and whitespace', () {
    for (final example in [
      ('', 'blue eyes', 'blue eyes'),
      ('  ', ', blue eyes， ', 'blue eyes'),
      ('masterpiece', 'blue eyes', 'masterpiece, blue eyes'),
      ('masterpiece,  ', ', blue eyes', 'masterpiece, blue eyes'),
      ('masterpiece，\n', '，blue eyes，', 'masterpiece, blue eyes'),
      ('masterpiece,,， ', ' ,， blue eyes', 'masterpiece, blue eyes'),
      ('masterpiece,', ' ,， ', 'masterpiece,'),
      (
        '1.3::girl, silver hair::\n[sketch]',
        '{{soft lighting}},\nblue eyes',
        '1.3::girl, silver hair::\n[sketch], {{soft lighting}},\nblue eyes'
      ),
    ]) {
      expect(appendPromptFragment(example.$1, example.$2), example.$3);
    }
  });
}
