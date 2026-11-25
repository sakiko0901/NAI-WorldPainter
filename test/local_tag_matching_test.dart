import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
  List<VerifiedDanbooruTag> result = const [
    VerifiedDanbooruTag(DanbooruTag(tag: 'blue_hair', count: 20),
        VerifiedDanbooruMatch.semantic)
  ];
  bool fails = false;
  int calls = 0;
  bool? nsfw;
  @override
  Future<List<VerifiedDanbooruTag>> searchVerified(
      {required String query, int limit = 15, bool showNsfw = true}) async {
    calls++;
    nsfw = showNsfw;
    if (fails) throw StateError('offline');
    return result;
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
  test('explicit local labels spelling candidates and never connects',
      () async {
    final local = _Catalog()
      ..result = [
        const TagSearchMatch(TagCompletion(tag: 'blue_hair'), 'fuzzy',
            distance: 1)
      ];
    final api = _Api();
    final result = await SearchDanbooruTool(api, catalog: local)
        .call({'query': 'bule hair', 'source': 'local'});
    expect(result.success, isTrue);
    expect(result.text, contains('拼写近似'));
    expect(result.text, contains('blue_hair'));
    expect(api.calls, 0);
  });
  test('auto uses a local exact name, matching alias or full translation',
      () async {
    final local = _Catalog();
    final api = _Api();
    final tool = SearchDanbooruTool(api, catalog: local);
    final cases = [
      (
        'blue hair',
        const TagSearchMatch(TagCompletion(tag: 'blue_hair'), 'exact')
      ),
      (
        'aqua hair',
        const TagSearchMatch(
            TagCompletion(tag: 'blue_hair', alias: 'aqua_hair'), 'alias')
      ),
      (
        '纳西妲（原神）',
        const TagSearchMatch(
            TagCompletion(
                tag: 'nahida_(genshin_impact)', translation: '纳西妲 (原神)'),
            'translation')
      ),
    ];
    for (final (query, match) in cases) {
      local.result = [match];
      final toolResult = await tool.call({'query': query});
      expect(toolResult.success, isTrue);
      expect(toolResult.text, contains(match.tag.tag));
      final hit = (jsonDecode(toolResult.followUpHint!) as List).single;
      expect(hit, containsPair('source', 'local'));
      expect(hit, containsPair('candidate', false));
    }
    expect(api.calls, 0);
  });
  test(
      'auto verifies only weak local matches and preserves candidates on failure',
      () async {
    final local = _Catalog()
      ..result = const [
        TagSearchMatch(TagCompletion(tag: 'shun_(blue_archive)'), 'fuzzy',
            distance: 2),
      ];
    final api = _Api()
      ..result = const [
        VerifiedDanbooruTag(
            DanbooruTag(tag: 'shunling_(blue_archive)', count: 2488),
            VerifiedDanbooruMatch.exact)
      ];
    final tool = SearchDanbooruTool(api, catalog: local);
    final arguments = {'query': 'shunling_(blue_archive)'};
    final verified = await tool.call(arguments);
    expect(verified.text, contains('官方准确匹配'));
    expect(verified.text, contains('shunling_(blue_archive)'));
    expect(api.calls, 1);

    api.fails = true;
    final fallback = await tool.call(arguments);
    expect(fallback.success, isTrue);
    expect(
        fallback.text, contains('在线 Danbooru 核验「shunling_(blue_archive)」失败'));
    expect(fallback.text, contains('shun_(blue_archive)'));
    expect(fallback.text, contains('拼写近似（候选）'));
    expect(
        (jsonDecode(fallback.followUpHint!) as List).single,
        allOf(
            containsPair('source', 'local'), containsPair('candidate', true)));

    api.fails = false;
    api.result = [];
    final empty = await tool.call(arguments);
    expect(empty.text, contains('未核验到匹配标签'));
    expect(empty.text, contains('shun_(blue_archive)'));
    expect(api.calls, 3);
  });
  test('partial translation and ambiguous exact names trigger online lookup',
      () async {
    final local = _Catalog();
    final api = _Api();
    final tool = SearchDanbooruTool(api, catalog: local);
    local.result = const [
      TagSearchMatch(
          TagCompletion(tag: 'shun_(blue_archive)', translation: '春原瞬 (蔚蓝档案)'),
          'translation'),
    ];
    expect((await tool.call({'query': '春原瞬'})).text, contains('在线'));
    local.result = const [
      TagSearchMatch(
          TagCompletion(tag: 'red_eyes', translation: '红瞳'), 'translation'),
      TagSearchMatch(
          TagCompletion(tag: 'red_pupils', translation: '红瞳'), 'translation'),
    ];
    expect((await tool.call({'query': '红瞳', 'limit': 1})).text, contains('在线'));
    local.result = const [
      TagSearchMatch(
          TagCompletion(tag: 'alice_(series_a)', alias: 'alice'), 'alias'),
      TagSearchMatch(
          TagCompletion(tag: 'alice_(series_b)', alias: 'alice'), 'alias'),
    ];
    expect(
        (await tool.call({'query': 'alice', 'limit': 1})).text, contains('在线'));
    expect(api.calls, 3);
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
