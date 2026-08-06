import 'dart:async';
import 'dart:math';
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
///
/// 多端点轮询 + 重试 + UA 池，缓解 DDG 反爬限速问题。
class DuckDuckGoSearchService {
  final Dio _dio;
  DuckDuckGoSearchService(this._dio);

  /// DDG 搜索端点列表（轮询顺序）。html.duckduckgo.com 结构与 lite 几乎一致，复用解析器。
  static const List<String> _endpoints = [
    'https://lite.duckduckgo.com/lite/',
    'https://html.duckduckgo.com/html/',
  ];

  /// UA 池：轮换降低反爬识别
  static const List<String> _userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0',
    'Mozilla/5.0 (X11; Linux x86_64; rv:122.0) Gecko/20100101 Firefox/122.0',
  ];

  /// 每端点最大重试次数（含首次）
  static const int _maxAttemptsPerEndpoint = 3;

  /// 单次请求超时
  static const Duration _requestTimeout = Duration(seconds: 6);

  Future<List<SearchResult>> search(String query, {int maxResults = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    for (final endpoint in _endpoints) {
      final results = await _searchWithRetries(endpoint, trimmed, maxResults);
      if (results.isNotEmpty) return results;
    }
    return const [];
  }

  Future<List<SearchResult>> _searchWithRetries(
    String endpoint,
    String query,
    int maxResults,
  ) async {
    final uaIndex = Random(query.hashCode).nextInt(_userAgents.length);
    List<SearchResult> lastResults = const [];

    for (int attempt = 0; attempt < _maxAttemptsPerEndpoint; attempt++) {
      try {
        final ua = _userAgents[(uaIndex + attempt) % _userAgents.length];
        final resp = await _dio.get(
          endpoint,
          queryParameters: {'q': query},
          options: Options(
            headers: {
              'User-Agent': ua,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8',
            },
            receiveTimeout: _requestTimeout,
            sendTimeout: const Duration(seconds: 4),
          ),
        );
        final data = resp.data;
        if (data is! String) {
          // 响应非 HTML，重试
          await _backoff(attempt);
          continue;
        }
        final parsed = _parseLiteHtml(data, maxResults);
        if (parsed.isNotEmpty) return parsed;
        lastResults = parsed;
        // 解析成功但无结果：可能真无结果，也可能 HTML 改版。再试一次看是否稳定。
        if (attempt < _maxAttemptsPerEndpoint - 1) {
          await _backoff(attempt);
        }
      } on DioException {
        // 网络异常 / 403 / 429 / 超时：退避重试
        await _backoff(attempt);
      } catch (_) {
        // 其他异常：直接放弃当前端点
        break;
      }
    }
    return lastResults;
  }

  Future<void> _backoff(int attempt) async {
    // 指数退避：500ms / 1500ms / 3500ms
    final delay = Duration(milliseconds: 500 * (1 << attempt) + (attempt * 500));
    await Future.delayed(delay);
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
