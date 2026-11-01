String normalizeCompletionTag(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

class TagCompletion {
  const TagCompletion(
      {required this.tag,
      this.translation = '',
      this.category = 0,
      this.count = 0,
      this.alias,
      this.match = 0,
      this.online = false});

  final String tag;
  final String translation;
  final int category;
  final int count;
  final String? alias;
  final int match;
  final bool online;

  String get displayTag => tag.replaceAll('_', ' ');
  String get categoryLabel => switch (category) {
        1 || 8 => '画师',
        3 || 10 => '作品',
        4 || 11 => '角色',
        5 || 14 => '元数据',
        9 => '贡献者',
        12 => '物种',
        15 => '设定',
        _ => '普通',
      };
}
