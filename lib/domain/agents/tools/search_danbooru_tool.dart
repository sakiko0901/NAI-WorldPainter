import 'dart:convert';
import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/danbooru_tag.dart';

/// 搜索 Danbooru 真实 tag 池（单次直接检索版）。
/// 直接调 DanbooruApiService.search，绕过 ExtractedKeywords 中间层。
class SearchDanbooruTool extends AgentTool {
  final DanbooruApiService _api;
  SearchDanbooruTool(this._api);

  @override
  String get name => 'search_danbooru';

  @override
  String get description =>
      '搜索 Danbooru 真实 tag 列表。用户提及角色/画风/场景时调用，返回真实存在的 tag（含中文名、热度）。'
      '**不要凭空创造 tag**，所有 tag 必须来自此工具的检索结果或用户本地记忆。'
      'query 可用中文或英文，Danbooru 服务支持中文语义检索。'
      '\n\n【节流提示】单次检索一个角色名/画风名/场景名即可覆盖该概念的常见特征 tag（发色/瞳色/服装/姿势/场景元素等），'
      '不需要为每个细节单独搜。只有切换到不同角色、不同场景、不同画风时才需要再次调用。'
      '例如"纳西妲在森林里看书"只需搜一次"纳西妲"——返回的 tag 池里会包含她的外貌特征、森林场景元素，无需再搜"green hair"或"forest"。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词，如"纳西妲"、"森林夜景"、"skirt"。',
          },
          'limit': {
            'type': 'integer',
            'description': '返回结果数，默认 15，最大 30',
          },
          'show_nsfw': {
            'type': 'boolean',
            'description': '是否包含 NSFW tag，默认 true',
          },
        },
        'required': ['query'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final query = (arguments['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return ToolResult.failure('query 不能为空');
    }
    final showNsfw = (arguments['show_nsfw'] as bool?) ?? true;
    int limit = 15;
    final l = arguments['limit'];
    if (l is int) {
      limit = l.clamp(1, 30);
    } else if (l is String) {
      final parsed = int.tryParse(l);
      if (parsed != null) limit = parsed.clamp(1, 30);
    }
    try {
      final tags = await _api.search(
        query: query,
        topK: 5,
        limit: limit,
        showNsfw: showNsfw,
      );
      if (tags.isEmpty) {
        return ToolResult.success(
          'Danbooru 检索 "$query" 无结果。',
          displayText: '无匹配 tag',
        );
      }
      final buf = StringBuffer();
      buf.writeln('Danbooru 检索 "$query" 命中 ${tags.length} 个真实 tag：');
      for (int i = 0; i < tags.length; i++) {
        final t = tags[i];
        final name = t.tag.replaceAll('_', ' ');
        final cn = t.cnName.isNotEmpty ? '（${t.cnName}）' : '';
        final cat = t.category.isNotEmpty ? ' [${t.category}]' : '';
        buf.writeln('${i + 1}. $name$cn$cat');
      }
      return ToolResult.success(
        buf.toString(),
        displayText: '检索到 ${tags.length} 个 Danbooru tag',
        followUpHint: jsonEncode(tags
            .map((t) => {
                  'tag': t.tag,
                  'cn': t.cnName,
                  'category': t.category,
                })
            .toList()),
      );
    } catch (e) {
      return ToolResult.failure('Danbooru 检索失败：$e');
    }
  }
}

// 防止 DanbooruTag import 未使用警告
// ignore: unused_element
void _useDanbooruTag(DanbooruTag _) {}
