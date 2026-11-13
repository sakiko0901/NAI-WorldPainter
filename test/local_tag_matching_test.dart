import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:nai_huishi/data/datasources/local/tag_completion_catalog.dart';
import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/domain/agents/tools/search_danbooru_tool.dart';
import 'package:nai_huishi/domain/entities/danbooru_tag.dart';
import 'package:nai_huishi/domain/entities/tag_completion.dart';
import 'package:nai_huishi/domain/entities/tag_search_match.dart';
import 'package:nai_huishi/domain/services/local_tag_matching.dart';

class _Catalog extends TagCompletionCatalog {
  List<TagSearchMatch> result = [];
  bool fails = false;
  int calls = 0;
  @override
  Future<List<TagSearchMatch>> searchFuzzy(String query,
      {int limit = 15}) async {
    calls++;
    if (fails) throw StateError('unavailable');
    return result.take(limit).toList();
  }
}

class _Api extends DanbooruApiService {
  int calls = 0;
  bool? nsfw;
  @override
  Future<List<DanbooruTag>> search(
      {required String query,
      int topK = 5,
      int limit = 30,
      bool showNsfw = false,
      String? customBaseUrl,
      CancelToken? cancelToken}) async {
    calls++;
    nsfw = showNsfw;
    return [const DanbooruTag(tag: 'blue_hair')];
  }
}

void main() {
  test(
      'bounded edit distance includes transposition without relaxing short inputs',
      () {
    expect(tagEditDistance('blue', 'bule', 1), 1);
    expect(tagEditDistance('blue', 'lue', 1), 1);
    expect(tagEditDistance('blue', 'bluwe', 1), 1);
    expect(tagEditDistance('blue', 'red', 1), greaterThan(1));
    expect(tagEditDistance('', 'blue', 1), greaterThan(1));
    expect(tagSearchPrefixes('bl'), {'bl'});
    expect(tagSearchPrefixes('xahida'), contains('nahi'));
  });
  test('exact and aliases outrank popular fuzzy matches, results deduplicate',
      () {
    Map<String, Object?> row(String name, String term, int kind, int count) => {
          'name': name,
          'term': term,
          'kind': kind,
          'post_count': count,
          'category': 0,
          'translation': '',
        };
    final matches = rankLocalTagCandidates({
      'query': 'blue_hair',
      'limit': 10,
      'rows': [
        row('blue_hairs', 'blue_hairs', 0, 1000000),
        row('blue_hair', 'blue_hair', 0, 1),
        row('blue_hair', 'hair', 2, 1),
        row('another_canonical', 'blue_hair', 1, 10),
      ]
    });
    expect(matches.map((m) => m.kind), ['exact', 'alias', 'prefix']);
    expect(matches.map((m) => m.tag.tag).toSet().length, matches.length);
  });
  test('local candidates are labeled and do not trigger remote requests',
      () async {
    final local = _Catalog()
      ..result = [
        const TagSearchMatch(TagCompletion(tag: 'blue_hair'), 'fuzzy',
            distance: 1)
      ];
    final api = _Api();
    final result = await SearchDanbooruTool(api, catalog: local)
        .call({'query': 'bule hair'});
    expect(result.success, isTrue);
    expect(result.text, contains('拼写近似'));
    expect(result.text, contains('blue_hair'));
    expect(api.calls, 0);
  });
  test(
      'auto falls back for missing or broken catalog; explicit local never connects',
      () async {
    final local = _Catalog();
    final api = _Api();
    final tool = SearchDanbooruTool(api, catalog: local);
    expect((await tool.call({'query': 'missing'})).success, isTrue);
    expect(api.calls, 1);
    local.fails = true;
    expect((await tool.call({'query': 'missing'})).text, contains('本地词库暂不可用'));
    expect(api.calls, 2);
    expect((await tool.call({'query': 'missing', 'source': 'local'})).success,
        isFalse);
    expect(api.calls, 2);
    local.fails = false;
    expect((await tool.call({'query': 'missing', 'source': 'local'})).text,
        contains('无匹配'));
    expect(api.calls, 2);
  });
  test('online mode and NSFW filtering do not pretend local catalog can filter',
      () async {
    final local = _Catalog();
    final api = _Api();
    final tool = SearchDanbooruTool(api, catalog: local);
    await tool.call({'query': 'test', 'source': 'online'});
    expect(local.calls, 0);
    await tool.call({'query': 'test', 'show_nsfw': false});
    expect(local.calls, 0);
    expect(api.nsfw, isFalse);
    expect(
        (await tool
                .call({'query': 'test', 'source': 'local', 'show_nsfw': false}))
            .success,
        isFalse);
    expect(api.calls, 2);
  });
}
