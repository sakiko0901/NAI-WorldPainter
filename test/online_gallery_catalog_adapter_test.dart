import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/gallery/gallery_catalog_adapter.dart';
import 'package:nai_huishi/data/datasources/remote/gallery/gallery_http.dart';
import 'package:nai_huishi/domain/entities/online_gallery.dart';

void main() {
  group('QuickTagCloud catalog adapter', () {
    test(
        'lists safe collections, exposes their type, and paginates entries after sorting',
        () async {
      final fixture = _quickFixture();
      final adapter = GalleryCatalogAdapter(_galleryHttp(fixture));

      final directory = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.quickTag,
        safeOnly: true,
        collectionType: 'codex',
      ));
      expect(directory.items, hasLength(1));
      expect(directory.items.single.isCollection, isTrue);
      expect(directory.items.single.collectionId, 'demo');
      expect(directory.items.single.title, 'Demo Codex');
      expect(directory.collections, hasLength(1));
      expect(directory.collections.single, isA<OnlineGalleryCollection>());
      expect(directory.collections.single.type, 'codex');

      final page = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.quickTag,
        collectionId: 'old_demo',
        categoryPath: ['Clothing'],
        sort: 'name',
        page: 2,
        pageSize: 12,
      ));
      expect(page.total, 13);
      expect(page.hasMore, isFalse);
      expect(page.items.map((item) => item.title), ['Item 13']);
      expect(page.items.single.categoryPath, ['Clothing', 'Coats']);
      expect(page.categories.map((category) => category.path), [
        ['Clothing'],
        ['Clothing', 'Coats'],
        ['Empty'],
      ]);
      expect(page.categories.map((category) => category.count), [13, 13, 0]);
      expect(
        fixture.adapter.requests
            .where((request) => request.uri.path.contains('/images/')),
        isEmpty,
        reason: 'catalog search must not download linked image media',
      );
    });

    test(
        'maps positive, negative, character blocks, notes, and all entry images',
        () async {
      final fixture = _quickFixture();
      final adapter = GalleryCatalogAdapter(_galleryHttp(fixture));
      final summary = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.quickTag,
        collectionId: 'demo',
        categoryPath: ['Clothing'],
        sort: 'default',
        pageSize: 24,
      ));
      final entry = summary.items.singleWhere((item) => item.id == 'entry_13');
      final detail = await adapter.detail(entry);

      expect(detail.prompt, 'blue coat, soft light');
      expect(detail.negativePrompt, 'lowres, blurry');
      expect(detail.description, 'Synthetic item note');
      expect(detail.metadata['remark'], 'Synthetic item note');
      expect(detail.metadata['characterPrompts'], [
        {'label': 'Character A', 'prompt': 'blue coat'},
        {'label': 'Character B', 'prompt': 'red scarf'},
      ]);
      expect(detail.media, hasLength(2));
      expect(detail.media.first.previewUrl,
          'https://assets.quicktagcloud.com/images/demo/preview.webp');
      expect(detail.media.first.downloadUrl,
          'https://assets.quicktagcloud.com/originals/demo/original.png');
      expect(detail.media.last.width, 768);
      final sourceUrl = Uri.parse(detail.sourceUrl);
      expect(sourceUrl.queryParameters['c'], 'demo');
      expect(sourceUrl.queryParameters['entry'], 'entry_13');
      expect(sourceUrl.queryParameters['p'], isNotEmpty);
      expect(
        fixture.adapter.requests.where((request) =>
            request.uri.path.contains('/images/') ||
            request.uri.path.contains('/originals/')),
        isEmpty,
      );
    });
  });

  group('TAGs Gallery adapter', () {
    test('uses model and category routes and stitches true 60-item pages',
        () async {
      final fake = _FixtureAdapter((request) {
        final uri = request.uri;
        final upstreamPage = int.tryParse(uri.queryParameters['p'] ?? '') ?? 1;
        final start = (upstreamPage - 1) * 60;
        return _Response.html(_tagsListing(
          model: 'v5',
          category: 'character',
          start: start,
          count: 60,
          total: 128,
        ));
      });
      final adapter = GalleryCatalogAdapter(GalleryHttp(_dio(fake)));

      final page = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.tagsGallery,
        category: 'character',
        model: 'v5',
        query: 'blue & white',
        sort: 'favorites',
        page: 2,
        pageSize: 48,
      ));

      expect(page.items, hasLength(48));
      expect(page.items.first.id, 'v5/character/sample_48');
      expect(page.items.last.id, 'v5/character/sample_95');
      expect(page.items.first.sourceUrl,
          'https://tags.gallery/character/sample_48');
      expect(page.total, 128);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '3');
      expect(page.categories.map((value) => value.path), [
        ['artist'],
        ['character'],
        ['copyright'],
        ['fashion_style'],
        ['face'],
        ['face_parts'],
        ['hair'],
        ['accessories'],
        ['composition'],
      ]);
      expect(fake.requests, hasLength(2));
      expect(fake.requests.map((request) => request.uri.path), [
        '/v5/character',
        '/v5/character',
      ]);
      expect(
          fake.requests
              .map((request) => request.uri.queryParameters['p'] ?? '1'),
          ['1', '2']);
      expect(
          fake.requests.every((request) =>
              request.uri.queryParameters['q'] == 'blue & white' &&
              request.uri.queryParameters['s'] == 'favorites'),
          isTrue);
      expect(
          fake.requests
              .any((request) => request.uri.path.startsWith('/images/')),
          isFalse);
    });

    test('isolates V4.5 and V5 listing images and rejects wrong-model assets',
        () async {
      final adapter =
          GalleryCatalogAdapter(GalleryHttp(_dio(_FixtureAdapter((request) {
        final model = request.uri.path.startsWith('/v5') ? 'v5' : 'v4-5';
        return _Response.html(_tagsListing(
          model: model,
          category: 'hair',
          start: 0,
          count: 1,
          total: 1,
          wrongModel: model == 'v5',
        ));
      }))));

      final v45 = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.tagsGallery,
        category: 'hair',
        model: 'v4-5',
        pageSize: 12,
      ));
      final v5 = await adapter.search(const OnlineGalleryQuery(
        source: OnlineGallerySource.tagsGallery,
        category: 'hair',
        model: 'v5',
        pageSize: 12,
      ));

      expect(v45.items.single.id, 'hair/sample_0');
      expect(v45.items.single.cover.displayUrl,
          'https://tags.gallery/images/v45_sample_0.webp');
      expect(v5.items.single.id, 'v5/hair/sample_0');
      expect(v5.items.single.cover.displayUrl, isEmpty);
      expect(v5.items.single.mediaCount, 0);
    });

    test(
        'detail keeps only the requested model media and excludes recommendations',
        () async {
      const html = '''
<html><body>
  <h1><button aria-label="Copy tag: blue &amp; white"></button></h1>
  <button aria-label="Copy tag: blue_white"></button>
  <div>V5 vs V4.5 · SAME SEED</div>
  <div class="compare">
    <img src="/images/v5_sample.webp" alt="synthetic v5"/>
    <img src="/images/v45_sample.webp" alt="synthetic v4.5"/>
    <img src="/images/v5_sample_2.webp" alt="synthetic second v5"/>
  </div>
  <div class="grid grid-cols-3"><span>top score</span></div>
  <aside><img src="/images/v5_related_tag.webp" alt="synthetic related"/></aside>
  <div class="prompt-label">PROMPT / Shared</div>
  <button aria-label="Copy tag: blue &amp; white, shared synthetic prompt"></button>
</body></html>''';
      final fake = _FixtureAdapter((_) => _Response.html(html));
      final adapter = GalleryCatalogAdapter(GalleryHttp(_dio(fake)));
      const v5Item = OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: 'v5/artist/sample',
        title: 'sample',
      );
      const v45Item = OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: 'artist/sample',
        title: 'sample',
      );

      final v5 = await adapter.detail(v5Item);
      final v45 = await adapter.detail(v45Item);

      expect(v5.prompt, 'blue & white, shared synthetic prompt');
      expect(v5.media.map((media) => media.displayUrl), [
        'https://tags.gallery/images/v5_sample.webp',
        'https://tags.gallery/images/v5_sample_2.webp',
      ]);
      expect(v5.mediaCount, 2);
      expect(v5.metadata['model'], 'NAI Diffusion Anime V5 Full');
      expect(v5.sourceUrl, 'https://tags.gallery/artist/sample');
      expect(v45.media.map((media) => media.displayUrl), [
        'https://tags.gallery/images/v45_sample.webp',
      ]);
      expect(v45.metadata['model'], 'NAI Diffusion Anime V4.5 Full');
      expect(fake.requests, hasLength(2));
    });

    test(
        'detail falls back to validated listing media when the source has no comparison block',
        () async {
      const html = '''
<html><body>
  <h1><button aria-label="Copy tag: synthetic tag"></button></h1>
  <div class="stats"><span>Top score</span></div>
  <aside aria-label="Related tags">
    <a href="/artist/related"><img src="/images/v45_related.webp" alt="synthetic related"/></a>
  </aside>
</body></html>''';
      final fake = _FixtureAdapter((_) => _Response.html(html));
      final adapter = GalleryCatalogAdapter(GalleryHttp(_dio(fake)));
      const listingCover = OnlineGalleryMedia(
        id: 'listing-cover',
        previewUrl: 'https://tags.gallery/images/thumbs/v45_listing.webp',
        displayUrl: 'https://tags.gallery/images/v45_listing.webp',
        downloadUrl: 'https://tags.gallery/images/v45_listing.webp',
        width: 480,
        height: 702,
        extension: 'webp',
      );
      const v45Item = OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: 'artist/sample',
        title: 'synthetic tag',
        media: [listingCover],
      );
      const itemWithoutMedia = OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: 'artist/sample',
        title: 'synthetic tag',
      );
      const wrongModelItem = OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: 'artist/sample',
        title: 'synthetic tag',
        media: [
          OnlineGalleryMedia(
            id: 'wrong-model',
            previewUrl: 'https://tags.gallery/images/thumbs/v5_related.webp',
            displayUrl: 'https://tags.gallery/images/v5_related.webp',
            downloadUrl: 'https://tags.gallery/images/v5_related.webp',
          ),
        ],
      );

      final withListingMedia = await adapter.detail(v45Item);
      final withoutListingMedia = await adapter.detail(itemWithoutMedia);
      final wrongModelFallback = await adapter.detail(wrongModelItem);

      expect(withListingMedia.media, hasLength(1));
      expect(withListingMedia.media.single.previewUrl, listingCover.previewUrl);
      expect(withListingMedia.media.single.displayUrl, listingCover.displayUrl);
      expect(withListingMedia.mediaCount, 1);
      expect(withListingMedia.media.single.downloadUrl,
          'https://tags.gallery/images/v45_listing.webp');
      expect(withoutListingMedia.media, isEmpty);
      expect(withoutListingMedia.mediaCount, 0);
      expect(wrongModelFallback.media, isEmpty);
      expect(wrongModelFallback.mediaCount, 0);
      expect(fake.requests, hasLength(3));
    });

    test('detail selects a model-scoped prompt without borrowing its pair',
        () async {
      const html = '''
<html><body>
  <h1><button aria-label="Copy tag: synthetic"></button></h1>
  <div data-model="v5"><h2>PROMPT / V5</h2>
    <button aria-label="Copy tag: synthetic, v5 prompt"></button></div>
  <div data-model="v4-5"><h2>PROMPT / V4.5</h2>
    <button aria-label="Copy tag: synthetic, v4.5 prompt"></button></div>
</body></html>''';
      final adapter = GalleryCatalogAdapter(GalleryHttp(
        _dio(_FixtureAdapter((_) => _Response.html(html))),
      ));

      final v5 = await adapter.detail(const OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: 'v5/character/sample',
        title: 'sample',
      ));
      final v45 = await adapter.detail(const OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: 'character/sample',
        title: 'sample',
      ));

      expect(v5.prompt, 'synthetic, v5 prompt');
      expect(v45.prompt, 'synthetic, v4.5 prompt');
    });
  });
}

GalleryHttp _galleryHttp(_QuickFixture fixture) =>
    GalleryHttp(_dio(fixture.adapter));

Dio _dio(HttpClientAdapter adapter) => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 2),
      followRedirects: false,
    ))
      ..httpClientAdapter = adapter;

_QuickFixture _quickFixture() {
  final codex = <String, dynamic>{
    'id': 'demo',
    'title': 'Demo Codex',
    'author': 'Synthetic Author',
    'version': 'test-1',
    'type': 'codex',
    'tree': [
      {
        'name': 'Clothing',
        'children': [
          {'name': 'Coats'}
        ],
      }
    ],
    'emptyCategories': [
      ['Empty']
    ],
    'entries': [
      for (var number = 12; number >= 1; number--)
        {
          'id': 'entry_$number',
          'title': 'Item $number',
          'tags': 'synthetic tag $number',
          'path': ['Clothing', 'Coats'],
        },
      {
        'id': 'entry_13',
        'title': 'Item 13',
        'tags': 'blue coat, soft light',
        'negative': 'lowres, blurry',
        'note': 'Synthetic item note',
        'path': ['Clothing', 'Coats'],
        'characterPrompts': [
          {'label': 'Character A', 'prompt': 'blue coat'},
          {'label': 'Character B', 'prompt': 'red scarf'},
          {'label': 'invalid', 'prompt': ''},
        ],
        'images': [
          {
            'path': 'preview.webp',
            'original': 'original.png',
            'width': 512,
            'height': 768,
          },
          {
            'path': 'detail.webp',
            'original': 'detail.png',
            'width': 768,
            'height': 1024,
          },
        ],
      },
    ],
  };
  final codexBytes = utf8.encode(jsonEncode(codex));
  final manifestEntry = {
    'size': codexBytes.length,
    'sha256': sha256.convert(codexBytes).toString(),
  };
  final catalog = [
    {
      'id': 'demo',
      'type': 'codex',
      'title': 'Demo Codex',
      'author': 'Synthetic Author',
      'version': 'test-1',
      'entryCount': 13,
      'imagedCount': 2,
      'cover': 'cover.webp',
      'aliases': ['old_demo'],
    },
    {
      'id': 'adult_pack',
      'type': 'pack',
      'title': 'Hidden Synthetic Pack',
      'entryCount': 1,
      'nsfw': true,
    },
  ];
  final adapter = _FixtureAdapter((request) {
    final path = request.uri.path;
    if (path == '/data-source.json') {
      return _Response.json({
        'baseUrl': 'https://assets.quicktagcloud.com/data',
        'pointer': 'current.json',
        'remoteHosts': ['assets.quicktagcloud.com'],
      });
    }
    if (path == '/data/current.json') {
      return _Response.json({
        'release': 'r-test',
        'manifest': 'releases/r-test/manifest.json',
      });
    }
    if (path == '/data/releases/r-test/manifest.json') {
      return _Response.json({
        'files': {'demo.json': manifestEntry},
      });
    }
    if (path == '/data/releases/r-test/codexes.json') {
      return _Response.json(catalog);
    }
    if (path == '/data/releases/r-test/media.json') {
      return _Response.json({
        'baseUrl': 'https://assets.quicktagcloud.com',
        'imagePrefix': 'images',
        'originalPrefix': 'originals',
      });
    }
    if (path == '/data/releases/r-test/demo.json') {
      return _Response.bytes(codexBytes);
    }
    return _Response.notFound();
  });
  return _QuickFixture(adapter);
}

String _tagsListing({
  required String model,
  required String category,
  required int start,
  required int count,
  required int total,
  bool wrongModel = false,
}) {
  final imagePrefix = model == 'v5' ? 'v5' : 'v45';
  final wrongPrefix = model == 'v5' ? 'v45' : 'v5';
  final prefix = wrongModel ? wrongPrefix : imagePrefix;
  final cards = List<String>.generate(count, (offset) {
    final index = start + offset;
    final title = index == 0 ? 'blue & white' : 'sample tag $index';
    return '''
<div class="gallery-card">
  <a aria-label="Open detail: ${_escapeHtml(title)}" href="/$category/sample_$index">
    <picture>
      <source srcSet="/images/thumbs/${prefix}_sample_$index.webp 1x" type="image/webp"/>
      <img src="/images/${prefix}_sample_$index.webp" alt="${_escapeHtml(title)}" width="480" height="702"/>
    </picture>
  </a>
  <div><button aria-label="いいね — お気に入りに追加"></button>
    <span aria-label="累計いいね ${index + 7}">${index + 7}</span>
    <span>posts=${index + 3} · ▲${2800 - index}</span>
  </div>
</div>''';
  }).join();
  return '''<html><body><span>hits=$total</span>$cards
<script>const recommendation = "Open detail: synthetic related";</script>
</body></html>''';
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

class _QuickFixture {
  final _FixtureAdapter adapter;
  const _QuickFixture(this.adapter);
}

class _FixtureAdapter implements HttpClientAdapter {
  final _Response Function(RequestOptions request) responder;
  final requests = <RequestOptions>[];
  _FixtureAdapter(this.responder);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = responder(options);
    return switch (response.kind) {
      _ResponseKind.json || _ResponseKind.html => ResponseBody.fromString(
          response.body,
          response.statusCode,
          headers: {
            Headers.contentTypeHeader: [
              response.kind == _ResponseKind.html
                  ? 'text/html; charset=utf-8'
                  : 'application/json; charset=utf-8',
            ],
          },
        ),
      _ResponseKind.bytes => ResponseBody.fromBytes(
          response.bytes,
          response.statusCode,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      _ResponseKind.notFound => ResponseBody.fromString(
          'not found',
          404,
          headers: {
            Headers.contentTypeHeader: ['text/plain']
          },
        ),
    };
  }

  @override
  void close({bool force = false}) {}
}

enum _ResponseKind { json, html, bytes, notFound }

class _Response {
  final _ResponseKind kind;
  final String body;
  final List<int> bytes;
  final int statusCode;
  const _Response._(this.kind, this.body, this.bytes, this.statusCode);

  factory _Response.json(Object? value) =>
      _Response._(_ResponseKind.json, jsonEncode(value), const [], 200);
  factory _Response.html(String value) =>
      _Response._(_ResponseKind.html, value, const [], 200);
  factory _Response.bytes(List<int> value) =>
      _Response._(_ResponseKind.bytes, '', value, 200);
  factory _Response.notFound() =>
      const _Response._(_ResponseKind.notFound, '', [], 404);
}
