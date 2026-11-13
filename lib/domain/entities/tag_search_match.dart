import 'tag_completion.dart';

class TagSearchMatch {
  const TagSearchMatch(this.tag, this.kind,
      {this.distance = 0, this.matchedTerm = ''});
  final TagCompletion tag;
  final String kind;
  final int distance;
  final String matchedTerm;
  String get label => switch (kind) {
        'exact' => '准确匹配',
        'alias' => '别名匹配',
        'translation' => '中文匹配',
        'prefix' => '前缀匹配',
        'words' => '词语匹配',
        _ => '拼写近似（候选）',
      };
}
