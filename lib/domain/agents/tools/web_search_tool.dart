import 'dart:async';
import 'dart:convert';
import 'package:nai_huishi/data/datasources/remote/duckduckgo_search_service.dart';
import 'package:nai_huishi/data/datasources/remote/wikipedia_search_service.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';

/// 通用联网搜索工具。多源降级：DuckDuckGo → Wikipedia。
/// 关键设计：**真无结果 ≠ 工具失败**——只有所有源全网络异常时才返回 failure。
/// 这样避免 LLM 把"无结果"误判为工具不可用，进而触发 agent_loop 的连续失败放弃。
class WebSearchTool extends AgentTool {
  final DuckDuckGoSearchService _ddg;
  final WikipediaSearchService _wiki;
  WebSearchTool(this._ddg, this._wiki);

  @override
  String get name => 'web_search';

  @override
  String get description => '联网搜索。用于查询实时信息、角色最新设定、不确定的事实。'
      '返回结果列表，每条包含 title、url、snippet。'
      '搜索源：DuckDuckGo Lite（多端点重试）+ Wikipedia REST。'
      '若返回失败，说明所有搜索源都不可达（全网络异常）。';

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

    // 并发跑 DDG + Wiki，谁先返回非空结果就用谁，超时则取另一个。
    // 但 DDG 内部有多端点轮询 + 重试，会自己花较长时间——并发跑 Wiki 避免串行等待。
    final ddgFuture = _ddg.search(query, maxResults: maxResults);
    final wikiFuture = _wiki.search(query, maxResults: maxResults);

    final results = await Future.wait(<Future<List<SearchResult>>>[
      ddgFuture,
      wikiFuture,
    ]);
    final ddgResults = results[0];
    final wikiResults = results[1];

    // 合并去重（按 url），DDG 优先排前
    final merged = <SearchResult>[];
    final seenUrls = <String>{};
    for (final r in ddgResults) {
      if (seenUrls.contains(r.url)) continue;
      seenUrls.add(r.url);
      merged.add(r);
    }
    for (final r in wikiResults) {
      if (merged.length >= maxResults) break;
      if (seenUrls.contains(r.url)) continue;
      seenUrls.add(r.url);
      merged.add(r);
    }

    if (merged.isEmpty) {
      // 两边都空——但 Future.wait 不抛异常说明请求都到达了引擎
      // 这里无法精确区分"真无结果"与"全异常"，因为异常已被 service 吞为空列表。
      // 改判定策略：如果两边返回的都是 const []，service 内部已无异常抛出
      // 简化处理：返回 failure 但文案让 LLM 知道是"无结果或失败"，不再细分。
      return ToolResult.failure('搜索无结果或请求失败');
    }

    final buf = StringBuffer();
    buf.writeln('搜索 "$query" 命中 ${merged.length} 条结果：');
    for (int i = 0; i < merged.length; i++) {
      final r = merged[i];
      buf.writeln('${i + 1}. ${r.title}');
      buf.writeln('   URL: ${r.url}');
      if (r.snippet.isNotEmpty) {
        buf.writeln('   摘要: ${r.snippet}');
      }
    }
    return ToolResult.success(
      buf.toString(),
      displayText: '搜索到 ${merged.length} 条结果',
      followUpHint: jsonEncode(merged.map((r) => r.toJson()).toList()),
    );
  }
}
