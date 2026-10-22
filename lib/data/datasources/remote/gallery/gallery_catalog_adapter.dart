import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

import '../../../../domain/entities/online_gallery.dart';
import 'gallery_adapter.dart';
import 'gallery_http.dart';

const _quickTagSourceUrl = 'https://novelai.quicktagcloud.com/data-source.json';
const _quickTagReferer = 'https://novelai.quicktagcloud.com/';
const _tagsGalleryOrigin = 'https://tags.gallery';
const _tagsGalleryCategories = <String>[
  'artist',
  'character',
  'copyright',
  'fashion_style',
  'face',
  'face_parts',
  'hair',
  'accessories',
  'composition',
];
const _quickTagDefaultHosts = <String>{
  'assets.quicktagcloud.com',
  'novelai.quicktagcloud.com',
};
const _tagsGalleryUpstreamPageSize = 60;
const _quickTagMaxCodexBytes = 32 * 1024 * 1024;
const _tagsGalleryMaxHtmlChars = 5 * 1000 * 1000;

/// Catalog backed adapters for the public QuickTagCloud and TAGs Gallery sites.
///
/// It intentionally owns only transport normalization. Gallery persistence and
/// presentation remain in the repository and UI layers.
class GalleryCatalogAdapter implements GalleryAdapter {
  final GalleryHttp _http;
  Future<_QuickCatalog>? _quickCatalogFuture;
  DateTime? _quickCatalogFetchedAt;
  final Map<String, _TimedFuture<_QuickCodex>> _quickCodexCache = {};

  GalleryCatalogAdapter(GalleryHttp http) : _http = http;

  @override
  Future<OnlineGalleryPage> search(OnlineGalleryQuery query) async {
    if (query.timeRange != 'all' &&
        (query.source == OnlineGallerySource.quickTag ||
            query.source == OnlineGallerySource.tagsGallery)) {
      throw const FormatException('Unsupported gallery time range');
    }
    return switch (query.source) {
      OnlineGallerySource.quickTag => _searchQuickTag(query),
      OnlineGallerySource.tagsGallery => _searchTagsGallery(query),
      _ => throw UnsupportedError(
          'GalleryCatalogAdapter does not handle ${query.source.id}'),
    };
  }

  @override
  Future<OnlineGalleryItem> detail(
    OnlineGalleryItem item, {
    bool safeOnly = true,
  }) async {
    return switch (item.source) {
      OnlineGallerySource.quickTag => _quickTagDetail(item, safeOnly: safeOnly),
      OnlineGallerySource.tagsGallery => _tagsGalleryDetail(item),
      _ => throw UnsupportedError(
          'GalleryCatalogAdapter does not handle ${item.source.id}'),
    };
  }

  Future<OnlineGalleryPage> _searchQuickTag(OnlineGalleryQuery query) async {
    final catalog = await _quickCatalog();
    final link = _quickLink(query.query.trim());
    final searchText = link?.query ?? query.query.trim();
    final requestedId = link?.collectionId ?? query.collectionId ?? '';
    final collectionId = _quickResolveCollection(catalog.codexes, requestedId);
    final collectionType = collectionId.isNotEmpty
        ? _quickCollectionType(catalog.codexes
            .firstWhere((value) => value['id'] == collectionId)['type'])
        : query.collectionType ?? '';
    final safeOnly = query.safeOnly;
    final available = catalog.codexes.where((codex) {
      return (!safeOnly || !_truthy(codex['nsfw'])) &&
          (collectionType.isEmpty ||
              _quickCollectionType(codex['type']) == collectionType);
    }).toList();
    final navigationCollections = catalog.codexes
        .where((codex) => !safeOnly || !_truthy(codex['nsfw']))
        .map(_quickNavigationCollection)
        .toList(growable: false);
    final pageSize = _pageSize(query.pageSize);
    final requestedPage = _requestedPage(query);

    if (collectionId.isEmpty && !query.searchAll) {
      final matching = available
          .where((codex) => _quickCollectionMatches(codex, searchText))
          .map((codex) => _quickCollectionItem(catalog, codex))
          .toList();
      final sorted = _sortQuickItems(matching, query.sort, query.shuffleSeed);
      final page = _slicePage(sorted, requestedPage, pageSize);
      return OnlineGalleryPage(
        items: page.items,
        hasMore: page.hasMore,
        nextCursor: page.hasMore ? '${page.page + 1}' : null,
        total: sorted.length,
        title: 'QuickTagCloud',
        collections: navigationCollections,
      );
    }

    if (collectionId.isEmpty) {
      if (searchText.trim().isEmpty) {
        return OnlineGalleryPage(
          items: const [],
          title: 'QuickTagCloud',
          collections: navigationCollections,
        );
      }
      final groups = List<List<OnlineGalleryItem>>.generate(
        available.length,
        (_) => <OnlineGalleryItem>[],
      );
      final warnings = <String>[];
      var next = 0;
      Future<void> worker() async {
        while (true) {
          final index = next++;
          if (index >= available.length) return;
          final codexMeta = available[index];
          try {
            final codex = await _quickCodex(catalog, _string(codexMeta['id']));
            groups[index] = codex.entries.indexed
                .where((indexed) =>
                    (!safeOnly || _quickSafe(indexed.$2)) &&
                    _quickEntryMatches(indexed.$2, searchText))
                .map((indexed) => _quickEntryItem(
                      catalog,
                      codex,
                      indexed.$2,
                      indexed.$1,
                    ))
                .toList();
          } catch (_) {
            warnings.add('集合「${_string(codexMeta['title'])}」加载失败，搜索结果可能不完整');
          }
        }
      }

      await Future.wait(List<Future<void>>.generate(
        available.length < 3 ? available.length : 3,
        (_) => worker(),
      ));
      final all = _sortQuickItems(groups.expand((group) => group).toList(),
          query.sort, query.shuffleSeed);
      final page = _slicePage(all, requestedPage, pageSize);
      return OnlineGalleryPage(
        items: page.items,
        hasMore: page.hasMore,
        nextCursor: page.hasMore ? '${page.page + 1}' : null,
        total: all.length,
        title: 'QuickTagCloud',
        collections: navigationCollections,
        warnings: warnings,
      );
    }

    final codex = await _quickCodex(catalog, collectionId);
    if (safeOnly && _truthy(codex.metadata['nsfw'])) {
      throw const FormatException(
          'This QuickTagCloud collection is hidden by the all-ages filter');
    }
    final visibleEntries = codex.entries
        .where((entry) => !safeOnly || _quickSafe(entry))
        .toList(growable: false);
    final categories = _quickCategories(
      visibleEntries,
      codex.metadata['tree'],
      codex.metadata['emptyCategories'],
    );
    var categoryPath =
        link != null && link.path.isNotEmpty ? link.path : query.categoryPath;
    if (link != null && link.code.isNotEmpty && link.path.isEmpty) {
      final matches = _quickCategories(
        codex.entries,
        codex.metadata['tree'],
        codex.metadata['emptyCategories'],
      ).where((category) => category.code == link.code).toList();
      if (matches.length != 1) {
        throw const FormatException(
            'QuickTagCloud category link is obsolete or ambiguous');
      }
      categoryPath = matches.single.path;
    }

    final aliases = _asMap(codex.metadata['entryAliases']);
    final matchingEntries = <OnlineGalleryItem>[];
    for (var index = 0; index < codex.entries.length; index++) {
      final entry = codex.entries[index];
      if (safeOnly && !_quickSafe(entry)) continue;
      final entryPath = _stringList(entry['path']);
      if (!_isPathPrefix(categoryPath, entryPath)) continue;
      if (link != null && link.entry.isNotEmpty) {
        final canonicalId = _string(aliases[link.entry]).isNotEmpty
            ? _string(aliases[link.entry])
            : link.entry;
        if ((_string(entry['id']).isNotEmpty
                ? _string(entry['id'])
                : '${codex.id}_${index + 1}') !=
            canonicalId) {
          continue;
        }
      }
      if (!_quickEntryMatches(entry, searchText)) continue;
      matchingEntries.add(_quickEntryItem(catalog, codex, entry, index));
    }

    final sorted =
        _sortQuickItems(matchingEntries, query.sort, query.shuffleSeed);
    final page = _slicePage(sorted, requestedPage, pageSize);
    return OnlineGalleryPage(
      items: page.items,
      hasMore: page.hasMore,
      nextCursor: page.hasMore ? '${page.page + 1}' : null,
      total: sorted.length,
      title: codex.title,
      collections: navigationCollections,
      categories: categories
          .map((category) => OnlineGalleryCategory(
                path: category.path,
                title: category.path.last,
                count: category.count,
              ))
          .toList(growable: false),
    );
  }

  Future<OnlineGalleryPage> _searchTagsGallery(OnlineGalleryQuery query) async {
    final category = _tagsGalleryCategory(query.category);
    final model = _tagsGalleryModel(query.model);
    final sort = _tagsGallerySort(query.sort);
    final page = _requestedPage(query);
    final pageSize = _pageSize(query.pageSize);
    final offset = (page - 1) * pageSize;
    final upstreamPage = offset ~/ _tagsGalleryUpstreamPageSize + 1;
    var skip = offset % _tagsGalleryUpstreamPageSize;
    var current = await _fetchTagsGalleryPage(
      category,
      model,
      upstreamPage,
      query.query,
      sort,
    );
    var total = current.total;
    final items = <OnlineGalleryItem>[];
    var nextUpstreamPage = upstreamPage;

    while (items.length < pageSize && offset + items.length < total) {
      items.addAll(current.items.skip(skip).take(pageSize - items.length));
      skip = 0;
      if (items.length >= pageSize || offset + items.length >= total) break;
      if (current.items.length < _tagsGalleryUpstreamPageSize) break;
      nextUpstreamPage++;
      current = await _fetchTagsGalleryPage(
        category,
        model,
        nextUpstreamPage,
        query.query,
        sort,
      );
      total = current.total == 0
          ? total
          : (current.total < total ? current.total : total);
      if (current.items.isEmpty) break;
    }

    final hasMore = offset + items.length < total;
    return OnlineGalleryPage(
      items: items,
      hasMore: hasMore,
      nextCursor: hasMore ? '${page + 1}' : null,
      total: total,
      title: 'TAGs Gallery · $model · $category',
      categories: _tagsGalleryCategories
          .map((value) => OnlineGalleryCategory(path: [value], title: value))
          .toList(growable: false),
    );
  }

  Future<_ParsedTagsPage> _fetchTagsGalleryPage(
    String category,
    String model,
    int upstreamPage,
    String searchText,
    String sort,
  ) async {
    final modelPath = model == 'v5' ? 'v5' : 'v4-5';
    final categoryPath = category == 'artist' ? '' : '/$category';
    final parameters = <String, String>{
      if (upstreamPage > 1) 'p': '$upstreamPage',
      if (searchText.isNotEmpty) 'q': searchText,
      if (sort != 'score') 's': sort,
    };
    final uri = Uri.parse('$_tagsGalleryOrigin/$modelPath$categoryPath')
        .replace(queryParameters: parameters.isEmpty ? null : parameters);
    final html =
        await _http.html(uri.toString(), referer: '$_tagsGalleryOrigin/');
    return _parseTagsGalleryPage(html, category, model);
  }

  Future<OnlineGalleryItem> _quickTagDetail(
    OnlineGalleryItem item, {
    required bool safeOnly,
  }) async {
    if (item.isCollection) return item;
    final collectionId = _safeCollectionId(item.collectionId);
    if (collectionId.isEmpty) {
      throw const FormatException('QuickTagCloud collection id is required');
    }
    final catalog = await _quickCatalog();
    final codex = await _quickCodex(catalog, collectionId);
    if (safeOnly && _truthy(codex.metadata['nsfw'])) {
      throw const FormatException(
          'This QuickTagCloud collection is hidden by the all-ages filter');
    }
    var index = -1;
    for (var position = 0; position < codex.entries.length; position++) {
      final entryId = _string(codex.entries[position]['id']);
      final resolvedId =
          entryId.isNotEmpty ? entryId : '${codex.id}_${position + 1}';
      if (resolvedId == item.id) {
        index = position;
        break;
      }
    }
    if (index < 0) {
      throw const FormatException('QuickTagCloud entry was not found');
    }
    final entry = codex.entries[index];
    if (safeOnly && !_quickSafe(entry)) {
      throw const FormatException(
          'This QuickTagCloud entry is hidden by the all-ages filter');
    }
    return _quickEntryItem(catalog, codex, entry, index,
        includeDetailMetadata: true);
  }

  Future<OnlineGalleryItem> _tagsGalleryDetail(OnlineGalleryItem item) async {
    final identity = _parseTagsGalleryId(item.id);
    final sourceUrl = _tagsGalleryDetailUrl(identity);
    final raw = await _http.html(sourceUrl, referer: '$_tagsGalleryOrigin/');
    final listingMedia = _tagsGalleryFallbackMedia(item, identity.model);
    return _parseTagsGalleryDetail(
      raw,
      item.id,
      fallbackMedia: listingMedia,
    );
  }

  Future<_QuickCatalog> _quickCatalog() async {
    final cached = _quickCatalogFuture;
    final fetchedAt = _quickCatalogFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(minutes: 10)) {
      return cached;
    }
    final future = _fetchQuickCatalog();
    _quickCatalogFuture = future;
    _quickCatalogFetchedAt = DateTime.now();
    future.then<void>((_) {}, onError: (Object _) {
      if (identical(_quickCatalogFuture, future)) {
        _quickCatalogFuture = null;
        _quickCatalogFetchedAt = null;
      }
    });
    return future;
  }

  Future<_QuickCatalog> _fetchQuickCatalog() async {
    final source =
        _asMap(await _http.json(_quickTagSourceUrl, referer: _quickTagReferer));
    final baseUri = Uri.tryParse(_string(source['baseUrl']));
    if (baseUri == null || !_isQuickTagUri(baseUri, _quickTagDefaultHosts)) {
      throw const FormatException('Invalid QuickTagCloud data source');
    }
    final allowedHosts = <String>{..._quickTagDefaultHosts};
    for (final remoteHost in _asList(source['remoteHosts'])) {
      final host = _hostOf(remoteHost);
      if (host.isNotEmpty) allowedHosts.add(host);
    }
    if (!allowedHosts.contains(baseUri.host.toLowerCase())) {
      throw const FormatException('Invalid QuickTagCloud data host');
    }
    final pointerName = _string(source['pointer']);
    if (!_isSafeQuickJsonPath(pointerName)) {
      throw const FormatException('Invalid QuickTagCloud data source');
    }
    final baseDirectory =
        Uri.parse('${baseUri.toString().replaceAll(RegExp(r'/+$'), '')}/');
    final pointerUri =
        _trustedQuickUri(baseDirectory.resolve(pointerName), allowedHosts);
    final pointer = _asMap(
        await _http.json(pointerUri.toString(), referer: _quickTagReferer));
    final release = _safeCollectionId(pointer['release']);
    final manifestPath = _string(pointer['manifest']);
    if (release.isEmpty ||
        !RegExp(r'^releases/[a-z0-9_-]+/manifest\.json$', caseSensitive: false)
            .hasMatch(manifestPath)) {
      throw const FormatException('Invalid QuickTagCloud release pointer');
    }
    final basePath = baseUri.toString().replaceAll(RegExp(r'/+$'), '');
    final releaseBase =
        Uri.parse('$basePath/releases/${Uri.encodeComponent(release)}/');
    final manifestUri =
        _trustedQuickUri(baseDirectory.resolve(manifestPath), allowedHosts);
    final manifest = _asMap(
        await _http.json(manifestUri.toString(), referer: _quickTagReferer));
    final files = _asMap(manifest['files']);
    final results = await Future.wait<dynamic>([
      _http.json('${releaseBase}codexes.json', referer: _quickTagReferer),
      _http.json('${releaseBase}media.json', referer: _quickTagReferer),
    ]);
    final rawCodexes = results[0] is List
        ? results[0] as List
        : _asList(_asMap(results[0])['codexes']);
    final codexes = rawCodexes
        .map(_asMap)
        .map(_normalizeQuickMeta)
        .where((codex) => _string(codex['id']).isNotEmpty)
        .toList(growable: false);
    final media = _asMap(results[1]);
    final mediaBase = _httpsUri(media['baseUrl'], allowedHosts) ??
        Uri.parse('https://assets.quicktagcloud.com');
    allowedHosts.add(mediaBase.host.toLowerCase());
    return _QuickCatalog(
      baseUrl: basePath,
      release: release,
      releaseBaseUrl: releaseBase.toString(),
      media: {
        ...media,
        'baseUrl': mediaBase.toString(),
        'imagePrefix': _string(media['imagePrefix']).isNotEmpty
            ? _string(media['imagePrefix'])
            : 'images',
        'originalPrefix': _string(media['originalPrefix']).isNotEmpty
            ? _string(media['originalPrefix'])
            : 'originals',
      },
      allowedHosts: allowedHosts,
      manifestFiles: {
        for (final entry in files.entries) entry.key: _asMap(entry.value),
      },
      codexes: codexes,
    );
  }

  Future<_QuickCodex> _quickCodex(_QuickCatalog catalog, String id) async {
    final safeId = _safeCollectionId(id);
    final meta = catalog.codexes.cast<Map<String, dynamic>?>().firstWhere(
          (codex) => codex?['id'] == safeId,
          orElse: () => null,
        );
    if (safeId.isEmpty || meta == null) {
      throw const FormatException('QuickTagCloud collection was not found');
    }
    final cacheKey = '${catalog.release}:$safeId';
    final existing = _quickCodexCache[cacheKey];
    if (existing != null &&
        DateTime.now().difference(existing.createdAt) <
            const Duration(minutes: 10)) {
      return existing.future;
    }
    final future = _fetchQuickCodex(catalog, meta);
    _quickCodexCache[cacheKey] = _TimedFuture(future);
    future.then<void>((_) {}, onError: (Object _) {
      if (identical(_quickCodexCache[cacheKey]?.future, future)) {
        _quickCodexCache.remove(cacheKey);
      }
    });
    return future;
  }

  Future<_QuickCodex> _fetchQuickCodex(
    _QuickCatalog catalog,
    Map<String, dynamic> meta,
  ) async {
    final id = _string(meta['id']);
    final canonicalPath = '$id.json';
    final dataUrl = _string(meta['dataUrl']);
    final uri = dataUrl.isEmpty
        ? _trustedQuickUri(
            Uri.parse(catalog.releaseBaseUrl)
                .resolve(_encodePath(canonicalPath)),
            catalog.allowedHosts,
          )
        : _trustedQuickUri(
            Uri.parse(catalog.releaseBaseUrl).resolve(dataUrl),
            catalog.allowedHosts,
          );
    final response = await _http.get(
      uri.toString(),
      referer: _quickTagReferer,
      responseType: ResponseType.bytes,
    );
    final rawBytes = response.data;
    final bytes = rawBytes is List<int>
        ? rawBytes
        : rawBytes is String
            ? utf8.encode(rawBytes)
            : const <int>[];
    if (bytes.isEmpty || bytes.length > _quickTagMaxCodexBytes) {
      throw const FormatException(
          'QuickTagCloud collection response is invalid');
    }
    if (dataUrl.isEmpty) {
      final manifestEntry = catalog.manifestFiles[canonicalPath];
      if (manifestEntry != null) {
        final expectedSize = _integer(manifestEntry['size']);
        final expectedHash = _string(manifestEntry['sha256']).toLowerCase();
        if (expectedSize <= 0 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) ||
            bytes.length != expectedSize ||
            sha256.convert(bytes).toString() != expectedHash) {
          throw const FormatException(
              'QuickTagCloud collection integrity check failed');
        }
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    final rawCodex = _asMap(decoded);
    final merged = <String, dynamic>{...meta, ...rawCodex, 'id': id};
    final entries =
        _asList(rawCodex['entries']).map(_asMap).toList(growable: false);
    return _QuickCodex(
      id: id,
      title:
          _string(merged['title']).isNotEmpty ? _string(merged['title']) : id,
      author: _string(merged['author']),
      version: _string(merged['version']),
      metadata: merged,
      entries: entries,
    );
  }

  OnlineGalleryCollection _quickNavigationCollection(
          Map<String, dynamic> codex) =>
      OnlineGalleryCollection(
        id: _string(codex['id']),
        title: _string(codex['title']).isNotEmpty
            ? _string(codex['title'])
            : _string(codex['id']),
        count: _integer(codex['entryCount']),
        type: _quickCollectionType(codex['type']),
        version: _string(codex['version']),
      );

  OnlineGalleryItem _quickCollectionItem(
    _QuickCatalog catalog,
    Map<String, dynamic> codex,
  ) {
    final id = _string(codex['id']);
    final coverUrl = _quickAssetUrl(
      catalog,
      codex,
      _string(codex['cover']),
      kind: 'image',
      assetCodexId: _safeCollectionId(codex['coverCodexId']),
    );
    return OnlineGalleryItem(
      source: OnlineGallerySource.quickTag,
      id: id,
      title: _string(codex['title']).isNotEmpty ? _string(codex['title']) : id,
      author: _string(codex['author']),
      description:
          '${_string(codex['version']).isNotEmpty ? _string(codex['version']) : '—'} · ${_integer(codex['entryCount'])} 条',
      sourceUrl: _quickSourceUrl(id),
      rating: _truthy(codex['nsfw']) ? 'explicit' : 'general',
      createdAt: _string(codex['version']),
      collectionId: id,
      isCollection: true,
      mediaCount: _integer(codex['imagedCount']),
      media: coverUrl.isEmpty
          ? const []
          : [
              OnlineGalleryMedia(
                id: 'quicktag:$id:cover',
                previewUrl: coverUrl,
                displayUrl: coverUrl,
                downloadUrl: coverUrl,
                extension: _extension(coverUrl),
              ),
            ],
      metadata: {
        'type': _quickCollectionType(codex['type']),
        'entryCount': _integer(codex['entryCount']),
        'imagedCount': _integer(codex['imagedCount']),
        'version': _string(codex['version']),
      },
    );
  }

  OnlineGalleryItem _quickEntryItem(
    _QuickCatalog catalog,
    _QuickCodex codex,
    Map<String, dynamic> entry,
    int index, {
    bool includeDetailMetadata = false,
  }) {
    final id = _string(entry['id']).isNotEmpty
        ? _string(entry['id'])
        : '${codex.id}_${index + 1}';
    final media = _quickEntryMedia(catalog, codex, entry, id);
    final prompt = _quickPrompt(entry);
    final path = _stringList(entry['path']);
    final note = _string(entry['note']);
    final characters = _quickCharacters(entry['characterPrompts']);
    final authorParts = <String>[
      _string(entry['credit']),
      _string(entry['author']),
      codex.author,
    ].where((value) => value.isNotEmpty).toSet().toList();
    return OnlineGalleryItem(
      source: OnlineGallerySource.quickTag,
      id: id,
      title: _string(entry['title']).isNotEmpty ? _string(entry['title']) : id,
      author: authorParts.join(' · '),
      description: note.isNotEmpty ? note : path.join(' / '),
      sourceUrl: _quickSourceUrl(codex.id, entry: id, path: path),
      prompt: prompt,
      negativePrompt: _string(entry['negative']).isNotEmpty
          ? _string(entry['negative'])
          : _string(entry['negativePrompt']),
      rating: _truthy(codex.metadata['nsfw']) || !_quickSafe(entry)
          ? 'explicit'
          : 'general',
      createdAt: codex.version,
      collectionId: codex.id,
      mediaCount: media.length,
      media: media,
      categoryPath: path,
      tags: {
        'general': prompt
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(),
      },
      metadata: {
        'characterPrompts': characters,
        'remark': note,
        if (includeDetailMetadata) ...{
          'collectionTitle': codex.title,
          'collectionVersion': codex.version,
          'collectionId': codex.id,
        },
      },
    );
  }

  List<OnlineGalleryMedia> _quickEntryMedia(
    _QuickCatalog catalog,
    _QuickCodex codex,
    Map<String, dynamic> entry,
    String entryId,
  ) {
    final images = _asList(entry['images']).map(_asMap).toList();
    if (images.isEmpty &&
        (_string(entry['image']).isNotEmpty ||
            _string(entry['original']).isNotEmpty)) {
      images.add({'path': entry['image'], 'original': entry['original']});
    }
    final requestedAssetId = _safeCollectionId(entry['assetCodexId']);
    final assetCodexId =
        requestedAssetId.isNotEmpty ? requestedAssetId : codex.id;
    return images.indexed
        .map((indexed) {
          final image = indexed.$2;
          final path = _string(image['path']).isNotEmpty
              ? _string(image['path'])
              : (_string(image['image']).isNotEmpty
                  ? _string(image['image'])
                  : _string(entry['image']));
          final originalPath = _string(image['original']).isNotEmpty
              ? _string(image['original'])
              : (_string(entry['original']).isNotEmpty
                  ? _string(entry['original'])
                  : path);
          final previewUrl = _quickAssetUrl(
            catalog,
            codex.metadata,
            path,
            kind: 'image',
            assetCodexId: assetCodexId,
          );
          final originalUrl = _quickAssetUrl(
            catalog,
            codex.metadata,
            originalPath,
            kind: 'original',
            assetCodexId: assetCodexId,
          ).isNotEmpty
              ? _quickAssetUrl(
                  catalog,
                  codex.metadata,
                  originalPath,
                  kind: 'original',
                  assetCodexId: assetCodexId,
                )
              : previewUrl;
          return OnlineGalleryMedia(
            id: 'quicktag:${codex.id}:$entryId:${indexed.$1}',
            previewUrl: previewUrl,
            displayUrl: previewUrl,
            downloadUrl: originalUrl,
            width: _integer(image['width'] ?? entry['imageWidth']),
            height: _integer(image['height'] ?? entry['imageHeight']),
            extension:
                _extension(originalUrl.isNotEmpty ? originalUrl : previewUrl),
          );
        })
        .where((media) => media.previewUrl.isNotEmpty)
        .toList(growable: false);
  }

  String _quickAssetUrl(
    _QuickCatalog catalog,
    Map<String, dynamic> codex,
    String file, {
    required String kind,
    String assetCodexId = '',
  }) {
    final raw = file.trim();
    if (raw.isEmpty) return '';
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) {
      return _isQuickTagUri(parsed, catalog.allowedHosts)
          ? parsed.toString()
          : '';
    }
    final assetMode = _string(codex['assetPathMode']);
    final assetBaseUrl = _string(codex['assetBaseUrl']);
    final safeFile = _encodePath(raw);
    if (assetMode == 'relative' && assetBaseUrl.isNotEmpty) {
      final assetBase = _httpsUri(assetBaseUrl, catalog.allowedHosts);
      if (assetBase == null) return '';
      final prefix = assetBase.toString().replaceAll(RegExp(r'/+$'), '');
      return '$prefix/$safeFile';
    }
    final prefix = kind == 'original'
        ? _string(catalog.media['originalPrefix'])
        : _string(catalog.media['imagePrefix']);
    final collection = assetCodexId.isNotEmpty
        ? assetCodexId
        : (_safeCollectionId(codex['coverCodexId']).isNotEmpty
            ? _safeCollectionId(codex['coverCodexId'])
            : _safeCollectionId(codex['id']));
    if (collection.isEmpty || prefix.isEmpty) return '';
    final base =
        _string(catalog.media['baseUrl']).replaceAll(RegExp(r'/+$'), '');
    final baseUri = _httpsUri(base, catalog.allowedHosts);
    if (baseUri == null) return '';
    return '$base/${_encodePath(prefix)}/${_encodePath(collection)}/$safeFile';
  }

  String _quickSourceUrl(String collectionId,
      {String entry = '', List<String> path = const []}) {
    final parameters = <String, String>{'c': collectionId};
    if (entry.isNotEmpty) parameters['entry'] = entry;
    if (path.isNotEmpty) parameters['p'] = _quickPathCode(path);
    return Uri.https('novelai.quicktagcloud.com', '/', parameters).toString();
  }

  String _quickPrompt(Map<String, dynamic> entry) {
    final tags = entry['tags'];
    if (tags is String) return tags;
    if (tags is List) return tags.whereType<String>().join(', ');
    return _string(entry['prompt']);
  }

  List<Map<String, String>> _quickCharacters(Object? value) {
    return _asList(value)
        .whereType<Map>()
        .map((raw) {
          final character = Map<String, dynamic>.from(raw);
          final prompt = _string(character['prompt']);
          if (prompt.isEmpty) return null;
          return <String, String>{
            'label': _string(character['label']),
            'prompt': prompt,
          };
        })
        .whereType<Map<String, String>>()
        .toList(growable: false);
  }

  bool _quickSafe(Map<String, dynamic> entry) {
    final rating = _string(entry['rating']);
    return !_truthy(entry['nsfw']) &&
        !RegExp(r'^(r18|r18g|nsfw|explicit|questionable|sensitive|adult)$',
                caseSensitive: false)
            .hasMatch(rating);
  }

  bool _quickEntryMatches(Map<String, dynamic> entry, String query) {
    final characterText = _quickCharacters(entry)
        .map((character) => '${character['label']} ${character['prompt']}')
        .join(' ');
    final haystack = [
      entry['title'],
      entry['tags'],
      entry['prompt'],
      entry['note'],
      entry['author'],
      entry['credit'],
      entry['path'],
      characterText,
    ].join(' ').toLowerCase();
    return _quickQueryMatches(haystack, query);
  }

  bool _quickCollectionMatches(Map<String, dynamic> codex, String query) {
    final haystack = [
      codex['id'],
      codex['title'],
      codex['author'],
      codex['version'],
      codex['type'],
    ].join(' ').toLowerCase();
    return _quickQueryMatches(haystack, query);
  }

  bool _quickQueryMatches(String haystack, String query) {
    final tokens = RegExp(r'-?"[^"]+"|\S+').allMatches(query);
    for (final match in tokens) {
      final token = match.group(0)!;
      final exclude = token.startsWith('-');
      final term = (exclude ? token.substring(1) : token)
          .replaceAll(RegExp(r'^"|"$'), '')
          .toLowerCase();
      if (term.isEmpty) continue;
      final present = haystack.contains(term);
      if (exclude ? present : !present) return false;
    }
    return true;
  }

  String _quickCollectionType(Object? value) =>
      value is String && value.isNotEmpty ? value : 'other';

  String _quickResolveCollection(
      List<Map<String, dynamic>> catalog, String rawId) {
    final id = _safeCollectionId(rawId);
    if (id.isEmpty) return '';
    if (catalog.any((codex) => codex['id'] == id)) return id;
    final matches = catalog.where((codex) {
      return _asList(codex['aliases']).any((alias) => alias == id);
    }).toList();
    if (matches.length != 1) {
      throw const FormatException(
          'QuickTagCloud collection alias is unknown or ambiguous');
    }
    return _string(matches.single['id']);
  }

  Map<String, dynamic> _normalizeQuickMeta(Map<String, dynamic> value) {
    final id = _safeCollectionId(value['id']);
    if (id.isEmpty) return <String, dynamic>{};
    return <String, dynamic>{
      ...value,
      'id': id,
      'title': _string(value['title']),
      'author': _string(value['author']),
      'version': _string(value['version']),
      'entryCount': _integer(value['entryCount']),
      'imagedCount': _integer(value['imagedCount']),
      'cover': _string(value['cover']),
      'coverCodexId': _safeCollectionId(value['coverCodexId']),
      'nsfw': _truthy(value['nsfw']),
      'type': _quickCollectionType(value['type']),
      'aliases': _asList(value['aliases']),
      'dataUrl': _string(value['dataUrl']),
      'assetBaseUrl': _string(value['assetBaseUrl']),
      'assetPathMode': _string(value['assetPathMode']),
    };
  }

  List<_QuickCategory> _quickCategories(
    List<Map<String, dynamic>> entries,
    Object? tree,
    Object? empty,
  ) {
    final nodes = <String, _QuickCategory>{};
    void addPath(List<String> path) {
      for (var index = 1; index <= path.length; index++) {
        final prefix = path.take(index).toList(growable: false);
        final key = jsonEncode(prefix);
        nodes.putIfAbsent(
          key,
          () => _QuickCategory(prefix, _quickPathCode(prefix)),
        );
      }
    }

    void walk(Object? current, List<String> parent) {
      for (final rawNode in _asList(current)) {
        final node = _asMap(rawNode);
        final name = _string(node['name']);
        if (name.isEmpty) continue;
        final path = [...parent, name];
        addPath(path);
        walk(node['children'], path);
      }
    }

    walk(tree, const []);
    for (final rawPath in _asList(empty)) {
      final path = _stringList(rawPath);
      if (path.length == _asList(rawPath).length && path.isNotEmpty) {
        addPath(path);
      }
    }
    for (final entry in entries) {
      final path = _stringList(entry['path']);
      for (var index = 1; index <= path.length; index++) {
        final prefix = path.take(index).toList(growable: false);
        final key = jsonEncode(prefix);
        final node = nodes.putIfAbsent(
          key,
          () => _QuickCategory(prefix, _quickPathCode(prefix)),
        );
        node.count++;
      }
    }
    return nodes.values.toList(growable: false);
  }

  String _quickPathCode(List<String> path) {
    if (path.isEmpty) return '';
    var hash = 0x811c9dc5;
    for (final unit in path.join('\u001f').codeUnits) {
      hash = ((hash ^ (unit & 0xff)) * 0x01000193) & 0xffffffff;
      hash = ((hash ^ (unit >> 8)) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(36);
  }

  _QuickLink? _quickLink(String value) {
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'novelai.quicktagcloud.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw const FormatException('Invalid QuickTagCloud link');
    }
    String fragmentEntry = '';
    if (uri.fragment.isNotEmpty) {
      try {
        fragmentEntry = Uri.splitQueryString(uri.fragment)['entry'] ?? '';
      } catch (_) {
        fragmentEntry = '';
      }
    }
    return _QuickLink(
      collectionId:
          uri.queryParameters['c'] ?? uri.queryParameters['codex'] ?? '',
      path: uri.queryParametersAll['path'] ?? const [],
      code: uri.queryParameters['p'] ?? '',
      entry: uri.queryParameters['entry'] ?? fragmentEntry,
      query: uri.queryParameters['q'] ?? '',
    );
  }

  bool _isQuickTagUri(Uri uri, Set<String> hosts) {
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443) &&
        hosts.contains(uri.host.toLowerCase());
  }

  Uri _trustedQuickUri(Uri uri, Set<String> hosts) {
    if (!_isQuickTagUri(uri, hosts)) {
      throw const FormatException(
          'QuickTagCloud returned an untrusted data host');
    }
    return uri;
  }

  Uri? _httpsUri(Object? value, Set<String> hosts) {
    final uri = Uri.tryParse(_string(value));
    if (uri == null || !_isQuickTagUri(uri, hosts)) return null;
    return uri;
  }

  String _hostOf(Object? value) {
    final raw = _string(value).trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || uri.userInfo.isNotEmpty || uri.host.isEmpty) return '';
    return uri.host.toLowerCase();
  }

  bool _isSafeQuickJsonPath(String value) {
    return RegExp(r'^[-a-z0-9_/]+\.json$', caseSensitive: false)
            .hasMatch(value) &&
        !value.split('/').any((segment) => segment == '..' || segment == '.');
  }

  String _safeCollectionId(Object? value) {
    final normalized = _string(value).trim();
    return RegExp(r'^[a-z0-9][a-z0-9_-]{0,127}$', caseSensitive: false)
            .hasMatch(normalized)
        ? normalized
        : '';
  }

  String _encodePath(String value) => value.split('/').map((part) {
        String decoded;
        try {
          decoded = Uri.decodeComponent(part);
        } catch (_) {
          decoded = part;
        }
        return Uri.encodeComponent(decoded);
      }).join('/');

  Future<OnlineGalleryItem> _parseTagsGalleryDetail(
    String raw,
    String id, {
    List<OnlineGalleryMedia> fallbackMedia = const [],
  }) async {
    final identity = _parseTagsGalleryId(id);
    final document = _parseTagsGalleryHtml(raw);
    final bodyHtml = _cleanBodyHtml(document);
    final buttons = document.querySelectorAll('button').where((button) {
      return (_attribute(button, 'aria-label') ?? '').startsWith('Copy tag: ');
    }).toList(growable: false);
    if (buttons.isEmpty) {
      throw const FormatException('TAGS_GALLERY_LAYOUT_CHANGED');
    }
    final tag = _attribute(buttons.first, 'aria-label')!
        .substring('Copy tag: '.length)
        .trim();
    if (tag.isEmpty) {
      throw const FormatException('TAGS_GALLERY_LAYOUT_CHANGED');
    }
    final prompt = _tagsGalleryPrompt(document, identity, tag);
    final detailMedia = _tagsGalleryDetailMedia(bodyHtml, id, identity.model);
    final media = detailMedia.isNotEmpty ? detailMedia : fallbackMedia;
    final tags = _tagsForCategory(identity.category, tag);
    return OnlineGalleryItem(
      source: OnlineGallerySource.tagsGallery,
      id: id,
      title: tag,
      author: identity.category == 'artist' ? tag : '',
      description: tag,
      sourceUrl: _tagsGalleryDetailUrl(identity),
      prompt: prompt,
      categoryPath: [identity.category],
      tags: tags,
      media: media,
      mediaCount: media.length,
      metadata: {
        'sourceUrl': _tagsGalleryDetailUrl(identity),
        'model': identity.model == 'v5'
            ? 'NAI Diffusion Anime V5 Full'
            : 'NAI Diffusion Anime V4.5 Full',
      },
    );
  }

  List<OnlineGalleryMedia> _tagsGalleryFallbackMedia(
    OnlineGalleryItem item,
    String model,
  ) {
    final media = <OnlineGalleryMedia>[];
    for (final candidate in item.media) {
      String modelUrl(String value) {
        final safe = _safeTagsGalleryImageUrl(value);
        return _imageBelongsToModel(safe, model) ? safe : '';
      }

      final previewUrl = modelUrl(candidate.previewUrl);
      final displayUrl = modelUrl(candidate.displayUrl);
      final downloadUrl = modelUrl(candidate.downloadUrl);
      if (previewUrl.isEmpty && displayUrl.isEmpty && downloadUrl.isEmpty) {
        continue;
      }
      // Preserve listing URLs and their download semantics. They remain the
      // source's card media; do not synthesize a higher-resolution URL here.
      media.add(OnlineGalleryMedia(
        id: candidate.id.isNotEmpty
            ? candidate.id
            : '${item.id}:listing:${media.length}',
        previewUrl: previewUrl,
        displayUrl: displayUrl,
        downloadUrl: downloadUrl,
        width: candidate.width,
        height: candidate.height,
        extension: candidate.extension,
      ));
    }
    return media;
  }

  _ParsedTagsPage _parseTagsGalleryPage(
    String raw,
    String category,
    String model,
  ) {
    final document = _parseTagsGalleryHtml(raw);
    final plain = _normalizedText(document.body?.text ?? document.text ?? '');
    final countMatch = RegExp(r'\bhits\s*=\s*([\d,]+)', caseSensitive: false)
        .firstMatch(plain);
    if (countMatch == null) {
      throw const FormatException('TAGS_GALLERY_LAYOUT_CHANGED');
    }
    final total = int.tryParse(countMatch.group(1)!.replaceAll(',', ''));
    if (total == null || total < 0) {
      throw const FormatException('TAGS_GALLERY_LAYOUT_CHANGED');
    }
    final cards = document.querySelectorAll('a[aria-label]');
    final items = <OnlineGalleryItem>[];
    for (final anchor in cards) {
      final label = _attribute(anchor, 'aria-label') ?? '';
      if (!label.startsWith('Open detail: ')) continue;
      final slug = _listingSlug(_attribute(anchor, 'href') ?? '', category);
      final title = label.substring('Open detail: '.length).trim();
      if (slug.isEmpty || title.isEmpty) continue;
      final id = _tagsGalleryId(category, slug, model);
      final cover = _tagsGalleryListingMedia(anchor, id, model);
      final card = _tagsGalleryCardContainer(anchor);
      final cardText = _normalizedText(card?.text ?? anchor.text);
      final score = _parseMetric(cardText, RegExp(r'▲\s*([\d,]+)'));
      final favoriteCount = _tagsGalleryFavoriteCount(card);
      items.add(OnlineGalleryItem(
        source: OnlineGallerySource.tagsGallery,
        id: id,
        title: title,
        author: category == 'artist' ? title : '',
        description: title,
        sourceUrl:
            _tagsGalleryDetailUrl(_TagsGalleryIdentity(category, slug, model)),
        prompt: title,
        categoryPath: [category],
        tags: _tagsForCategory(category, title),
        media: cover.previewUrl.isEmpty && cover.displayUrl.isEmpty
            ? const []
            : [cover],
        mediaCount: cover.displayUrl.isEmpty ? 0 : 1,
        score: score,
        favoriteCount: favoriteCount,
      ));
    }
    if (total > 0 && items.isEmpty) {
      throw const FormatException('TAGS_GALLERY_LAYOUT_CHANGED');
    }
    return _ParsedTagsPage(total, items);
  }

  Document _parseTagsGalleryHtml(String raw) {
    if (raw.length > _tagsGalleryMaxHtmlChars) {
      throw const FormatException('TAGS_GALLERY_RESPONSE_TOO_LARGE');
    }
    final document = parse(raw);
    for (final script in document.querySelectorAll('script,style')) {
      script.remove();
    }
    return document;
  }

  String _cleanBodyHtml(Document document) =>
      document.body?.innerHtml ?? document.outerHtml;

  String _tagsGalleryCategory(String value) {
    if (value.isEmpty) return 'artist';
    if (_tagsGalleryCategories.contains(value)) return value;
    throw const FormatException('TAGS_GALLERY_INVALID_CATEGORY');
  }

  String _tagsGalleryModel(String value) {
    if (value == 'v4-5' || value == 'v5') return value;
    throw const FormatException('TAGS_GALLERY_INVALID_MODEL');
  }

  String _tagsGallerySort(String value) {
    if (value == 'default' || value == 'score') return 'score';
    if (const {'count', 'name', 'favorites'}.contains(value)) return value;
    throw const FormatException('TAGS_GALLERY_INVALID_SORT');
  }

  String _tagsGalleryId(String category, String slug, String model) =>
      model == 'v5'
          ? 'v5/$category/${Uri.encodeComponent(slug)}'
          : '$category/${Uri.encodeComponent(slug)}';

  _TagsGalleryIdentity _parseTagsGalleryId(String id) {
    if (id.isEmpty || id.length > 1200) {
      throw const FormatException('TAGS_GALLERY_INVALID_ID');
    }
    final parts = id.split('/');
    late final String model;
    late final String category;
    late final String rawSlug;
    if (parts.length == 2) {
      model = 'v4-5';
      category = parts[0];
      rawSlug = parts[1];
    } else if (parts.length == 3 && parts[0] == 'v5') {
      model = 'v5';
      category = parts[1];
      rawSlug = parts[2];
    } else {
      throw const FormatException('TAGS_GALLERY_INVALID_ID');
    }
    final normalizedCategory = _tagsGalleryCategory(category);
    String slug;
    try {
      slug = Uri.decodeComponent(rawSlug);
    } catch (_) {
      throw const FormatException('TAGS_GALLERY_INVALID_ID');
    }
    if (slug.isEmpty ||
        slug == '.' ||
        slug == '..' ||
        slug.length > 500 ||
        RegExp(r'[/\\?#\u0000-\u001f\u007f]').hasMatch(slug)) {
      throw const FormatException('TAGS_GALLERY_INVALID_ID');
    }
    return _TagsGalleryIdentity(normalizedCategory, slug, model);
  }

  String _tagsGalleryDetailUrl(_TagsGalleryIdentity identity) =>
      '$_tagsGalleryOrigin/${identity.category}/${Uri.encodeComponent(identity.slug)}';

  String _listingSlug(String href, String category) {
    if (href.isEmpty) return '';
    final uri = Uri.tryParse('$_tagsGalleryOrigin/')?.resolve(href);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'tags.gallery' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.hasQuery ||
        uri.hasFragment) {
      return '';
    }
    final parts = uri.pathSegments;
    if (parts.length != 2 || parts[0] != category) return '';
    final slug = parts[1];
    if (slug.isEmpty ||
        slug == '.' ||
        slug == '..' ||
        slug.length > 500 ||
        RegExp(r'[/\\?#\u0000-\u001f\u007f]').hasMatch(slug)) {
      return '';
    }
    return slug;
  }

  OnlineGalleryMedia _tagsGalleryListingMedia(
    Element anchor,
    String id,
    String model,
  ) {
    final image = anchor.querySelector('img');
    final source = anchor.querySelector('source');
    final Map<String, String> attrs = image == null
        ? const <String, String>{}
        : Map<String, String>.from(image.attributes);
    final Map<String, String> sourceAttrs = source == null
        ? const <String, String>{}
        : Map<String, String>.from(source.attributes);
    return _tagsGalleryMediaFromAttributes(attrs, sourceAttrs, id, model);
  }

  OnlineGalleryMedia _tagsGalleryMediaFromAttributes(
    Map<String, String> image,
    Map<String, String> source,
    String id,
    String model,
  ) {
    final rawDisplay = image['src'] ?? image['data-src'] ?? '';
    final candidateDisplay = _safeTagsGalleryImageUrl(rawDisplay);
    final displayUrl =
        _imageBelongsToModel(candidateDisplay, model) ? candidateDisplay : '';
    final previews = [
      ..._sourceSetUrls(source['srcset'] ?? ''),
      ..._sourceSetUrls(image['srcset'] ?? ''),
    ].map(_safeTagsGalleryImageUrl).where((url) {
      return url.isNotEmpty && _imageBelongsToModel(url, model);
    }).toList(growable: false);
    final previewUrl = previews.isNotEmpty ? previews.first : displayUrl;
    return OnlineGalleryMedia(
      id: id,
      previewUrl: previewUrl,
      displayUrl: displayUrl,
      downloadUrl: displayUrl,
      width: _integer(image['width']),
      height: _integer(image['height']),
      extension: _extension(displayUrl.isNotEmpty ? displayUrl : previewUrl),
    );
  }

  String _safeTagsGalleryImageUrl(String raw) {
    if (raw.trim().isEmpty) return '';
    final uri = Uri.tryParse('$_tagsGalleryOrigin/')?.resolve(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'tags.gallery' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !RegExp(r'^/images/(?:thumbs/)?[^/]+\.(?:webp|png|jpe?g|gif|avif)$',
                caseSensitive: false)
            .hasMatch(uri.path)) {
      return '';
    }
    return uri.toString();
  }

  bool _imageBelongsToModel(String url, String model) {
    if (url.isEmpty) return false;
    final name = Uri.parse(url).pathSegments.last;
    return model == 'v5' ? name.startsWith('v5_') : name.startsWith('v45_');
  }

  List<String> _sourceSetUrls(String raw) => raw
      .split(',')
      .map((part) => part.trim().split(RegExp(r'\s+')).first)
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  Element? _tagsGalleryCardContainer(Element anchor) {
    Element? current = anchor.parent;
    Element? fallback;
    var depth = 0;
    while (current != null && depth++ < 8) {
      if (current.localName == 'body' || current.localName == 'html') break;
      final cards = current.querySelectorAll('a[aria-label^="Open detail: "]');
      if (cards.length > 1) break;
      fallback ??= current;
      final text = _normalizedText(current.text);
      if (RegExp(r'▲\s*[\d,]+').hasMatch(text) ||
          current.querySelector('[aria-label*="いいね"], [aria-label*="like"]') !=
              null) {
        return current;
      }
      current = current.parent;
    }
    return fallback;
  }

  int _tagsGalleryFavoriteCount(Element? card) {
    if (card == null) return 0;
    for (final element in card.querySelectorAll('[aria-label]')) {
      final label = _attribute(element, 'aria-label') ?? '';
      final match = RegExp(
        r'(?:累計\s*)?いいね\s*([\d,]+)|(?:total\s*)?likes?\s*([\d,]+)',
        caseSensitive: false,
      ).firstMatch(label);
      final value = match?.group(1) ?? match?.group(2);
      if (value != null) return _integer(value.replaceAll(',', ''));
    }
    return 0;
  }

  int _parseMetric(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    return _integer(match?.group(1)?.replaceAll(',', ''));
  }

  Map<String, List<String>> _tagsForCategory(String category, String title) {
    if (category == 'artist') {
      return {
        'artists': [title]
      };
    }
    if (category == 'character') {
      return {
        'characters': [title]
      };
    }
    if (category == 'copyright') {
      return {
        'copyrights': [title]
      };
    }
    return {
      'general': [title]
    };
  }

  String _tagsGalleryPrompt(
    Document document,
    _TagsGalleryIdentity identity,
    String tag,
  ) {
    final elements = document.body?.querySelectorAll('*') ?? const <Element>[];
    final promptStart = elements.indexWhere((element) =>
        RegExp(r'PROMPT\s*(?:/|:|-)', caseSensitive: false)
            .hasMatch(_ownText(element)));
    if (promptStart < 0) return tag;
    String? currentHeadingModel;
    final candidates = <_PromptCandidate>[];
    for (var index = promptStart; index < elements.length; index++) {
      final element = elements[index];
      final ownText = _ownText(element);
      final heading =
          RegExp(r'PROMPT\s*(?:/|:|-)\s*([^<\n]{0,80})', caseSensitive: false)
              .firstMatch(ownText);
      if (heading != null) {
        currentHeadingModel = _modelMarker(heading.group(1) ?? '');
      }
      if (element.localName != 'button') continue;
      final label = _attribute(element, 'aria-label') ?? '';
      if (!label.startsWith('Copy tag: ')) continue;
      final value = label.substring('Copy tag: '.length).trim();
      if (value.isEmpty || value == tag || value == identity.slug) continue;
      candidates.add(_PromptCandidate(
        value,
        _ancestorModel(element) ?? currentHeadingModel,
      ));
    }
    for (final candidate in candidates) {
      if (candidate.model == identity.model) return candidate.value;
    }
    for (final candidate in candidates) {
      if (candidate.model == null) return candidate.value;
    }
    return tag;
  }

  String? _ancestorModel(Element element) {
    Node? current = element;
    while (current != null) {
      if (current is Element) {
        final marker = current.attributes['data-model'];
        if (marker != null) {
          final model = _modelMarker(marker);
          if (model != null) return model;
        }
      }
      current = current.parent;
    }
    return null;
  }

  String? _modelMarker(String value) {
    if (RegExp(r'(?:^|[^\w])(?:v5|NAI Diffusion Anime V5 Full)(?:$|[^\w])',
            caseSensitive: false)
        .hasMatch(value)) {
      return 'v5';
    }
    if (RegExp(
            r'(?:^|[^\w])(?:v4[.-]?5|NAI Diffusion Anime V4\.5 Full)(?:$|[^\w])',
            caseSensitive: false)
        .hasMatch(value)) {
      return 'v4-5';
    }
    return null;
  }

  List<OnlineGalleryMedia> _tagsGalleryDetailMedia(
    String html,
    String id,
    String model,
  ) {
    final comparison =
        RegExp(r'V5\s+vs\s+V4\.5\s*[·-]\s*SAME\s+SEED', caseSensitive: false)
            .firstMatch(html);
    if (comparison == null) return const [];
    final firstImage = html.toLowerCase().indexOf('<img', comparison.end);
    if (firstImage < 0) return const [];
    final lower = html.toLowerCase();
    final statsText = lower.indexOf('top score', firstImage);
    final statsRow = lower.indexOf('class="grid grid-cols-3', firstImage);
    final endCandidates =
        [statsText, statsRow].where((index) => index >= 0).toList();
    final end = endCandidates.isEmpty
        ? (html.length < firstImage + 5000 ? html.length : firstImage + 5000)
        : endCandidates.reduce((left, right) => left < right ? left : right);
    final region = html.substring(firstImage, end);
    final document = parse('<div>$region</div>');
    final seen = <String>{};
    final media = <OnlineGalleryMedia>[];
    for (final image in document.querySelectorAll('img')) {
      final candidate = _safeTagsGalleryImageUrl(
          image.attributes['src'] ?? image.attributes['data-src'] ?? '');
      if (!_imageBelongsToModel(candidate, model) ||
          Uri.parse(candidate).path.contains('/thumbs/') ||
          !seen.add(candidate)) {
        continue;
      }
      final parsed = _tagsGalleryMediaFromAttributes(
        Map<String, String>.from(image.attributes),
        const <String, String>{},
        '$id:media:${media.length}',
        model,
      );
      media.add(parsed);
    }
    return media;
  }

  String? _attribute(Element element, String key) =>
      element.attributes[key.toLowerCase()];

  String _ownText(Element element) =>
      element.nodes.whereType<Text>().map((text) => text.text).join(' ').trim();

  String _normalizedText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  int _pageSize(int value) =>
      const [12, 24, 48, 60].contains(value) ? value : 12;

  int _requestedPage(OnlineGalleryQuery query) {
    final cursorPage = int.tryParse(query.cursor ?? '');
    final value = cursorPage ?? query.page;
    if (value < 1 || value > 100000) {
      throw const FormatException('Gallery page is invalid');
    }
    return value;
  }

  _PageSlice _slicePage(
    List<OnlineGalleryItem> items,
    int requestedPage,
    int pageSize,
  ) {
    final totalPages =
        items.isEmpty ? 1 : (items.length + pageSize - 1) ~/ pageSize;
    final page = requestedPage > totalPages ? totalPages : requestedPage;
    final offset = (page - 1) * pageSize;
    final end =
        offset + pageSize < items.length ? offset + pageSize : items.length;
    return _PageSlice(
      page,
      items.sublist(offset < items.length ? offset : items.length, end),
      offset + pageSize < items.length,
    );
  }

  List<OnlineGalleryItem> _sortQuickItems(
    List<OnlineGalleryItem> items,
    String sort,
    int seed,
  ) {
    // OnlineGalleryQuery's shared constructor defaults to score; the QuickTag
    // source default is the published order represented by "default".
    if (sort == 'score') sort = 'default';
    if (!const {'default', 'name', 'name-desc', 'random'}.contains(sort)) {
      throw FormatException('Unsupported quicktag sort: $sort');
    }
    final result = List<OnlineGalleryItem>.of(items);
    if (sort == 'default') return result;
    if (sort == 'name' || sort == 'name-desc') {
      final indexed = result.indexed.toList();
      indexed.sort((left, right) {
        final compared = _naturalCompare(left.$2.title, right.$2.title) *
            (sort == 'name' ? 1 : -1);
        return compared != 0 ? compared : left.$1.compareTo(right.$1);
      });
      return indexed.map((value) => value.$2).toList(growable: false);
    }
    var state = seed & 0xffffffff;
    int nextUint32() {
      state = (state + 0x6d2b79f5) & 0xffffffff;
      var value = state;
      value = ((value ^ (value >>> 15)) * (value | 1)) & 0xffffffff;
      final mixed = (((value ^ (value >>> 7)) * (value | 61)) & 0xffffffff);
      value = (value ^ ((value + mixed) & 0xffffffff)) & 0xffffffff;
      return (value ^ (value >>> 14)) & 0xffffffff;
    }

    for (var index = result.length - 1; index > 0; index--) {
      final target = (nextUint32() / 0x100000000 * (index + 1)).floor();
      final hold = result[index];
      result[index] = result[target];
      result[target] = hold;
    }
    return result;
  }

  int _naturalCompare(String left, String right) {
    final leftParts =
        RegExp(r'\d+|\D+').allMatches(left.toLowerCase()).toList();
    final rightParts =
        RegExp(r'\d+|\D+').allMatches(right.toLowerCase()).toList();
    final limit = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < limit; index++) {
      final a = leftParts[index].group(0)!;
      final b = rightParts[index].group(0)!;
      final aNumber = int.tryParse(a);
      final bNumber = int.tryParse(b);
      final compared = aNumber != null && bNumber != null
          ? aNumber.compareTo(bNumber)
          : a.compareTo(b);
      if (compared != 0) return compared;
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  bool _isPathPrefix(List<String> prefix, List<String> path) {
    if (prefix.length > path.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (prefix[index] != path[index]) return false;
    }
    return true;
  }

  List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().where((part) => part.isNotEmpty).toList()
      : const [];

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<dynamic> _asList(Object? value) => value is List ? value : const [];

  String _string(Object? value) => value == null ? '' : value.toString();

  int _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(_string(value).replaceAll(',', '')) ?? 0;
  }

  bool _truthy(Object? value) =>
      value == true || value == 1 || value == '1' || value == 'true';

  String? _extension(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    final last = uri.pathSegments.last;
    final index = last.lastIndexOf('.');
    if (index < 0 || index == last.length - 1) return null;
    final extension = last.substring(index + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension) ? extension : null;
  }
}

class _QuickCatalog {
  final String baseUrl, release, releaseBaseUrl;
  final Map<String, dynamic> media;
  final Set<String> allowedHosts;
  final Map<String, Map<String, dynamic>> manifestFiles;
  final List<Map<String, dynamic>> codexes;

  const _QuickCatalog({
    required this.baseUrl,
    required this.release,
    required this.releaseBaseUrl,
    required this.media,
    required this.allowedHosts,
    required this.manifestFiles,
    required this.codexes,
  });
}

class _QuickCodex {
  final String id, title, author, version;
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> entries;

  const _QuickCodex({
    required this.id,
    required this.title,
    required this.author,
    required this.version,
    required this.metadata,
    required this.entries,
  });
}

class _QuickCategory {
  final List<String> path;
  final String code;
  int count = 0;

  _QuickCategory(this.path, this.code);
}

class _QuickLink {
  final String collectionId, code, entry, query;
  final List<String> path;

  const _QuickLink({
    required this.collectionId,
    required this.path,
    required this.code,
    required this.entry,
    required this.query,
  });
}

class _TimedFuture<T> {
  final DateTime createdAt = DateTime.now();
  final Future<T> future;
  _TimedFuture(this.future);
}

class _ParsedTagsPage {
  final int total;
  final List<OnlineGalleryItem> items;
  const _ParsedTagsPage(this.total, this.items);
}

class _TagsGalleryIdentity {
  final String category, slug, model;
  const _TagsGalleryIdentity(this.category, this.slug, this.model);
}

class _PromptCandidate {
  final String value;
  final String? model;
  const _PromptCandidate(this.value, this.model);
}

class _PageSlice {
  final int page;
  final List<OnlineGalleryItem> items;
  final bool hasMore;
  const _PageSlice(this.page, this.items, this.hasMore);
}
