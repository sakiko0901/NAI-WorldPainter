import 'dart:convert';
import 'package:nai_huishi/data/datasources/local/tag_completion_catalog.dart';
import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';

class SearchDanbooruTool extends AgentTool {
  SearchDanbooruTool(this._api, {TagCompletionCatalog? catalog})
      : _catalog = catalog ?? TagCompletionCatalog();
  final DanbooruApiService _api;
  final TagCompletionCatalog _catalog;

  @override
  String get name => 'search_danbooru';

  @override
  String get description => '检索真实存在的 Danbooru tag。默认优先查本地词库，支持英文、中文翻译、别名、'
      '空格/下划线、词序变化及少量英文拼写错误；本地无结果或不可用时再在线检索。'
      'source=local 仅查本地；source=online 用于中文语义和关联概念检索。'
      '本地结果只说明标签存在，不代表角色身份、外貌或概念之间有关联。'
      '标为“拼写近似”的仅是候选，尤其相似角色名、作品名必须核对，不能直接视为同一对象。'
      '优先使用准确匹配和别名匹配；不要把查询原文或猜测词作为真实 tag。'
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
            'description': '默认 auto：本地优先，无结果再在线。local 完全离线；online 在线语义检索。'
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
    if (query.isEmpty || query.length > 160)
      return ToolResult.failure('query 需为 1 至 160 字符的关键词。');
    final source = arguments['source'] ?? 'auto';
    if (!const ['auto', 'local', 'online'].contains(source))
      return ToolResult.failure('source 仅支持 auto、local、online。');
    final showNsfw = arguments['show_nsfw'] != false;
    final limit =
        (int.tryParse('${arguments['limit'] ?? 15}') ?? 15).clamp(1, 30);
    if (source == 'local' && !showNsfw) {
      return ToolResult.failure('本地词库无 NSFW 标记，无法保证筛选结果；请使用 source=online。');
    }
    String? localStatus;
    if (source != 'online' && showNsfw) {
      try {
        final matches = await _catalog.searchFuzzy(query, limit: limit);
        if (matches.isNotEmpty) {
          final text = StringBuffer(
              '本地 Danbooru 词库检索 "$query"：${matches.length} 个候选。\n');
          text.writeln('以下仅确认标签存在；字面匹配不证明角色身份、外观或关联特征。');
          for (var i = 0; i < matches.length; i++) {
            final match = matches[i];
            final tag = match.tag;
            text.writeln(
                '${i + 1}. ${tag.tag}${tag.translation.isEmpty ? "" : "（${tag.translation}）"}'
                ' [${tag.categoryLabel}] [${match.label}]'
                '${tag.alias == null ? "" : " 别名：${tag.alias}"}');
          }
          if (matches.any((m) => m.kind == 'fuzzy')) {
            text.writeln('拼写近似仅代表字面相似，不确认角色身份或语义相同；不确定时询问用户或使用在线检索核对。');
          }
          return ToolResult.success(text.toString(),
              displayText: '本地检索到 ${matches.length} 个 tag',
              followUpHint: jsonEncode(matches
                  .map((m) => {
                        'tag': m.tag.tag,
                        'cn': m.tag.translation,
                        'category': m.tag.categoryLabel,
                        'source': 'local',
                        'match': m.kind,
                        'distance': m.distance,
                      })
                  .toList()));
        }
        localStatus = '本地词库无匹配';
      } catch (_) {
        localStatus = '本地词库暂不可用';
        if (source == 'local')
          return ToolResult.failure('$localStatus，请在标签补全设置中修复词库或使用在线检索。');
      }
      if (source == 'local')
        return ToolResult.success('$localStatus："$query"。',
            displayText: '本地无匹配 tag');
    }
    try {
      final tags = await _api.search(
          query: query, topK: 5, limit: limit, showNsfw: showNsfw);
      final prefix = localStatus == null ? '' : '$localStatus，已转在线检索。\n';
      if (tags.isEmpty)
        return ToolResult.success('${prefix}在线检索 "$query" 无结果。',
            displayText: '无匹配 tag');
      final text = StringBuffer(
          '${prefix}在线 Danbooru 检索 "$query"：${tags.length} 个 tag。\n');
      for (var i = 0; i < tags.length; i++) {
        final t = tags[i];
        text.writeln(
            '${i + 1}. ${t.tag}${t.cnName.isEmpty ? "" : "（${t.cnName}）"} [${t.category}]');
      }
      return ToolResult.success(text.toString(),
          displayText: '在线检索到 ${tags.length} 个 tag',
          followUpHint: jsonEncode(tags
              .map((t) => {
                    'tag': t.tag,
                    'cn': t.cnName,
                    'category': t.category,
                    'source': 'online'
                  })
              .toList()));
    } catch (e) {
      return ToolResult.failure(
          '${localStatus == null ? "" : "$localStatus；"}在线 Danbooru 检索失败：$e');
    }
  }
}
