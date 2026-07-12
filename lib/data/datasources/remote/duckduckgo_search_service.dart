import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html;

/// DuckDuckGo Lite 搜索结果
class SearchResult {
  final String title;
  final String url;
  final String snippet;
  const SearchResult(
      {required this.title, required this.url, required this.snippet});

  Map<String, dynamic> toJson() =>
      {'title': title, 'url': url, 'snippet': snippet};
}

/// 用 DuckDuckGo Lite（免 API key）做通用联网搜索。
/// 解析 https://lite.duckduckgo.com/lite/?q=<query> 的 HTML 表格结果。
class DuckDuckGoSearchService {
  final Dio _dio;
  DuckDuckGoSearchService(this._dio);

  Future<List<SearchResult>> search(String query, {int maxResults = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final resp = await _dio.get(
        'https://lite.duckduckgo.com/lite/',
        queryParameters: {'q': trimmed},
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8',
          },
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final data = resp.data;
      if (data is! String) return const [];
      return _parseLiteHtml(data, maxResults);
    } on DioException catch (_) {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 解析 DuckDuckGo Lite 的 HTML 表格。
  /// Lite 页面的结果在 `<table>` 内，每个结果一行：
  /// 第一列是标题链接（`<a class="result-link" href="...">标题</a>`），
  /// 第二列是描述（`<td class="result-snippet">...</td>`）。
  List<SearchResult> _parseLiteHtml(String htmlStr, int maxResults) {
    final doc = html_parser.parse(htmlStr);
    final results = <SearchResult>[];

    // Lite 版结果表格的 a 标签 class="result-link"
    final links = doc.querySelectorAll('a.result-link');
    for (final link in links) {
      if (results.length >= maxResults) break;
      final title = link.text.trim();
      var url = link.attributes['href'] ?? '';
      if (title.isEmpty || url.isEmpty) continue;
      // DDG 有时会用 redirect 跳转，提取实际 url
      url = _extractActualUrl(url);

      // snippet：往上找 td，再取下一个兄弟 td
      var snippet = '';
      html.Element? ancestor = link.parent;
      while (ancestor != null && ancestor.localName != 'td') {
        ancestor = ancestor.parent;
      }
      if (ancestor != null && ancestor.nextElementSibling != null) {
        snippet = ancestor.nextElementSibling!.text.trim();
      }

      results.add(SearchResult(title: title, url: url, snippet: snippet));
    }

    // 兜底：如果 result-link 没找到，尝试普通表格里的链接
    if (results.isEmpty) {
      final tables = doc.querySelectorAll('table');
      for (final table in tables) {
        final rows = table.querySelectorAll('tr');
        for (final row in rows) {
          if (results.length >= maxResults) break;
          final anchor = row.querySelector('a');
          if (anchor == null) continue;
          final title = anchor.text.trim();
          var url = anchor.attributes['href'] ?? '';
          if (title.isEmpty || url.isEmpty) continue;
          if (url.startsWith('//duckduckgo.com')) continue;
          url = _extractActualUrl(url);
          if (!url.startsWith('http')) continue;
          // snippet = row 内除链接外的文本
          final snippet = row.text.replaceFirst(title, '').trim();
          if (title.isNotEmpty && !title.contains('duckduckgo')) {
            results.add(SearchResult(title: title, url: url, snippet: snippet));
          }
        }
      }
    }
    return results;
  }

  /// 解析 DDG 跳转链接（如 //duckduckgo.com/l/?uddg=<encoded>）。
  String _extractActualUrl(String url) {
    if (url.startsWith('//')) url = 'https:$url';
    if (url.contains('uddg=')) {
      final u = Uri.tryParse(url);
      if (u != null) {
        final uddg = u.queryParameters['uddg'];
        if (uddg != null && uddg.isNotEmpty) return uddg;
      }
    }
    return url;
  }
}
