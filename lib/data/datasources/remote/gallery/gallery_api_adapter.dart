import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../domain/entities/online_gallery.dart';
import 'gallery_adapter.dart';
import 'gallery_http.dart';

const _maxGalleryPage = 100000;
const _maxBooruPageSize = 60;
const _maxCivitaiCursorLength = 4096;
const _artistTagPageSize = 1000;
const _artistTagMaxPage = 1000;
const _artistCountCacheAge = Duration(days: 7);
const _aitagApiPageSize = 60;
const _aitagDefaultAssetBase = 'https://ai-img.10118899.xyz/';

typedef GelbooruCredentialsProvider = Future<OnlineGalleryCredentials?>
    Function();

/// JSON adapters for the public image boards and discovery APIs.
///
/// The [GalleryHttp] instance is supplied by the gallery composition root and
/// owns its own Dio client, so these requests never inherit generation auth.
class GalleryApiAdapter implements GalleryAdapter {
  final GalleryHttp http;
  final GelbooruCredentialsProvider? gelbooruCredentials;
  final Map<String, _CachedArtistCount> _artistCounts = {};
  Future<String>? _aitagAssetBase;

  GalleryApiAdapter(
    this.http, {
    this.gelbooruCredentials,
  });

  @override
  Future<OnlineGalleryPage> search(OnlineGalleryQuery query) {
    return switch (query.source) {
      OnlineGallerySource.danbooru ||
      OnlineGallerySource.safebooru =>
        _searchDonmai(query),
      OnlineGallerySource.gelbooru => _searchGelbooru(query),
      OnlineGallerySource.civitai => _searchCivitai(query),
      OnlineGallerySource.aitag => _searchAitag(query),
      OnlineGallerySource.artistRanking => query.collectionId == null
          ? _searchArtistRanking(query)
          : _searchArtistPosts(query),
      OnlineGallerySource.quickTag ||
      OnlineGallerySource.tagsGallery =>
        throw UnsupportedError('${query.source.label} 由另一个图库适配器处理'),
    };
  }

  @override
  Future<OnlineGalleryItem> detail(
    OnlineGalleryItem item, {
    bool safeOnly = true,
  }) {
    return switch (item.source) {
      OnlineGallerySource.danbooru ||
      OnlineGallerySource.safebooru =>
        _detailDonmai(item),
      OnlineGallerySource.gelbooru => _detailGelbooru(item),
      OnlineGallerySource.civitai => _detailCivitai(item, safeOnly),
      OnlineGallerySource.aitag => _detailAitag(item),
      OnlineGallerySource.artistRanking => item.isCollection
          ? _detailArtist(item)
          : item.metadata['kind'] == 'artist-post'
              ? _detailDonmai(item)
              : Future.error(StateError('这条画师排行榜记录不是可打开的作品。')),
      OnlineGallerySource.quickTag ||
      OnlineGallerySource.tagsGallery =>
        Future.error(UnsupportedError('${item.source.label} 由另一个图库适配器处理')),
    };
  }

  Future<OnlineGalleryPage> _searchDonmai(
    OnlineGalleryQuery query, {
    OnlineGallerySource? itemSource,
    String? artistName,
  }) async {
    final requestSource = query.source;
    final resultSource = itemSource ?? requestSource;
    final base = requestSource == OnlineGallerySource.safebooru
        ? 'https://safebooru.donmai.us'
        : 'https://danbooru.donmai.us';
    final page = _page(query.page);
    final pageSize = _booruPageSize(query.pageSize);
    final tags = _buildBooruTags(query);
    final referer = '$base/';

    final countFuture = _optionalDonmaiPostCount(base, tags, referer);
    final raw = await http.json(
      '$base/posts.json',
      params: {'tags': tags, 'limit': pageSize, 'page': page},
      referer: referer,
    );
    final posts = _requireList(raw, '${requestSource.label} posts');
    final items = posts
        .map((post) => _donmaiItem(
              post,
              resultSource,
              metadata: artistName == null
                  ? const {}
                  : {'kind': 'artist-post', 'artist': artistName},
            ))
        .where((item) => item.id.isNotEmpty && item.cover.previewUrl.isNotEmpty)
        .toList(growable: false);
    final total = await countFuture;
    return OnlineGalleryPage(
      items: items,
      total: total,
      hasMore:
          total == null ? posts.length >= pageSize : page * pageSize < total,
    );
  }

  Future<int?> _optionalDonmaiPostCount(
    String base,
    String tags,
    String referer,
  ) async {
    try {
      final raw = await http.json(
        '$base/counts/posts.json',
        params: {'tags': tags},
        referer: referer,
      );
      final counts = _map(_map(raw)['counts']);
      return _nullableNonNegativeInt(counts['posts']);
    } catch (_) {
      // The post page is still useful when the optional total-count endpoint
      // is unavailable or rate limited.
      return null;
    }
  }

  OnlineGalleryItem _donmaiItem(
    Object? value,
    OnlineGallerySource source, {
    Map<String, dynamic> metadata = const {},
  }) {
    final post = _map(value);
    final id = _text(post['id']);
    final artists = _spaceTags(post['tag_string_artist']);
    final characters = _spaceTags(post['tag_string_character']);
    final copyrights = _spaceTags(post['tag_string_copyright']);
    final general = _spaceTags(post['tag_string_general']);
    final meta = _spaceTags(post['tag_string_meta']);
    final allTags = _spaceTags(post['tag_string']);
    final base = source == OnlineGallerySource.safebooru
        ? 'https://safebooru.donmai.us'
        : 'https://danbooru.donmai.us';
    final media = _makeMedia(
      '${source.id}:$id:0',
      _https(post['preview_file_url'], base),
      _https(post['large_file_url'] ?? post['sample_url'] ?? post['file_url'],
          base),
      _https(post['file_url'] ?? post['large_file_url'] ?? post['sample_url'],
          base),
      _integer(post['image_width']),
      _integer(post['image_height']),
    );
    return OnlineGalleryItem(
      source: source,
      id: id,
      title: characters.firstOrNull ?? copyrights.firstOrNull ?? '#$id',
      author: artists.join(', '),
      description: allTags.take(16).join(' · '),
      sourceUrl: '$base/posts/${Uri.encodeComponent(id)}',
      prompt: allTags.join(', '),
      rating: _text(post['rating']).isEmpty ? 'g' : _text(post['rating']),
      createdAt: _text(post['created_at']),
      score: _integer(post['score']),
      favoriteCount: _integer(post['fav_count']),
      mediaCount: 1,
      media: [media],
      tags: {
        'artists': artists,
        'characters': characters,
        'copyrights': copyrights,
        'general': general,
        'meta': meta,
      },
      metadata: metadata,
    );
  }

  Future<OnlineGalleryPage> _searchGelbooru(OnlineGalleryQuery query) async {
    final page = _page(query.page);
    final pageSize = _booruPageSize(query.pageSize);
    final tags = _buildBooruTags(query);
    final credentials = await _requireGelbooruCredentials();
    final raw = await http.json(
      'https://gelbooru.com/index.php',
      params: {
        'page': 'dapi',
        's': 'post',
        'q': 'index',
        'json': '1',
        'limit': pageSize,
        'pid': page - 1,
        'tags': tags,
        'api_key': credentials.apiKey,
        'user_id': credentials.userId,
      },
      referer: 'https://gelbooru.com/',
    );
    final posts = _gelbooruPosts(raw);
    final items = posts
        .map(_gelbooruItem)
        .where((item) => item.id.isNotEmpty && item.cover.previewUrl.isNotEmpty)
        .toList(growable: false);
    final attributes = _map(_map(raw)['@attributes']);
    final total = _nullablePositiveInt(attributes['count']);
    return OnlineGalleryPage(
      items: items,
      total: total,
      hasMore:
          total == null ? posts.length >= pageSize : page * pageSize < total,
    );
  }

  Future<OnlineGalleryCredentials> _requireGelbooruCredentials() async {
    final credentials = await gelbooruCredentials?.call();
    if (credentials == null ||
        credentials.userId.trim().isEmpty ||
        credentials.apiKey.trim().isEmpty) {
      throw StateError('请先在图库设置中填写 Gelbooru 的 User ID 和 API Key。');
    }
    final userId = credentials.userId.trim();
    if (!RegExp(r'^\d+$').hasMatch(userId)) {
      throw StateError('Gelbooru User ID 必须为数字，请在图库设置中检查。');
    }
    return OnlineGalleryCredentials(
      userId: userId,
      apiKey: credentials.apiKey.trim(),
    );
  }

  List<Object?> _gelbooruPosts(Object? value) {
    if (value is List) return List<Object?>.from(value);
    if (value is! Map) {
      throw const FormatException('Gelbooru 返回了无效的 JSON 数据。');
    }
    final rawPosts = _map(value)['post'];
    if (rawPosts == null) return const [];
    if (rawPosts is List) return List<Object?>.from(rawPosts);
    if (rawPosts is Map) return [rawPosts];
    throw const FormatException('Gelbooru 返回了无效的帖子列表。');
  }

  OnlineGalleryItem _gelbooruItem(Object? value) {
    final post = _map(value);
    final id = _text(post['id']);
    final allTags = _spaceTags(post['tags']);
    final media = _makeMedia(
      'gelbooru:$id:0',
      _https(post['preview_url'], 'https://gelbooru.com'),
      _https(post['sample_url'] ?? post['file_url'], 'https://gelbooru.com'),
      _https(post['file_url'] ?? post['sample_url'], 'https://gelbooru.com'),
      _integer(post['width']),
      _integer(post['height']),
    );
    return OnlineGalleryItem(
      source: OnlineGallerySource.gelbooru,
      id: id,
      title: '#$id',
      author: _text(post['owner']),
      description: allTags.take(16).join(' · '),
      sourceUrl:
          'https://gelbooru.com/index.php?page=post&s=view&id=${Uri.encodeComponent(id)}',
      prompt: allTags.join(', '),
      rating: _text(post['rating']).isEmpty ? 'general' : _text(post['rating']),
      createdAt: _text(post['created_at']),
      score: _integer(post['score']),
      mediaCount: 1,
      media: [media],
      tags: {'general': allTags},
    );
  }

  Future<OnlineGalleryPage> _searchCivitai(OnlineGalleryQuery query) async {
    final page = _page(query.page, max: _maxGalleryPage);
    final cursor = query.cursor ?? '';
    if (cursor.length > _maxCivitaiCursorLength) {
      throw const FormatException('Civitai 分页游标过长。');
    }
    if (page > 1 && cursor.isEmpty) {
      throw const FormatException('Civitai 后续页面需要上一页返回的游标。');
    }
    final pageSize = _pageSize(query.pageSize, max: 200);
    final params = <String, dynamic>{
      'limit': pageSize,
      'type': 'image',
      'withMeta': 'true',
      'sort': _civitaiSort(query.sort),
      'period': _civitaiPeriod(query.timeRange),
      if (query.safeOnly) 'browsingLevel': '1',
      if (query.query.trim().replaceFirst(RegExp(r'^@'), '').isNotEmpty)
        'username': query.query.trim().replaceFirst(RegExp(r'^@'), ''),
      if (cursor.isNotEmpty) 'cursor': cursor,
    };
    final raw = await http.json(
      'https://civitai.com/api/v1/images',
      params: params,
      referer: 'https://civitai.com/',
    );
    final root = _map(raw);
    if (raw is! Map || root['items'] is! List) {
      throw const FormatException('Civitai 返回了无法识别的图库数据。');
    }
    final rawItems = List<Object?>.from(root['items'] as List);
    final items = rawItems
        .map(_map)
        .where((image) => image.isNotEmpty)
        .where((image) => !query.safeOnly || _civitaiIsSafe(image))
        .map(_civitaiItem)
        .where((item) => item != null)
        .cast<OnlineGalleryItem>()
        .toList(growable: false);
    final nextCursor = _civitaiCursor(root);
    if (cursor.isNotEmpty && cursor == nextCursor) {
      throw const FormatException('Civitai 返回了重复游标，已停止分页。');
    }
    return OnlineGalleryPage(
      items: items,
      nextCursor: nextCursor,
      hasMore: nextCursor != null,
    );
  }

  OnlineGalleryItem? _civitaiItem(Map<String, dynamic> image) {
    if (image['type'] != 'image') return null;
    final id = _positiveId(image['id']);
    final url = _civitaiImageUrl(image['url']);
    if (id.isEmpty || url.isEmpty) return null;
    final media = _makeMedia(
      id,
      url,
      url,
      url,
      _integer(image['width']),
      _integer(image['height']),
    );
    final meta = _mapOrNull(image['meta']);
    final stats = _map(image['stats']);
    final reactionCount = const [
      'likeCount',
      'dislikeCount',
      'heartCount',
      'cryCount',
      'laughCount',
    ].fold<int>(0, (sum, key) => sum + _integer(stats[key]));
    final metadata = <String, dynamic>{
      for (final key in [
        'baseModel',
        'modelVersionIds',
        'postId',
        'nsfw',
        'nsfwLevel',
        'browsingLevel',
        'stats',
      ])
        if (image.containsKey(key)) key: image[key],
      if (meta != null) 'meta': meta,
    };
    return OnlineGalleryItem(
      source: OnlineGallerySource.civitai,
      id: id,
      title: _text(meta?['title']).trim().isEmpty
          ? 'Civitai image $id'
          : _text(meta?['title']),
      author: _text(image['username']),
      description: _text(meta?['description']).trim().isNotEmpty
          ? _text(meta?['description'])
          : _text(image['description']),
      sourceUrl: 'https://civitai.com/images/$id',
      prompt: _civitaiPrompt(meta, 'prompt'),
      negativePrompt: _civitaiPrompt(meta, 'negativePrompt'),
      rating: _text(image['nsfwLevel']).isNotEmpty
          ? _text(image['nsfwLevel'])
          : _text(image['browsingLevel']),
      createdAt: _text(image['createdAt']),
      score: reactionCount,
      favoriteCount: _firstCount(
          stats, const ['collectedCount', 'collectionCount', 'favoriteCount']),
      viewCount: _firstCount(stats, const ['viewCount']) > 0
          ? _firstCount(stats, const ['viewCount'])
          : _integer(image['viewCount']),
      mediaCount: 1,
      media: [media],
      metadata: metadata,
    );
  }

  String? _civitaiCursor(Map<String, dynamic> response) {
    final metadata = _map(response['metadata']);
    final value = metadata['nextCursor'];
    if (value == null || value == '') return null;
    if (value is! String) {
      throw const FormatException('Civitai 返回了无效的分页游标。');
    }
    final cursor = value;
    if (cursor.isEmpty || cursor.length > _maxCivitaiCursorLength) {
      throw const FormatException('Civitai 返回了无效的分页游标。');
    }
    return cursor;
  }

  bool _civitaiIsSafe(Map<String, dynamic> image) {
    final nsfw = image['nsfw'];
    if (nsfw == true || nsfw == 1 || nsfw == '1' || nsfw == 'true') {
      return false;
    }

    var hasSafeSignal = false;
    final level = image['browsingLevel'];
    if (level != null) {
      final numeric = level is num
          ? level.toDouble()
          : level is String && level.trim().isNotEmpty
              ? double.tryParse(level.trim())
              : null;
      if (numeric == null || (numeric != 0 && numeric != 1)) return false;
      hasSafeSignal = true;
    }
    final nsfwLevel = image['nsfwLevel'];
    if (nsfwLevel != null) {
      if (nsfwLevel is! String || nsfwLevel.toLowerCase() != 'none') {
        return false;
      }
      hasSafeSignal = true;
    }
    if (nsfw == false || nsfw == 0 || nsfw == 'false') hasSafeSignal = true;
    return hasSafeSignal;
  }

  String _civitaiImageUrl(Object? value) {
    final raw = _text(value);
    if (raw.isEmpty || raw != raw.trim()) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.origin != 'https://image.civitai.com' ||
        uri.userInfo.isNotEmpty) {
      return '';
    }
    return raw;
  }

  String _civitaiSort(String sort) => switch (sort) {
        'default' || 'score' => 'Most Reactions',
        'newest' => 'Newest',
        'oldest' => 'Oldest',
        'favorites' => 'Most Collected',
        'comments' => 'Most Comments',
        'random' => 'Random',
        _ => throw FormatException('Civitai 不支持排序方式：$sort'),
      };

  String _civitaiPeriod(String timeRange) => switch (timeRange) {
        'all' => 'AllTime',
        'day' => 'Day',
        'week' => 'Week',
        'month' => 'Month',
        'year' => 'Year',
        _ => throw FormatException('Civitai 不支持时间范围：$timeRange'),
      };

  String _civitaiPrompt(Map<String, dynamic>? metadata, String key) {
    final direct = metadata?[key];
    if (direct is String && direct.trim().isNotEmpty) return direct;
    final nested = _map(metadata?['meta'])[key];
    if (nested is String) return nested;
    if (nested is Map || nested is List) return jsonEncode(nested);
    return '';
  }

  Future<OnlineGalleryPage> _searchAitag(OnlineGalleryQuery query) async {
    final page = _page(query.page, max: 10000);
    final pageSize = _pageSize(query.pageSize, max: _aitagApiPageSize);
    final offset = (page - 1) * pageSize;
    final firstApiPage = offset ~/ _aitagApiPageSize + 1;
    final lastApiPage = (offset + pageSize - 1) ~/ _aitagApiPageSize + 1;
    final monthly = query.sort == 'favorites';
    final range = _aitagPeriod(query.timeRange, monthly: monthly);
    final path = monthly
        ? range == 'current'
            ? '/api/rank/monthly/real'
            : '/api/rank/monthly/fixed'
        : '/api/ai_works_search';

    final apiPages = await Future.wait([
      for (var apiPage = firstApiPage; apiPage <= lastApiPage; apiPage++)
        _fetchAitagSearchPage(
          path,
          apiPage,
          query,
          monthly: monthly,
          period: range,
        ),
    ]);
    final total = apiPages.first.total;
    final combined = apiPages.expand((result) => result.items).toList();
    final sliceStart = offset - (firstApiPage - 1) * _aitagApiPageSize;
    final items =
        combined.skip(sliceStart).take(pageSize).toList(growable: false);
    return OnlineGalleryPage(
      items: items,
      total: total,
      hasMore: offset + items.length < total,
    );
  }

  Future<_AitagSearchPage> _fetchAitagSearchPage(
    String path,
    int apiPage,
    OnlineGalleryQuery query, {
    required bool monthly,
    required String period,
  }) async {
    final params = <String, dynamic>{
      'page': apiPage,
      'page_size': _aitagApiPageSize,
      if (query.query.trim().isNotEmpty)
        'q': query.query
            .trim()
            .substring(0, query.query.trim().length.clamp(0, 2000).toInt()),
      if (!monthly) ...{
        'sort': 'new',
        'time_range': period,
      },
      if (monthly && period != 'current')
        'month': period == 'older' ? 'older' : period.substring(1),
    };
    final raw = await _aitagJson(
      'https://aitag.win$path',
      params: params,
      emptySearchOnNotFound: true,
    );
    final root = _map(raw);
    if (raw is! Map || root['items'] is! List) {
      throw const FormatException('AI TAG 返回了无效的作品列表。');
    }
    final total = _nullableNonNegativeInt(root['total']);
    if (total == null) {
      throw const FormatException('AI TAG 返回了无效的作品总数。');
    }
    final items = (root['items'] as List)
        .map(_map)
        .map((work) => _aitagWorkItem(work, safeOnly: query.safeOnly))
        .whereType<OnlineGalleryItem>()
        .toList(growable: false);
    return _AitagSearchPage(total: total, items: items);
  }

  String _aitagPeriod(String value, {required bool monthly}) {
    if (value == 'all') return monthly ? 'current' : 'all';
    if (value == 'current') return 'current';
    if (value == 'older' ||
        RegExp(r'^y\d{4}$').hasMatch(value) ||
        RegExp(r'^q\d{4}Q[1-4]$').hasMatch(value) ||
        RegExp(r'^m\d{4}-(?:0[1-9]|1[0-2])$').hasMatch(value)) {
      return value;
    }
    throw FormatException('AI TAG 不支持时间范围：$value');
  }

  OnlineGalleryItem? _aitagWorkItem(
    Map<String, dynamic> work, {
    required bool safeOnly,
  }) {
    final id = _positiveId(work['id']);
    if (id.isEmpty) return null;
    final tags = _aitagTagList(work['tags']);
    final aiType = _text(work['AI_type'] ?? work['ai_type'] ?? work['aiType']);
    return OnlineGalleryItem(
      source: OnlineGallerySource.aitag,
      id: id,
      title:
          _text(work['title']).trim().isEmpty ? '#$id' : _text(work['title']),
      author: _text(work['userId'] ?? work['userid']),
      description: _stripHtml(_text(work['caption'])),
      sourceUrl: 'https://aitag.win/i/$id',
      rating: 'general',
      createdAt: _text(work['create_date'] ?? work['createDate']),
      score: _integer(work['total_bookmarks'] ?? work['totalBookmarks']),
      favoriteCount:
          _integer(work['total_bookmarks'] ?? work['totalBookmarks']),
      viewCount: _integer(work['total_view'] ?? work['totalView']),
      mediaCount: _integer(work['image_count'] ?? work['imageCount']),
      tags: {'general': tags},
      metadata: {
        'aiType': aiType,
        'tags': tags,
        'work': work,
        'safeOnly': safeOnly,
      },
    );
  }

  Future<OnlineGalleryItem> _detailAitag(OnlineGalleryItem item) async {
    final id = _positiveId(item.id);
    if (id.isEmpty) throw const FormatException('AI TAG 作品编号无效。');
    final response = await _aitagJson('https://aitag.win/api/work/$id');
    final root = _map(response);
    if (response is! Map || root['work'] is! Map || root['images'] is! List) {
      throw const FormatException('AI TAG 返回了无效的作品详情。');
    }
    final work = _map(root['work']);
    final images = (root['images'] as List).map(_map).toList(growable: false);
    final assetBase = await _aitagAssetUrlBase();
    final media = <OnlineGalleryMedia>[];
    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      final imageId = _positiveId(image['id']);
      final imageType = _text(image['image_type'] ?? image['imageType']);
      final authorId = _text(image['author_id'] ?? image['authorId']);
      final fileName = _text(image['file_name'] ?? image['fileName']);
      if (imageId.isEmpty ||
          imageType.isEmpty ||
          authorId.isEmpty ||
          fileName.isEmpty) {
        continue;
      }
      final encoded = [imageType, authorId, '$fileName.webp']
          .map(Uri.encodeComponent)
          .join('/');
      final url = '$assetBase$encoded';
      media.add(OnlineGalleryMedia(
        id: 'aitag:$id:$imageId',
        previewUrl: url,
        displayUrl: url,
        downloadUrl: url,
        extension: 'webp',
      ));
    }
    final firstImage =
        images.isEmpty ? const <String, dynamic>{} : images.first;
    final aiJson =
        _parseAitagJson(firstImage['ai_json'] ?? firstImage['aiJson']);
    final aiMap = _map(aiJson);
    final prompt = _firstString([
      firstImage['prompt_text'],
      firstImage['promptText'],
      _map(aiMap['prompt'])['positive'],
      aiMap['prompt'],
    ]);
    final negativePrompt = _firstString([
      aiMap['negativePrompt'],
      aiMap['negative_prompt'],
      _map(aiMap['prompt'])['negative'],
    ]);
    final summary = _aitagWorkItem(
      work,
      safeOnly: item.metadata['safeOnly'] == true,
    );
    return item.copyWith(
      title: summary?.title ?? item.title,
      author: summary?.author ?? item.author,
      description: summary?.description ?? item.description,
      sourceUrl: summary?.sourceUrl ?? item.sourceUrl,
      createdAt: summary?.createdAt ?? item.createdAt,
      media: media,
      prompt: prompt,
      negativePrompt: negativePrompt,
      tags: summary?.tags ?? item.tags,
      metadata: {
        ...item.metadata,
        'aiType': work['AI_type'] ?? work['ai_type'] ?? work['aiType'] ?? '',
        'work': work,
        'images': images,
        if (aiJson != null) 'aiJson': aiJson,
      },
    );
  }

  Future<String> _aitagAssetUrlBase() {
    return _aitagAssetBase ??= _loadAitagAssetUrlBase();
  }

  Future<String> _loadAitagAssetUrlBase() async {
    try {
      final response = await _aitagJson('https://aitag.win/api/config');
      final root = _map(response);
      final configured =
          _text(root['asset_base_url'] ?? root['assetBaseUrl']).trim();
      final uri = Uri.tryParse(configured);
      if (uri == null || !GalleryHttp.isPublicUrl(configured)) {
        return _aitagDefaultAssetBase;
      }
      final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
      return uri
          .replace(path: normalizedPath, query: null, fragment: null)
          .toString();
    } catch (_) {
      return _aitagDefaultAssetBase;
    }
  }

  Future<dynamic> _aitagJson(
    String url, {
    Map<String, dynamic>? params,
    bool emptySearchOnNotFound = false,
  }) async {
    try {
      return await http.json(
        url,
        params: params,
        referer: 'https://aitag.win/',
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (emptySearchOnNotFound &&
          status == 404 &&
          _isEmptyAitagSearch404(error.response?.data)) {
        return const {
          'page': 1,
          'page_size': _aitagApiPageSize,
          'total': 0,
          'items': []
        };
      }
      final body = _text(error.response?.data).toLowerCase();
      if (status == 403 &&
          body.contains('cloudflare') &&
          RegExp(r'blocked|attention required|challenge').hasMatch(body)) {
        throw StateError('AI TAG 暂时拒绝了请求（403），可能触发了站点访问保护。');
      }
      if (status != null) throw StateError('AI TAG 请求失败（HTTP $status）。');
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw StateError('AI TAG 请求超时，请检查网络后重试。');
      }
      throw StateError('AI TAG 网络请求失败，请检查网络后重试。');
    } on FormatException {
      throw StateError('AI TAG 返回了无效的 JSON 数据。');
    }
  }

  bool _isEmptyAitagSearch404(Object? body) {
    dynamic decoded = body;
    if (body is String) {
      if (body.trim().isEmpty) return true;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        return false;
      }
    }
    if (decoded is! Map) return false;
    final map = _map(decoded);
    return map.isEmpty ||
        (map['items'] is List &&
            (map['items'] as List).isEmpty &&
            _integer(map['total']) == 0);
  }

  Future<OnlineGalleryPage> _searchArtistRanking(
    OnlineGalleryQuery query,
  ) async {
    final pageSize = _pageSize(query.pageSize, max: _maxBooruPageSize);
    final artistQuery = _safeArtistQuery(query.query);
    final order = switch (query.sort) {
      'score' => 'count',
      'name' => 'name',
      _ => throw FormatException('画师排行榜不支持排序方式：${query.sort}'),
    };
    final total = await _artistCount(artistQuery, order);
    if (total == 0) {
      return const OnlineGalleryPage(items: [], total: 0, hasMore: false);
    }
    final pageCount =
        (total / pageSize).ceil().clamp(1, _maxGalleryPage).toInt();
    final page =
        _page(query.page, max: _maxGalleryPage).clamp(1, pageCount).toInt();
    final offset = (page - 1) * pageSize;
    final apiPage = offset ~/ _artistTagPageSize + 1;
    final offsetInApiPage = offset % _artistTagPageSize;
    final first = await _fetchArtistPage(artistQuery, order, apiPage);
    var window = first;
    if (offsetInApiPage + pageSize > first.length &&
        apiPage < _artistTagMaxPage) {
      window = [
        ...first,
        ...await _fetchArtistPage(artistQuery, order, apiPage + 1)
      ];
    }
    final items = window
        .skip(offsetInApiPage)
        .take(pageSize)
        .map(_artistItem)
        .toList(growable: false);
    return OnlineGalleryPage(
      items: items,
      total: total,
      hasMore: offset + items.length < total,
    );
  }

  Future<int> _artistCount(String query, String order) async {
    final key = '$order:$query';
    final cached = _artistCounts[key];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < _artistCountCacheAge) {
      return cached.total;
    }
    var low = 1;
    var high = _artistTagMaxPage;
    var lastPage = 0;
    var lastItems = <Map<String, dynamic>>[];
    while (low <= high) {
      final page = (low + high) ~/ 2;
      final items = await _fetchArtistPage(query, order, page);
      if (items.isNotEmpty) {
        lastPage = page;
        lastItems = items;
        low = page + 1;
      } else {
        high = page - 1;
      }
    }
    if (lastPage > 0 && lastItems.length == _artistTagPageSize) {
      lastItems = await _fetchArtistPage(query, order, lastPage);
    }
    final total = lastPage == 0
        ? 0
        : (lastPage - 1) * _artistTagPageSize + lastItems.length;
    _artistCounts[key] = _CachedArtistCount(total, DateTime.now());
    return total;
  }

  Future<List<Map<String, dynamic>>> _fetchArtistPage(
    String query,
    String order,
    int page,
  ) async {
    final raw = await http.json(
      'https://danbooru.donmai.us/tags.json',
      params: {
        'limit': _artistTagPageSize,
        'page': page,
        'search[category]': 1,
        'search[order]': order,
        'search[is_deprecated]': 'no',
        if (query.isNotEmpty) 'search[name_matches]': '*$query*',
      },
      referer: 'https://danbooru.donmai.us/artists',
    );
    if (raw is! List) {
      throw const FormatException('Danbooru 返回了无效的画师标签列表。');
    }
    return raw
        .map(_map)
        .where((tag) => _integer(tag['id']) > 0)
        .where((tag) => _integer(tag['category']) == 1)
        .where((tag) => tag['is_deprecated'] != true)
        .where((tag) => _text(tag['name']).trim().isNotEmpty)
        .toList(growable: false);
  }

  OnlineGalleryItem _artistItem(Map<String, dynamic> tag) {
    final id = _positiveId(tag['id']);
    final name = _text(tag['name']).trim();
    final count = _integer(tag['post_count']);
    return OnlineGalleryItem(
      source: OnlineGallerySource.artistRanking,
      id: id,
      title: name,
      description: '$count 个投稿',
      sourceUrl:
          'https://danbooru.donmai.us/artists/${Uri.encodeComponent(id)}',
      rating: 'general',
      score: count,
      mediaCount: 0,
      collectionId: name,
      isCollection: true,
      metadata: {
        'artistId': _integer(tag['id']),
        'artist': name,
        'postCount': count,
        'category': 1,
        'isDeprecated': false,
      },
    );
  }

  Future<OnlineGalleryPage> _searchArtistPosts(
    OnlineGalleryQuery query,
  ) async {
    final artist = _safeArtistTag(query.collectionId ?? '');
    final sort = query.sort == 'score' ? 'score' : 'default';
    final postQuery = OnlineGalleryQuery(
      source: OnlineGallerySource.danbooru,
      query: ['artist:$artist', query.query.trim()]
          .where((part) => part.isNotEmpty)
          .join(' '),
      sort: sort,
      page: query.page,
      pageSize: query.pageSize,
      safeOnly: query.safeOnly,
    );
    return _searchDonmai(
      postQuery,
      itemSource: OnlineGallerySource.artistRanking,
      artistName: artist,
    );
  }

  String _safeArtistQuery(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return normalized.substring(0, normalized.length.clamp(0, 120).toInt());
  }

  String _safeArtistTag(String value) {
    final tag = value.trim();
    if (tag.isEmpty || !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(tag)) {
      throw const FormatException('画师标签无效，无法打开投稿列表。');
    }
    return tag;
  }

  Future<OnlineGalleryItem> _detailDonmai(OnlineGalleryItem item) async {
    final id = _numericId(item.id, 'Danbooru');
    final base = item.source == OnlineGallerySource.safebooru
        ? 'https://safebooru.donmai.us'
        : 'https://danbooru.donmai.us';
    final raw = await http.json(
      '$base/posts/$id.json',
      referer: '$base/',
    );
    if (raw is! Map) {
      throw const FormatException('Danbooru 返回了无效的帖子详情。');
    }
    return _donmaiItem(
      raw,
      item.source,
      metadata: item.source == OnlineGallerySource.artistRanking
          ? item.metadata
          : const {},
    );
  }

  Future<OnlineGalleryItem> _detailGelbooru(OnlineGalleryItem item) async {
    final id = _numericId(item.id, 'Gelbooru');
    final credentials = await _requireGelbooruCredentials();
    final raw = await http.json(
      'https://gelbooru.com/index.php',
      params: {
        'page': 'dapi',
        's': 'post',
        'q': 'index',
        'json': '1',
        'id': id,
        'api_key': credentials.apiKey,
        'user_id': credentials.userId,
      },
      referer: 'https://gelbooru.com/',
    );
    final posts = _gelbooruPosts(raw);
    if (posts.isEmpty) throw StateError('Gelbooru 没有找到这张图片。');
    return _gelbooruItem(posts.first);
  }

  Future<OnlineGalleryItem> _detailCivitai(
    OnlineGalleryItem item,
    bool safeOnly,
  ) async {
    final id = _positiveId(item.id);
    if (id.isEmpty) throw const FormatException('Civitai 图片编号无效。');
    final params = <String, dynamic>{
      'limit': 1,
      'type': 'image',
      'withMeta': 'true',
      'imageId': id,
      if (safeOnly) 'browsingLevel': '1',
    };
    final raw = await http.json(
      'https://civitai.com/api/v1/images',
      params: params,
      referer: 'https://civitai.com/',
    );
    final root = _map(raw);
    if (raw is! Map || root['items'] is! List) {
      throw const FormatException('Civitai 返回了无法识别的图片详情。');
    }
    final image = (root['items'] as List)
        .map(_map)
        .where((candidate) => _positiveId(candidate['id']) == id)
        .firstOrNull;
    if (image == null) throw StateError('Civitai 没有找到这张图片。');
    if (safeOnly && !_civitaiIsSafe(image)) {
      throw StateError('这张 Civitai 图片不符合安全筛选条件。');
    }
    final detailed = _civitaiItem(image);
    if (detailed == null) {
      throw const FormatException('Civitai 返回了无效的图片地址。');
    }
    return detailed;
  }

  Future<OnlineGalleryItem> _detailArtist(OnlineGalleryItem item) async {
    final id = _positiveId(item.metadata['artistId'] ?? item.id);
    if (id.isEmpty) throw const FormatException('Danbooru 画师编号无效。');
    final raw = await http.json(
      'https://danbooru.donmai.us/tags/$id.json',
      referer: 'https://danbooru.donmai.us/artists',
    );
    if (raw is! Map) {
      throw const FormatException('Danbooru 返回了无效的画师详情。');
    }
    final tag = _map(raw);
    if (_integer(tag['category']) != 1 || tag['is_deprecated'] == true) {
      throw StateError('Danbooru 画师标签已经失效。');
    }
    final name = _text(tag['name']).trim();
    final count = _integer(tag['post_count']);
    return item.copyWith(
      title: name.isEmpty ? item.title : name,
      description: '$count 个投稿',
      sourceUrl: 'https://danbooru.donmai.us/artists/$id',
      metadata: {
        ...item.metadata,
        'artistId': id,
        'artist': name,
        'postCount': count,
        'category': 1,
        'isDeprecated': false,
        'tag': tag,
      },
    );
  }

  String _buildBooruTags(OnlineGalleryQuery query) {
    final source = query.source;
    final validSorts = source.sorts;
    if (!validSorts.contains(query.sort)) {
      throw FormatException('${source.label} 不支持排序方式：${query.sort}');
    }
    if (query.timeRange != 'all' && !source.supportsTimeRange) {
      throw FormatException('${source.label} 不支持时间筛选。');
    }
    if (!const ['all', 'day', 'week', 'month', 'year']
        .contains(query.timeRange)) {
      throw FormatException('不支持的图库时间范围：${query.timeRange}');
    }
    final base = query.query.trim();
    var tags = base;
    if (query.sort != 'default') {
      tags = _removeBooruTerms(tags, const ['order', 'sort']);
    }
    if (query.timeRange != 'all') {
      tags = _removeBooruTerms(tags, const ['date', 'age']);
    }
    if (query.safeOnly) {
      tags = _removeBooruTerms(tags, const ['rating']);
      tags = _append(
          tags,
          source == OnlineGallerySource.gelbooru
              ? 'rating:general'
              : 'rating:g');
    }
    if (query.sort != 'default') {
      final term = switch ((source, query.sort)) {
        (OnlineGallerySource.danbooru, 'newest') ||
        (OnlineGallerySource.safebooru, 'newest') =>
          'order:id_desc',
        (OnlineGallerySource.danbooru, 'oldest') ||
        (OnlineGallerySource.safebooru, 'oldest') =>
          'order:id_asc',
        (OnlineGallerySource.danbooru, 'score') ||
        (OnlineGallerySource.safebooru, 'score') =>
          'order:score',
        (OnlineGallerySource.danbooru, 'favorites') ||
        (OnlineGallerySource.safebooru, 'favorites') =>
          'order:favcount',
        (OnlineGallerySource.danbooru, 'random') ||
        (OnlineGallerySource.safebooru, 'random') =>
          'order:random',
        (OnlineGallerySource.gelbooru, 'newest') => 'sort:id:desc',
        (OnlineGallerySource.gelbooru, 'oldest') => 'sort:id:asc',
        (OnlineGallerySource.gelbooru, 'score') => 'sort:score:desc',
        (OnlineGallerySource.gelbooru, 'random') => 'sort:random',
        _ => throw FormatException('${source.label} 不支持排序方式：${query.sort}'),
      };
      tags = _append(tags, term);
    }
    if (query.timeRange != 'all') {
      final days = switch (query.timeRange) {
        'day' => 1,
        'week' => 7,
        'month' => 30,
        'year' => 365,
        _ => throw FormatException('不支持的图库时间范围：${query.timeRange}'),
      };
      tags = _append(tags, 'age:<${days}d');
    }
    return tags;
  }

  String _removeBooruTerms(String query, List<String> names) {
    if (query.isEmpty) return query;
    final pattern = RegExp(
      '(^|\\s)-?(?:${names.join('|')}):[^\\s]+',
      caseSensitive: false,
    );
    return query
        .replaceAll(pattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _append(String query, String term) =>
      query.isEmpty ? term : '$query $term';

  int _page(int value, {int max = _maxGalleryPage}) =>
      value.clamp(1, max).toInt();

  int _pageSize(int value, {int max = _maxBooruPageSize}) =>
      value.clamp(1, max).toInt();

  int _booruPageSize(int value) => _pageSize(value, max: _maxBooruPageSize);

  String _numericId(String value, String source) {
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw FormatException('$source 图片编号无效。');
    }
    return value;
  }

  String _positiveId(Object? value) {
    if (value is int && value > 0) return value.toString();
    if (value is double &&
        value.isFinite &&
        value > 0 &&
        value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    if (value is String && RegExp(r'^[1-9]\d*$').hasMatch(value)) return value;
    return '';
  }

  int _integer(Object? value) {
    final parsed = value is num ? value : num.tryParse(_text(value));
    if (parsed == null || !parsed.isFinite) return 0;
    return parsed.toInt();
  }

  int? _nullableNonNegativeInt(Object? value) {
    final parsed = value is num ? value : num.tryParse(_text(value));
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed.toInt();
  }

  int? _nullablePositiveInt(Object? value) {
    final parsed = _nullableNonNegativeInt(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  int _firstCount(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map[key] != null) return _integer(map[key]);
    }
    return 0;
  }

  Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.fromEntries(value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value)))
      : <String, dynamic>{};

  Map<String, dynamic>? _mapOrNull(Object? value) =>
      value is Map ? _map(value) : null;

  List<Object?> _requireList(Object? value, String source) {
    if (value is! List) {
      throw FormatException('$source 返回了无效的 JSON 列表。');
    }
    return List<Object?>.from(value);
  }

  String _text(Object? value) => value == null ? '' : value.toString();

  List<String> _spaceTags(Object? value) {
    if (value is List) {
      return value
          .map(_text)
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    }
    return _text(value)
        .trim()
        .split(RegExp(r'\s+'))
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _aitagTagList(Object? value) {
    dynamic parsed = value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(value);
      } catch (_) {
        parsed = value;
      }
    }
    if (parsed is List) {
      return parsed
          .map(_text)
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    }
    if (parsed is String) {
      return parsed
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    }
    return const [];
  }

  dynamic _parseAitagJson(Object? value) {
    if (value is! String || value.trim().isEmpty) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  String _firstString(List<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value;
      if (value is Map || value is List) return jsonEncode(value);
    }
    return '';
  }

  String _stripHtml(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .trim();

  String _https(Object? value, [String? base]) {
    final raw = _text(value).trim();
    if (raw.isEmpty) return '';
    try {
      final uri = base == null ? Uri.parse(raw) : Uri.parse(base).resolve(raw);
      if (!GalleryHttp.isPublicUrl(uri.toString()) || uri.userInfo.isNotEmpty) {
        return '';
      }
      return uri.toString();
    } catch (_) {
      return '';
    }
  }

  OnlineGalleryMedia _makeMedia(
    String id,
    String preview,
    String display,
    String download,
    int width,
    int height,
  ) {
    final fallback = download.isNotEmpty
        ? download
        : display.isNotEmpty
            ? display
            : preview;
    final chosen = fallback.isNotEmpty ? fallback : preview;
    String? extension;
    final uri = Uri.tryParse(chosen);
    final match = uri == null
        ? null
        : RegExp(r'\.([a-z\d]+)$', caseSensitive: false).firstMatch(uri.path);
    if (match != null) extension = match.group(1)!.toLowerCase();
    return OnlineGalleryMedia(
      id: id,
      previewUrl: preview.isNotEmpty ? preview : fallback,
      displayUrl: display.isNotEmpty ? display : fallback,
      downloadUrl: fallback,
      width: width < 0 ? 0 : width,
      height: height < 0 ? 0 : height,
      extension: extension,
    );
  }
}

class _CachedArtistCount {
  final int total;
  final DateTime savedAt;
  const _CachedArtistCount(this.total, this.savedAt);
}

class _AitagSearchPage {
  final int total;
  final List<OnlineGalleryItem> items;
  const _AitagSearchPage({required this.total, required this.items});
}
