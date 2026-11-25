import 'dart:async';
import 'dart:convert';

import 'package:nai_huishi/data/datasources/local/tag_completion_catalog.dart';
import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/tag_search_match.dart';
import 'package:nai_huishi/domain/services/local_tag_matching.dart';

class SearchDanbooruTool extends AgentTool {
  SearchDanbooruTool(this._api, {TagCompletionCatalog? catalog})
      : _catalog = catalog ?? TagCompletionCatalog();
  final DanbooruApiService _api;
  final TagCompletionCatalog _catalog;

  @override
  String get name => 'search_danbooru';

  @override
  String get description => '检索真实存在的 Danbooru tag。默认优先查本地词库，支持英文、中文翻译、别名、'
      '空格/下划线、词序变化及少量英文拼写错误。本地无准确、明确的匹配时自动在线核验。'
      'source=local 仅查本地。source=online 直接查官方标签和有效别名，并核验语义候选。'
      '优先使用准确匹配和别名匹配。前缀、拼写近似和语义匹配仅提供候选，角色身份和外观需另行确认。'
      '每次用一个角色名、画风词或简短特征查询；已有足够结果时不要重复检索。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '标签、别名、中文译名或简短关键词；最多 160 字符。'
          },
          'source': {
            'type': 'string',
            'enum': ['auto', 'local', 'online'],
            'description': 'auto 本地优先，匹配不足时在线核验。local 完全离线。online 直接在线核验。'
          },
          'limit': {'type': 'integer', 'description': '结果数，默认 15，最大 30。'},
          'show_nsfw': {
            'type': 'boolean',
            'description': '默认 true。false 需要在线服务筛选；本地词库不含此标记。'
          },
        },
        'required': ['query'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final query = arguments['query'] is String
        ? (arguments['query'] as String).trim()
        : '';
    if (query.isEmpty || query.length > 160) {
      return ToolResult.failure('query 需为 1 至 160 字符的关键词。');
    }
    final source = arguments['source'] ?? 'auto';
    if (!const ['auto', 'local', 'online'].contains(source)) {
      return ToolResult.failure('source 仅支持 auto、local、online。');
    }
    final showNsfw = arguments['show_nsfw'] != false;
    final limit =
        (int.tryParse('${arguments['limit'] ?? 15}') ?? 15).clamp(1, 30);
    if (source == 'local' && !showNsfw) {
      return ToolResult.failure('本地词库无 NSFW 标记，无法保证筛选结果；请使用 source=online。');
    }
    String? localStatus;
    var localMatches = const <TagSearchMatch>[];
    if (source != 'online' && showNsfw) {
      try {
        final catalogQuery = query
            .replaceAll('（', '(')
            .replaceAll('）', ')')
            .replaceAllMapped(
                RegExp(r'([\u3400-\u9fff])\('), (match) => '${match[1]} (');
        // Check for ambiguity before applying the caller's display limit.
        localMatches = await _catalog.searchFuzzy(catalogQuery, limit: 30);
        final strongMatch = _strongLocalMatch(query, localMatches);
        if (localMatches.isNotEmpty &&
            (source == 'local' || strongMatch != null)) {
          return _localResult(query, localMatches, limit,
              strongMatch: strongMatch);
        }
        localStatus = localMatches.isEmpty ? '本地词库无匹配' : '本地仅有近似或歧义候选';
      } catch (_) {
        localStatus = '本地词库暂不可用';
        if (source == 'local') {
          return ToolResult.failure('$localStatus，请在标签补全设置中修复词库或使用在线检索。');
        }
      }
      if (source == 'local') {
        return ToolResult.success('本地词库无匹配「$query」。', displayText: '本地无匹配 tag');
      }
    }
    final prefix = localStatus == null ? '' : '$localStatus，已转在线核验。\n';
    try {
      final hits = await _api.searchVerified(
          query: query, limit: limit, showNsfw: showNsfw);
      if (hits.isNotEmpty) {
        return _onlineResult(query, hits, localMatches, prefix);
      }
      final status = '$prefix在线检索「$query」未核验到匹配标签。';
      if (localMatches.isNotEmpty) {
        return _localResult(query, localMatches, limit, onlineStatus: status);
      }
      return ToolResult.success(status, displayText: '在线未核验到匹配 tag');
    } catch (error) {
      final reason = error is TimeoutException ? '超时' : '失败';
      final status = '$prefix在线 Danbooru 核验「$query」$reason。';
      if (localMatches.isNotEmpty) {
        return _localResult(query, localMatches, limit, onlineStatus: status);
      }
      return ToolResult.failure(status);
    }
  }

  TagSearchMatch? _strongLocalMatch(
      String query, List<TagSearchMatch> matches) {
    final key = normalizeTagSearch(query);
    final translationKey = _translationKey(query);
    final mapped = <String, TagSearchMatch>{};
    for (final match in matches) {
      final tagName = normalizeTagSearch(match.tag.tag);
      if (match.kind == 'exact' && tagName == key) return match;
      final alias = match.tag.alias ?? match.matchedTerm;
      if ((match.kind == 'alias' && normalizeTagSearch(alias) == key) ||
          (match.kind == 'translation' &&
              _translationKey(match.tag.translation) == translationKey)) {
        mapped[tagName] = match;
      }
    }
    return mapped.length == 1 ? mapped.values.single : null;
  }

  String _translationKey(String value) =>
      normalizeTagSearch(value.replaceAll('（', '(').replaceAll('）', ')'))
          .replaceAll('_(', '(')
          .replaceAll(')_', ')');

  ToolResult _localResult(String query, List<TagSearchMatch> matches, int limit,
      {TagSearchMatch? strongMatch, String? onlineStatus}) {
    final hits = [
      if (strongMatch != null) strongMatch,
      ...matches.where((match) => match != strongMatch),
    ].take(limit).toList();
    final text = StringBuffer();
    if (onlineStatus != null) text.writeln(onlineStatus);
    text.writeln('本地 Danbooru 词库检索「$query」返回 ${hits.length} 个标签。');
    text.writeln('本地词库确认标签记录，角色身份、外观和关联特征需核对。');
    final details = <Map<String, Object?>>[];
    for (var i = 0; i < hits.length; i++) {
      final match = hits[i];
      final tag = match.tag;
      final strong = match == strongMatch;
      final label = switch (match.kind) {
        'translation' => strong ? '完整中文译名' : '中文匹配（候选）',
        'alias' when !strong => '别名匹配（候选）',
        'prefix' || 'words' => '${match.label}（候选）',
        _ => match.label,
      };
      text.writeln(
          '${i + 1}. ${tag.tag}${tag.translation.isEmpty ? '' : '（${tag.translation}）'}'
          ' [${tag.categoryLabel}] [$label]'
          '${tag.alias == null ? '' : ' 别名 ${tag.alias}'}');
      details.add({
        'tag': tag.tag,
        'cn': tag.translation,
        'category': tag.categoryLabel,
        'source': 'local',
        'match': match.kind,
        'distance': match.distance,
        'candidate': !strong,
      });
    }
    return ToolResult.success(text.toString(),
        displayText: onlineStatus == null
            ? '本地检索到 ${hits.length} 个 tag'
            : '在线未核验，保留 ${hits.length} 个本地候选',
        followUpHint: jsonEncode(details));
  }

  ToolResult _onlineResult(String query, List<VerifiedDanbooruTag> hits,
      List<TagSearchMatch> localMatches, String prefix) {
    final hasNameMatch = hits.any((hit) => switch (hit.match) {
          VerifiedDanbooruMatch.exact ||
          VerifiedDanbooruMatch.alias ||
          VerifiedDanbooruMatch.wikiName =>
            true,
          _ => false,
        });
    final text =
        StringBuffer('$prefix在线 Danbooru 检索「$query」核验了 ${hits.length} 个标签。\n');
    if (!hasNameMatch) {
      text.writeln('未核验到原查询的准确名称或别名。以下仅确认候选标签本身存在，角色身份和语义对应需核对。');
    }
    if (hits
            .where((hit) => hit.match == VerifiedDanbooruMatch.wikiName)
            .length >
        1) {
      text.writeln('官方 Wiki 中有多个条目使用该名称，需结合具体作品或版本核对。');
    }
    final localTranslations = {
      for (final match in localMatches)
        if (match.tag.translation.isNotEmpty)
          match.tag.tag: match.tag.translation,
    };
    final details = <Map<String, Object?>>[];
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      final tag = hit.tag;
      final label = switch (hit.match) {
        VerifiedDanbooruMatch.exact => '官方准确匹配',
        VerifiedDanbooruMatch.alias => '官方有效别名',
        VerifiedDanbooruMatch.qualified => '带限定词的名称候选',
        VerifiedDanbooruMatch.wikiName => '官方 Wiki 名称记录',
        VerifiedDanbooruMatch.semantic => '语义候选，官方核验标签存在',
      };
      final translation =
          tag.cnName.isEmpty ? localTranslations[tag.tag] ?? '' : tag.cnName;
      final translationSource = tag.cnName.isNotEmpty
          ? hit.semanticProvider
          : translation.isEmpty
              ? null
              : '本地词库';
      final matchedTerm = hit.matchedTerm;
      text.writeln(
          '${i + 1}. ${tag.tag}${translation.isEmpty ? '' : '（$translation）'}'
          ' [${tag.category}] [$label] ${tag.count} 帖'
          '${matchedTerm == null ? '' : ' 检索名称 $matchedTerm'}'
          '${hit.semanticProvider == null ? '' : ' 语义来源 ${hit.semanticProvider}'}'
          '${translationSource == '本地词库' ? ' 译名来源 本地词库' : ''}');
      details.add({
        'tag': tag.tag,
        'cn': translation,
        'category': tag.category,
        'post_count': tag.count,
        'source': 'online',
        'verified_by': 'Danbooru',
        'match': hit.match.name,
        if (matchedTerm != null) 'matched_term': matchedTerm,
        if (hit.semanticProvider != null)
          'candidate_source': hit.semanticProvider,
        if (translationSource != null) 'translation_source': translationSource,
      });
    }
    return ToolResult.success(text.toString(),
        displayText: hasNameMatch
            ? '在线核验到 ${hits.length} 个 tag'
            : '在线查到 ${hits.length} 个候选 tag',
        followUpHint: jsonEncode(details));
  }
}
