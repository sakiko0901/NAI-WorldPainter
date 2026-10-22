import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/gallery/gallery_api_adapter.dart';
import 'package:nai_huishi/data/datasources/remote/gallery/gallery_http.dart';
import 'package:nai_huishi/domain/entities/online_gallery.dart';

void main() {
  group('GalleryApiAdapter JSON protocols', () {
    test('builds source-specific Danbooru and Safebooru queries', () async {
      final fixture = _Fixture((request) {
        if (request.uri.path == '/counts/posts.json') {
          return _Reply.json({
            'counts': {'posts': 30}
          });
        }
        if (request.uri.path == '/posts.json') {
          return _Reply.json([
            _danbooruPost(17, rating: 'g'),
          ]);
        }
        return _Reply.notFound();
      });
      final adapter = GalleryApiAdapter(_http(fixture));

      final danbooru = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.danbooru,
        query: 'blue_eyes rating:q order:id_asc',
        sort: 'score',
        timeRange: 'week',
        page: 2,
        pageSize: 12,
        safeOnly: true,
      ));
      final danbooruRequest = fixture.requests.firstWhere(
        (request) =>
            request.uri.host == 'danbooru.donmai.us' &&
            request.uri.path == '/posts.json',
      );
      expect(danbooruRequest.uri.queryParameters['tags'],
          'blue_eyes rating:g order:score age:<7d');
      expect(danbooruRequest.uri.queryParameters['page'], '2');
      expect(danbooru.total, 30);
      expect(danbooru.hasMore, isTrue);
      expect(danbooru.items.single.source, OnlineGallerySource.danbooru);
      expect(danbooru.items.single.tags['artists'], ['sample_artist']);
      expect(danbooru.items.single.cover.previewUrl,
          'https://cdn.donmai.us/preview/17.jpg');

      final safebooru = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.safebooru,
        query: 'cat rating:e',
        sort: 'newest',
        safeOnly: true,
      ));
      final safeRequest = fixture.requests.firstWhere(
        (request) =>
            request.uri.host == 'safebooru.donmai.us' &&
            request.uri.path == '/posts.json',
      );
      expect(safeRequest.uri.queryParameters['tags'],
          'cat rating:g order:id_desc');
      expect(safebooru.items.single.source, OnlineGallerySource.safebooru);
      expect(safebooru.items.single.sourceUrl,
          'https://safebooru.donmai.us/posts/17');
    });

    test('uses only injected Gelbooru credentials and its DAPI page protocol',
        () async {
      final missingFixture = _Fixture((_) => _Reply.json({'post': []}));
      final missingAdapter = GalleryApiAdapter(_http(missingFixture));
      await expectLater(
        missingAdapter.search(const OnlineGalleryQuery(
          source: OnlineGallerySource.gelbooru,
        )),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('图库设置'),
        )),
      );
      expect(missingFixture.requests, isEmpty);

      final fixture = _Fixture((request) {
        if (request.uri.path == '/index.php') {
          return _Reply.json({
            '@attributes': {'count': '8'},
            'post': [
              {
                'id': '91',
                'owner': 'fixture-author',
                'rating': 'general',
                'tags': 'blue_eyes sample_artist',
                'preview_url': 'https://gelbooru.com/thumbnails/91.jpg',
                'sample_url': 'https://img.gelbooru.com/sample/91.jpg',
                'file_url': 'https://img.gelbooru.com/images/91.jpg',
                'width': '640',
                'height': '480',
              }
            ],
          });
        }
        return _Reply.notFound();
      });
      final adapter = GalleryApiAdapter(
        _http(fixture),
        gelbooruCredentials: () async => const OnlineGalleryCredentials(
          userId: '12345',
          apiKey: 'fixture-key-not-secret',
        ),
      );
      final page = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.gelbooru,
        query: 'blue_eyes',
        page: 3,
        pageSize: 12,
        safeOnly: true,
      ));

      final request = fixture.requests.single;
      expect(request.uri.queryParameters['page'], 'dapi');
      expect(request.uri.queryParameters['q'], 'index');
      expect(request.uri.queryParameters['pid'], '2');
      expect(request.uri.queryParameters['tags'],
          'blue_eyes rating:general sort:score:desc');
      expect(request.uri.queryParameters['api_key'], 'fixture-key-not-secret');
      expect(request.uri.queryParameters['user_id'], '12345');
      expect(page.total, 8);
      expect(page.items.single.source, OnlineGallerySource.gelbooru);
      expect(page.items.single.media.single.downloadUrl,
          'https://img.gelbooru.com/images/91.jpg');
    });

    test('uses Civitai metadata and opaque cursors, then double-checks safety',
        () async {
      final fixture = _Fixture((request) {
        if (request.uri.path != '/api/v1/images') return _Reply.notFound();
        if (request.uri.queryParameters['cursor'] == 'opaque+/cursor=') {
          return _Reply.json({
            'items': [],
            'metadata': {'nextCursor': 'still-more', 'nextPage': 'ignored'},
          });
        }
        return _Reply.json({
          'items': [
            _civitaiImage(31),
            _civitaiImage(32, nsfw: true),
            _civitaiImage(33, url: 'https://evil.example/image.jpg'),
            _civitaiImage(34, type: 'video'),
            _civitaiImage(36, url: '/relative-image.jpg'),
            _civitaiImage(37, url: 'https:image.civitai.com/invalid.jpg'),
            _civitaiImage(
              35,
              url: 'https://image.civitai.com:444/images/35.jpeg',
            ),
          ],
          'metadata': {'nextCursor': 'opaque+/cursor=', 'nextPage': 'ignored'},
        });
      });
      final adapter = GalleryApiAdapter(_http(fixture));
      final first = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.civitai,
        query: '@alice',
        sort: 'favorites',
        timeRange: 'month',
        pageSize: 24,
        safeOnly: true,
      ));
      final firstRequest = fixture.requests.first;
      expect(firstRequest.uri.queryParameters['withMeta'], 'true');
      expect(firstRequest.uri.queryParameters['type'], 'image');
      expect(firstRequest.uri.queryParameters['username'], 'alice');
      expect(firstRequest.uri.queryParameters['sort'], 'Most Collected');
      expect(firstRequest.uri.queryParameters['period'], 'Month');
      expect(firstRequest.uri.queryParameters['browsingLevel'], '1');
      expect(firstRequest.uri.queryParameters.containsKey('prompt'), isFalse);
      expect(first.items.map((item) => item.id), ['31']);
      expect(first.nextCursor, 'opaque+/cursor=');
      expect(first.hasMore, isTrue);

      final next = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.civitai,
        page: 2,
        cursor: 'opaque+/cursor=',
        safeOnly: true,
      ));
      final nextRequest = fixture.requests.last;
      expect(nextRequest.uri.queryParameters['cursor'], 'opaque+/cursor=');
      expect(nextRequest.uri.queryParameters.containsKey('page'), isFalse);
      expect(next.items, isEmpty);
      expect(next.hasMore, isTrue);
      expect(next.nextCursor, 'still-more');

      final unsafeFixture = _Fixture((_) => _Reply.json({
            'items': [_civitaiImage(31, nsfwLevel: 'Soft')],
          }));
      await expectLater(
        GalleryApiAdapter(_http(unsafeFixture)).detail(
          const OnlineGalleryItem(
            source: OnlineGallerySource.civitai,
            id: '31',
            title: 'unsafe fixture',
          ),
          safeOnly: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(unsafeFixture.requests.single.uri.queryParameters['browsingLevel'],
          '1');
    });

    test(
        'uses AI TAG search and monthly rank APIs and hydrates detail metadata',
        () async {
      final fixture = _Fixture((request) {
        switch (request.uri.path) {
          case '/api/ai_works_search':
            return _Reply.json({
              'total': 70,
              'items': [
                for (var id = 1; id <= 60; id++)
                  {
                    'id': id,
                    'userId': 'artist-$id',
                    'caption': '<b>caption $id</b>',
                    'tags': '["blue sky", "sample"]',
                    'create_date': '2026-10-01',
                    'image_count': 2,
                  },
              ],
            });
          case '/api/rank/monthly/fixed':
            return _Reply.json({'total': 0, 'items': []});
          case '/api/work/48':
            return _Reply.json({
              'work': {
                'id': 48,
                'userId': 'fixture artist',
                'title': 'detail title',
                'caption': 'detail caption',
                'tags': ['sky'],
              },
              'images': [
                {
                  'id': 480,
                  'author_id': 'author id',
                  'image_type': 'illustration',
                  'file_name': 'blue sky',
                  'prompt_text': '',
                  'ai_json': jsonEncode({
                    'prompt': {
                      'positive': 'soft blue sky',
                      'negative': 'blurry'
                    },
                  }),
                },
              ],
            });
          case '/api/config':
            return _Reply.json(
                {'asset_base_url': 'https://assets.aitag.example/public'});
          default:
            return _Reply.notFound();
        }
      });
      final adapter = GalleryApiAdapter(_http(fixture));
      final page = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.aitag,
        query: 'blue sky',
        sort: 'default',
        page: 2,
        pageSize: 24,
        safeOnly: true,
      ));
      final searchRequest = fixture.requests.single;
      expect(searchRequest.uri.path, '/api/ai_works_search');
      expect(searchRequest.uri.queryParameters['q'], 'blue sky');
      expect(searchRequest.uri.queryParameters['sort'], 'new');
      expect(searchRequest.uri.queryParameters['time_range'], 'all');
      expect(searchRequest.headers['referer'], 'https://aitag.win/');
      expect(page.total, 70);
      expect(page.items.map((item) => item.id),
          List.generate(24, (index) => '${index + 25}'));
      expect(page.items.first.media, isEmpty);
      expect(page.items.first.metadata['safeOnly'], isTrue);
      expect(page.items.first.tags['general'], ['blue sky', 'sample']);

      await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.aitag,
        sort: 'newest',
        timeRange: 'y2026',
      ));
      expect(fixture.requests.last.uri.queryParameters['time_range'], 'y2026');

      await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.aitag,
        sort: 'favorites',
        timeRange: 'm2026-01',
      ));
      final monthlyRequest = fixture.requests.last;
      expect(monthlyRequest.uri.path, '/api/rank/monthly/fixed');
      expect(monthlyRequest.uri.queryParameters['month'], '2026-01');
      expect(monthlyRequest.uri.queryParameters['time_range'], isNull);

      final summary = page.items.singleWhere((item) => item.id == '48');
      final detailed = await adapter.detail(summary);
      expect(detailed.title, 'detail title');
      expect(detailed.prompt, 'soft blue sky');
      expect(detailed.negativePrompt, 'blurry');
      expect(detailed.media.single.previewUrl,
          'https://assets.aitag.example/public/illustration/author%20id/blue%20sky.webp');
      expect(detailed.metadata['safeOnly'], isTrue);
      expect(
        fixture.requests
            .where((request) => request.uri.path == '/api/work/48')
            .single
            .headers['referer'],
        'https://aitag.win/',
      );
    });

    test('accepts only AI TAG validated empty-result 404 responses', () async {
      final emptyFixture = _Fixture((_) => const _Reply(
            null,
            404,
            'application/json; charset=utf-8',
            rawBody: '{"items":[],"total":0}',
          ));
      final emptyPage = await GalleryApiAdapter(_http(emptyFixture)).search(
        const OnlineGalleryQuery(source: OnlineGallerySource.aitag),
      );
      expect(emptyPage.items, isEmpty);
      expect(emptyPage.total, 0);
      expect(emptyPage.hasMore, isFalse);

      final htmlFixture = _Fixture((_) => const _Reply(
            null,
            404,
            'text/html; charset=utf-8',
            rawBody: '<html><title>Not found</title></html>',
          ));
      await expectLater(
        GalleryApiAdapter(_http(htmlFixture)).search(
          const OnlineGalleryQuery(source: OnlineGallerySource.aitag),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('loads artist tags from Danbooru and keeps collection posts routable',
        () async {
      List<Map<String, dynamic>> artistPage(int page) {
        if (page == 1) {
          return [
            for (var index = 1; index <= 1000; index++)
              {
                'id': index,
                'name': 'artist_$index',
                'category': 1,
                'post_count': 1001 - index,
                'is_deprecated': false,
              },
          ];
        }
        if (page == 2) {
          return [
            {
              'id': 1001,
              'name': 'artist_tail',
              'category': 1,
              'post_count': 1,
              'is_deprecated': false,
            }
          ];
        }
        return [];
      }

      final fixture = _Fixture((request) {
        if (request.uri.path == '/tags.json') {
          final page = int.parse(request.uri.queryParameters['page']!);
          return _Reply.json(artistPage(page));
        }
        if (request.uri.path == '/posts.json') {
          return _Reply.json([_danbooruPost(200)]);
        }
        if (request.uri.path == '/counts/posts.json') {
          return _Reply.json({
            'counts': {'posts': 9}
          });
        }
        if (request.uri.path == '/posts/200.json') {
          return _Reply.json(_danbooruPost(200));
        }
        return _Reply.notFound();
      });
      final adapter = GalleryApiAdapter(_http(fixture));
      final ranking = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.artistRanking,
        sort: 'score',
        pageSize: 2,
      ));

      expect(ranking.total, 1001);
      expect(ranking.items, hasLength(2));
      expect(ranking.items.first.source, OnlineGallerySource.artistRanking);
      expect(ranking.items.first.isCollection, isTrue);
      expect(ranking.items.first.collectionId, 'artist_1');
      final artistSearch = fixture.requests.firstWhere(
        (request) => request.uri.path == '/tags.json',
      );
      expect(artistSearch.uri.queryParameters['search[category]'], '1');
      expect(artistSearch.uri.queryParameters['search[order]'], 'count');
      expect(artistSearch.uri.queryParameters['search[is_deprecated]'], 'no');

      final posts = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.artistRanking,
        collectionId: 'artist_1',
        sort: 'score',
      ));
      expect(posts.items.single.source, OnlineGallerySource.artistRanking);
      expect(posts.items.single.metadata['kind'], 'artist-post');
      expect(posts.items.single.metadata['artist'], 'artist_1');
      final postRequest = fixture.requests.firstWhere(
        (request) => request.uri.path == '/posts.json',
      );
      expect(postRequest.uri.host, 'danbooru.donmai.us');
      expect(postRequest.uri.queryParameters['tags'],
          'artist:artist_1 rating:g order:score');

      final detail = await adapter.detail(posts.items.single);
      expect(detail.source, OnlineGallerySource.artistRanking);
      expect(detail.metadata['kind'], 'artist-post');
      expect(fixture.requests.last.uri.path, '/posts/200.json');
      await expectLater(
        adapter.detail(const OnlineGalleryItem(
          source: OnlineGallerySource.artistRanking,
          id: '999',
          title: 'untyped placeholder',
        )),
        throwsA(isA<StateError>()),
      );
    });
  });
}

Map<String, dynamic> _danbooruPost(int id, {String rating = 'g'}) => {
      'id': id,
      'rating': rating,
      'score': 42,
      'fav_count': 8,
      'created_at': '2026-10-01T00:00:00Z',
      'tag_string_artist': 'sample_artist',
      'tag_string_character': 'sample_character',
      'tag_string_copyright': 'sample_series',
      'tag_string_general': 'blue_eyes sky',
      'tag_string_meta': 'highres',
      'tag_string':
          'sample_artist sample_character sample_series blue_eyes sky highres',
      'preview_file_url': 'https://cdn.donmai.us/preview/$id.jpg',
      'large_file_url': 'https://cdn.donmai.us/large/$id.jpg',
      'file_url': 'https://cdn.donmai.us/images/$id.jpg',
      'image_width': 512,
      'image_height': 768,
    };

Map<String, dynamic> _civitaiImage(
  int id, {
  bool nsfw = false,
  String nsfwLevel = 'None',
  String? url,
  String type = 'image',
}) =>
    {
      'id': id,
      'type': type,
      'url': url ?? 'https://image.civitai.com/images/$id.jpeg',
      'username': 'alice',
      'nsfw': nsfw,
      'nsfwLevel': nsfwLevel,
      'browsingLevel': 1,
      'meta': {
        'prompt': 'fixture prompt $id',
        'negativePrompt': 'fixture negative',
      },
    };

GalleryHttp _http(_Fixture fixture) => GalleryHttp(
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
        followRedirects: false,
      ))
        ..httpClientAdapter = fixture,
    );

class _Fixture implements HttpClientAdapter {
  final _Reply Function(RequestOptions request) responder;
  final requests = <RequestOptions>[];
  _Fixture(this.responder);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = responder(options);
    final body = reply.rawBody ?? jsonEncode(reply.body);
    return ResponseBody.fromString(
      body,
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [
          reply.contentType,
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Reply {
  final Object? body;
  final int statusCode;
  final String contentType;
  final String? rawBody;
  const _Reply(this.body, this.statusCode, this.contentType, {this.rawBody});

  factory _Reply.json(Object? value, {int statusCode = 200}) =>
      _Reply(value, statusCode, 'application/json; charset=utf-8');

  factory _Reply.notFound() => const _Reply(
        null,
        404,
        'text/plain; charset=utf-8',
        rawBody: 'not found',
      );
}
