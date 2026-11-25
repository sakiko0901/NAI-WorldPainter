import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/domain/agents/tools/search_danbooru_tool.dart';

const _officialHost = 'danbooru.donmai.us';
const _hfHost = 'sakizuki-danboorusearch.hf.space';
const _modelScopeHost = 'sakizuki-danboorusearchonline.ms.show';
const _renamedTag = 'shunling_(blue_archive)';
const _oldTag = 'shun_(small)_(blue_archive)';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(Object body, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

Map<String, Object> _officialTag(String name,
        {int count = 2488, int category = 4, bool deprecated = false}) =>
    {
      'name': name,
      'category': category,
      'post_count': count,
      'is_deprecated': deprecated,
    };

Map<String, String> _alias(String from, String to,
        {String status = 'active'}) =>
    {'antecedent_name': from, 'consequent_name': to, 'status': status};

Map<String, dynamic> _semanticTag(String name, String cn,
        {String nsfw = '0'}) =>
    {'tag': name, 'cn_name': cn, 'category': 'ai_generated', 'nsfw': nsfw};

DanbooruApiService _service(_Adapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  return DanbooruApiService(dio: dio);
}

String? _requestedNames(RequestOptions request) =>
    request.uri.queryParameters['search[name_normalize]'];

void main() {
  test('online exact spelling uses official counts and skips semantic mirrors',
      () async {
    final adapter = _Adapter((request) {
      expect(request.uri.host, _officialHost);
      expect(request.method, 'GET');
      expect(request.uri.path, '/tags.json');
      expect(_requestedNames(request), _renamedTag);
      expect(request.headers['User-Agent'], 'NAI-WorldPainter tag lookup');
      expect(request.connectTimeout, const Duration(seconds: 3));
      expect(request.receiveTimeout, const Duration(seconds: 3));
      return _response([
        _officialTag('shun_(blue_archive)'),
        _officialTag(_renamedTag),
      ]);
    });
    final tool = SearchDanbooruTool(_service(adapter));
    final result = await tool.call({
      'query': r'Shunling \(Blue Archive\)',
      'source': 'online',
    });
    expect(result.success, isTrue);
    expect(result.text, contains('官方准确匹配'));
    expect(result.text, contains('2488 帖'));
    expect((jsonDecode(result.followUpHint!) as List).single,
        containsPair('tag', _renamedTag));
    expect(adapter.requests, hasLength(1));
  });

  test(
      'active alias resolves the zero-count historical name to its canonical tag',
      () async {
    final adapter = _Adapter((request) {
      switch (request.uri.path) {
        case '/tag_aliases.json':
          expect(request.uri.queryParametersAll['search[antecedent_name][]'],
              [_oldTag]);
          expect(request.uri.queryParameters['search[status]'], 'active');
          return _response([
            _alias('other_name', 'other_tag'),
            _alias(_oldTag, 'wrong_tag', status: 'pending'),
            _alias(_oldTag, _renamedTag),
          ]);
        case '/tags.json':
          return _response([
            if (_requestedNames(request) == _oldTag)
              _officialTag(_oldTag, count: 0),
            if (_requestedNames(request) == _renamedTag)
              _officialTag(_renamedTag),
          ]);
        default:
          throw StateError('Unexpected request ${request.uri}');
      }
    });
    final result = await SearchDanbooruTool(_service(adapter))
        .call({'query': _oldTag, 'source': 'online'});
    expect(result.success, isTrue);
    expect(result.text, contains('官方有效别名'));
    expect(
        (jsonDecode(result.followUpHint!) as List).single,
        allOf(
            containsPair('tag', _renamedTag),
            containsPair('matched_term', _oldTag),
            containsPair('verified_by', 'Danbooru')));
    expect(adapter.requests, hasLength(3));
  });

  test('unqualified official character results remain distinct candidates',
      () async {
    const variant = 'shunling_(swimsuit)_(blue_archive)';
    final adapter = _Adapter((request) {
      if (request.uri.queryParameters['search[name_matches]'] ==
          'shunling_(*)') {
        return _response([_officialTag(_renamedTag), _officialTag(variant)]);
      }
      expect(request.uri.host, _officialHost);
      return _response([]);
    });
    final result = await SearchDanbooruTool(_service(adapter))
        .call({'query': 'shunling', 'source': 'online'});
    expect(result.text, contains('仅确认候选标签本身存在'));
    expect(result.text, contains('带限定词的名称候选'));
    final rows = (jsonDecode(result.followUpHint!) as List).cast<Map>();
    expect(rows.map((row) => row['tag']), [_renamedTag, variant]);
    expect(rows.map((row) => row['match']), everyElement('qualified'));
  });

  test('exact localized Wiki name is linked only to a verified official tag',
      () async {
    final adapter = _Adapter((request) {
      if (request.uri.path == '/wiki_pages.json') {
        expect(request.uri.queryParameters['search[other_names_match]'],
            '春原瞬（幼女）');
        return _response([
          {
            'title': 'shun_(blue_archive)',
            'other_names': ['春原瞬']
          },
          {
            'title': _renamedTag,
            'other_names': ['春原瞬(幼女)']
          },
        ]);
      }
      expect(_requestedNames(request), _renamedTag);
      return _response([_officialTag(_renamedTag)]);
    });
    final result = await SearchDanbooruTool(_service(adapter))
        .call({'query': '春原瞬（幼女）', 'source': 'online'});
    expect(result.text, contains('官方 Wiki 名称记录'));
    expect(result.text, contains('春原瞬(幼女)'));
    expect((jsonDecode(result.followUpHint!) as List).single,
        containsPair('tag', _renamedTag));
    expect(adapter.requests, hasLength(2));
  });

  test(
      'semantic mirror supplies bilingual candidates that require official verification',
      () async {
    final adapter = _Adapter((request) {
      if (request.uri.host == _hfHost) {
        expect(request.data, containsPair('query', 'bule hair'));
        return _response({
          'results': [
            _semanticTag('Blue hair', '蓝发'),
            _semanticTag('blue_hair', '重复译名'),
            _semanticTag('blonde', '金发'),
            _semanticTag('fictional_tag', '未经核对'),
            _semanticTag('deprecated_hair', '弃用条目'),
          ]
        });
      }
      final names = _requestedNames(request)?.split(',') ?? const [];
      if (request.uri.path == '/tag_aliases.json') {
        final names =
            request.uri.queryParametersAll['search[antecedent_name][]']!;
        if (!names.contains('blonde')) return _response([]);
        return _response([_alias('blonde', 'blonde_hair')]);
      }
      return _response([
        if (names.contains('blue_hair'))
          _officialTag('blue_hair', category: 0, count: 300),
        if (names.contains('blonde_hair'))
          _officialTag('blonde_hair', category: 0, count: 500),
        if (names.contains('deprecated_hair'))
          _officialTag('deprecated_hair', deprecated: true),
      ]);
    });
    final result = await SearchDanbooruTool(_service(adapter))
        .call({'query': 'bule hair', 'source': 'online'});
    expect(result.success, isTrue);
    expect(result.text, contains('未核验到原查询的准确名称或别名'));
    expect(result.text, contains('blue_hair（蓝发）'));
    expect(result.text, contains('blonde_hair（金发）'));
    expect(result.text, isNot(contains('fictional_tag')));
    expect(result.text, isNot(contains('deprecated_hair')));
    final rows = (jsonDecode(result.followUpHint!) as List).cast<Map>();
    expect(rows, hasLength(2));
    expect(
        rows.first,
        allOf(
            containsPair('source', 'online'),
            containsPair('match', 'semantic'),
            containsPair('translation_source', 'Hugging Face'),
            containsPair('verified_by', 'Danbooru'),
            containsPair('category', 'General'),
            containsPair('post_count', 300)));
  });

  test(
      'filtered lookup verifies only candidates from the filtered semantic service',
      () async {
    final adapter = _Adapter((request) {
      if (request.method == 'POST') {
        expect(request.data, containsPair('show_nsfw', false));
        return _response({
          'results': [
            _semanticTag('blue_hair', '蓝发'),
            _semanticTag('blocked_1', '', nsfw: '1'),
            _semanticTag('blocked_explicit', '', nsfw: 'explicit'),
          ]
        });
      }
      expect(_requestedNames(request), 'blue_hair,official_unrated');
      return _response(
          [_officialTag('blue_hair'), _officialTag('official_unrated')]);
    });
    final hits = await _service(adapter)
        .searchVerified(query: 'official_unrated', showNsfw: false);
    expect(adapter.requests.first.method, 'POST');
    expect(hits.single.tag.tag, 'blue_hair');
    expect(hits.single.match, VerifiedDanbooruMatch.semantic);
  });

  test(
      'semantic failover preserves provider provenance and verifies surviving candidates',
      () async {
    final adapter = _Adapter((request) {
      if (request.uri.host == _hfHost) return _response({}, status: 503);
      if (request.uri.host == _modelScopeHost) {
        return _response({
          'results': [_semanticTag('blue_hair', '蓝发')]
        });
      }
      return _response([_officialTag('blue_hair', category: 0)]);
    });
    final hits = await _service(adapter)
        .searchVerified(query: 'blue hair', showNsfw: false);
    expect(adapter.requests.map((request) => request.uri.host),
        [_hfHost, _modelScopeHost, _officialHost]);
    expect(hits.single.match, VerifiedDanbooruMatch.exact);
    expect(hits.single.semanticProvider, 'ModelScope');
  });

  test(
      'official service retries a temporary 503 once and exposes a failed lookup',
      () async {
    final adapter = _Adapter((request) => _response({}, status: 503));
    final result = await SearchDanbooruTool(_service(adapter))
        .call({'query': _renamedTag, 'source': 'online'});
    expect(result.success, isFalse);
    expect(result.text, contains('在线 Danbooru 核验「$_renamedTag」失败'));
    expect(adapter.requests.map((request) => request.uri.host),
        [_officialHost, _officialHost]);
  });
}
