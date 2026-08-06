import 'package:dio/dio.dart';
import 'package:nai_huishi/data/datasources/remote/duckduckgo_search_service.dart';

/// 用 Wikipedia REST API（免 API key、纯 JSON、无反爬）做备用搜索。
/// 对角色 / 作品 / 概念类查询命中率较高，作为 DuckDuckGo 失败时的降级源。
class WikipediaSearchService {
  final Dio _dio;
  WikipediaSearchService(this._dio);

  /// Wikipedia REST API：返回 JSON。
  /// 文档：https://en.wikipedia.org/w/rest.php/v1/#/Search/search
  Future<List<SearchResult>> search(String query, {int maxResults = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final resp = await _dio.get(
        'https://en.wikipedia.org/w/rest.php/v1/search/page',
        queryParameters: {
          'q': trimmed,
          'limit': maxResults.toString(),
        },
        options: Options(
          headers: {
            'User-Agent':
                'nai-huishi-agent/1.0 (https://github.com/cocophilia093-wq/nai-huishi)',
            'Accept': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 6),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      final data = resp.data;
      if (data is! Map<String, dynamic>) return const [];
      final pages = data['pages'] as List<dynamic>?; // docs 字段已废弃，pages 是主源
      if (pages == null || pages.isEmpty) return const [];

      final results = <SearchResult>[];
      for (final page in pages) {
        if (page is! Map<String, dynamic>) continue;
        final title = (page['title'] ?? '').toString().trim();
        final key = (page['key'] ?? '').toString().trim();
        final excerpt = (page['excerpt'] ?? '').toString().trim();
        if (title.isEmpty || key.isEmpty) continue;
        // 去 HTML 标签（excerpt 含 <span class="searchmatch">）
        final cleanExcerpt = _stripHtml(excerpt);
        final url = 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(key.replaceAll(' ', '_'))}';
        results.add(SearchResult(
          title: title,
          url: url,
          snippet: cleanExcerpt,
        ));
        if (results.length >= maxResults) break;
      }
      return results;
    } on DioException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  String _stripHtml(String s) {
    return s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&quot;', '"');
  }
}
