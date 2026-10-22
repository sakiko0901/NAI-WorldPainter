import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/online_gallery.dart';
import '../../domain/repositories/online_gallery_repository.dart';
import '../../domain/usecases/manage_style_presets.dart';
import '../datasources/local/online_gallery_local_store.dart';
import '../datasources/local/online_gallery_media_store.dart';
import '../datasources/remote/gallery/gallery_adapter.dart';
import '../datasources/remote/gallery/gallery_http.dart';

class OnlineGalleryRepositoryImpl implements OnlineGalleryRepository {
  final Map<OnlineGallerySource, GalleryAdapter> adapters;
  final OnlineGalleryLocalStore local;
  final OnlineGalleryCredentialStore credentials;
  final OnlineGalleryMediaStore media;
  final ManageStylePresetsUseCase styles;
  final Future<void> Function(String) _openUrl;
  final Map<String, Future<OnlineGalleryItem>> _pendingDetails = {};
  final Map<String, ({OnlineGalleryItem item, DateTime time})> _details = {};
  final List<Completer<void>> _detailWaiters = [];
  int _activeDetails = 0;
  int _detailEpoch = 0;

  OnlineGalleryRepositoryImpl({
    required this.adapters,
    required this.local,
    required this.credentials,
    required this.media,
    required this.styles,
    Future<void> Function(String)? openUrl,
  }) : _openUrl = openUrl ?? _openNativeUrl;

  static Future<void> _openNativeUrl(String url) async {
    final opened = await const MethodChannel('worldpainter/online_gallery')
        .invokeMethod<bool>('openUrl', {'url': url});
    if (opened != true) throw StateError('无法打开来源网站');
  }

  GalleryAdapter _adapter(OnlineGallerySource source) {
    final adapter = adapters[source];
    if (adapter == null) throw StateError('当前来源不可用');
    return adapter;
  }

  Future<T> _remote<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DioException catch (error) {
      // Request URLs can contain source-specific credentials. Never surface them.
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw StateError('来源拒绝访问，请检查图库凭据或稍后重试');
      }
      if (status == 429) throw StateError('来源请求过于频繁，请稍后重试');
      throw StateError('无法读取来源数据，请检查网络后重试');
    }
  }

  @override
  Future<OnlineGalleryPage> search(OnlineGalleryQuery query) async {
    final page = await _remote(() => _adapter(query.source).search(query));
    return OnlineGalleryPage(
      items: page.items
          .map((item) => item.copyWith(metadata: {
                ...item.metadata,
                'safeOnly': query.safeOnly,
              }))
          .toList(growable: false),
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
      total: page.total,
      title: page.title,
      collections: page.collections,
      categories: page.categories,
      warnings: page.warnings,
    );
  }

  @override
  Future<OnlineGalleryItem> detail(OnlineGalleryItem item,
      {bool safeOnly = true}) async {
    final epoch = _detailEpoch;
    final key = '${item.key}:$safeOnly:$epoch';
    final cached = _details[key];
    if (cached != null &&
        DateTime.now().difference(cached.time) < const Duration(minutes: 2)) {
      return cached.item;
    }
    final pending = _pendingDetails[key];
    if (pending != null) return pending;
    final operation = () async {
      if (_activeDetails >= 4) {
        final waiter = Completer<void>();
        _detailWaiters.add(waiter);
        await waiter.future;
      } else {
        _activeDetails++;
      }
      try {
        final fetched = await _remote(
            () => _adapter(item.source).detail(item, safeOnly: safeOnly));
        final result = fetched.copyWith(metadata: {
          ...fetched.metadata,
          'safeOnly': safeOnly,
        });
        if (epoch == _detailEpoch) {
          _details[key] = (item: result, time: DateTime.now());
          if (_details.length > 80) _details.remove(_details.keys.first);
        }
        return result;
      } finally {
        if (_detailWaiters.isEmpty) {
          _activeDetails--;
        } else {
          _detailWaiters.removeAt(0).complete();
        }
      }
    }();
    _pendingDetails[key] = operation;
    try {
      return await operation;
    } finally {
      _pendingDetails.remove(key);
    }
  }

  @override
  Future<List<OnlineGalleryItem>> favorites() => local.favorites();
  @override
  Future<void> setFavorite(OnlineGalleryItem item, bool value) async {
    final saved = value && !item.isCollection
        ? await detail(item, safeOnly: item.metadata['safeOnly'] != false)
        : item;
    await local.setFavorite(saved, value);
  }

  @override
  Future<OnlineGalleryQuery?> loadLastQuery() async => local.loadQuery();
  @override
  Future<void> saveQuery(OnlineGalleryQuery query) => local.saveQuery(query);
  @override
  Future<String?> previewPath(
      OnlineGalleryItem item, OnlineGalleryMedia image) async {
    if (item.source == OnlineGallerySource.aitag &&
        !item.isCollection &&
        image.previewUrl.isEmpty &&
        image.displayUrl.isEmpty) {
      final hydrated =
          await detail(item, safeOnly: item.metadata['safeOnly'] != false);
      return media.preview(hydrated, hydrated.cover);
    }
    return media.preview(item, image);
  }

  @override
  Future<OnlineGalleryDownloadResult> download(
          OnlineGalleryItem item, List<OnlineGalleryMedia> images) =>
      media.download(item, images);
  @override
  Future<void> saveStyle(OnlineGalleryItem item) async {
    if (item.prompt.trim().isEmpty || item.media.isEmpty) {
      throw StateError('此条目没有可保存的提示词或预览图');
    }
    final title = '${item.title} · ${item.source.label}';
    final presets = await styles.getAll();
    if (presets.any((preset) =>
        preset.title == title && preset.prompt == item.prompt.trim())) {
      return;
    }
    final path = await media.original(item, item.cover);
    await styles.createFromImage(
        title: title, prompt: item.prompt, sourceImagePath: path);
  }

  @override
  Future<void> openSource(OnlineGalleryItem item) async {
    final url = item.sourceUrl.isEmpty ? item.source.siteUrl : item.sourceUrl;
    if (!GalleryHttp.isPublicUrl(url)) throw ArgumentError('来源网址不受支持');
    await _openUrl(url);
  }

  @override
  Future<void> clearCache() async {
    _detailEpoch++;
    _details.clear();
    await media.clearCache();
  }

  @override
  Future<bool> hasGelbooruCredentials() async =>
      await credentials.read() != null;
  @override
  Future<void> setGelbooruCredentials(OnlineGalleryCredentials value) =>
      credentials.write(value);
}
