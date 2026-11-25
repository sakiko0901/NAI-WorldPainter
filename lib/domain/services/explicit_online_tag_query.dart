final _chineseLookup = RegExp(
  r'^(?:请|帮我|麻烦(?:你)?|能不能|可以)?\s*'
  r'(?:在线|联网|上网|(?<site>(?:去|用|在|到)?\s*(?:danbooru|丹波鲁)(?:\s*官网)?(?:上)?))\s*'
  r'(?:检索|查询|查找|搜索|核对|验证|查|搜)(?:一下|下)?[\s:：,，]*(?<query>.+)$',
  caseSensitive: false,
);

final _englishLookup = RegExp(
  r'^(?:please\s+)?(?:search|look\s+up|check|verify)\s+'
  r'(?:(?:danbooru|(?:the\s+)?online\s+tag\s+database)(?:\s+for)?[\s:]+(.+)|'
  r'(.+?)\s+(online|on\s+danbooru))$',
  caseSensitive: false,
);

final _tagLabel = RegExp(
  r'^(?:这个|这个角色的|该)?\s*(?:标准|规范)?\s*'
  r'(?:tags?|标签|检索词)(?:\s*[:：]\s*|\s+)',
  caseSensitive: false,
);

final _tagSuffix = RegExp(
  r'(?:\s*的\s*(?:标准|规范)?\s*(?:角色)?\s*|\s+)(?:tags?|标签)$',
  caseSensitive: false,
);

final _qualifiedTag =
    RegExp(r'^[a-z0-9_][^\s,，]*_\([^)]+\)$', caseSensitive: false);

/// Extract a single query only from an explicit online lookup request.
String? explicitOnlineTagQuery(String message) {
  final text = message.trim().replaceFirst(RegExp(r'[.。？！?!]+$'), '').trim();
  final chinese = _chineseLookup.firstMatch(text);
  final english = chinese == null ? _englishLookup.firstMatch(text) : null;
  final request =
      chinese?.namedGroup('query') ?? english?.group(1) ?? english?.group(2);
  if (request == null) return null;

  final searchText = request.trim();
  final mentionsTag =
      _tagLabel.hasMatch(searchText) || _tagSuffix.hasMatch(searchText);
  var query = searchText
      .replaceFirst(_tagLabel, '')
      .replaceFirst(_tagSuffix, '')
      .trim();
  const quotes = {'“': '”', '「': '」', '‘': '’', '"': '"', "'": "'", '`': '`'};
  if (query.length >= 2 && quotes[query[0]] == query[query.length - 1]) {
    query = query.substring(1, query.length - 1).trim();
  } else if (RegExp(r'[,，;；。?!？！]').hasMatch(query)) {
    return null;
  }
  final namedSite = chinese?.namedGroup('site') != null ||
      english?.group(1) != null ||
      english?.group(3)?.toLowerCase().endsWith('danbooru') == true;
  if (!mentionsTag && !namedSite && !_qualifiedTag.hasMatch(query)) {
    return null;
  }
  if (query.isEmpty ||
      query.length > 160 ||
      RegExp(r'[\r\n]').hasMatch(query) ||
      RegExp(r'^(?:这个|该|这张图里)?\s*(?:tags?|标签|角色|它|这个|词)?$',
              caseSensitive: false)
          .hasMatch(query)) {
    return null;
  }
  return query;
}
