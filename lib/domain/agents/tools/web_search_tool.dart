import 'dart:convert';
import 'package:nai_huishi/data/datasources/remote/duckduckgo_search_service.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';

/// 通用联网搜索工具。用 DuckDuckGo Lite（免 API key）。
class WebSearchTool extends AgentTool {
  final DuckDuckGoSearchService _service;
  WebSearchTool(this._service);

  @override
  String get name => 'web_search';

  @override
  String get description => '使用 DuckDuckGo Lite 做通用联网搜索。用于查询实时信息、角色最新设定、不确定的事实。'
      '返回结果列表（最多 max_results 条），每条包含 title、url、snippet。'
      '注意：DDG 可能因为反爬限速失败，失败时返回空列表，应该告知用户搜索失败。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词，建议用英文或主题词',
          },
          'max_results': {
            'type': 'integer',
            'description': '返回结果数上限，默认 5，最大 10',
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
    int maxResults = 5;
    final m = arguments['max_results'];
    if (m is int) {
      maxResults = m.clamp(1, 10);
    } else if (m is String) {
      final parsed = int.tryParse(m);
      if (parsed != null) maxResults = parsed.clamp(1, 10);
    }
    final results = await _service.search(query, maxResults: maxResults);
    if (results.isEmpty) {
      return ToolResult.failure('搜索无结果或请求失败');
    }
    final buf = StringBuffer();
    buf.writeln('搜索 "$query" 命中 ${results.length} 条结果：');
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      buf.writeln('${i + 1}. ${r.title}');
      buf.writeln('   URL: ${r.url}');
      if (r.snippet.isNotEmpty) {
        buf.writeln('   摘要: ${r.snippet}');
      }
    }
    return ToolResult.success(
      buf.toString(),
      displayText: '搜索到 ${results.length} 条结果',
      followUpHint: jsonEncode(results.map((r) => r.toJson()).toList()),
    );
  }
}
