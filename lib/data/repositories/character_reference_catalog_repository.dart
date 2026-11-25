import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/character_reference_asset.dart';

const _storageName = 'character_reference_catalog';
const _snapshotSchema = 'worldpainter-character-references/v1';
const _catalogSchema = 'langbai-reference-catalog/v1';
const _federatedSchema = 'langbai-reference-catalog/federated-v1';
const _catalogLimit = 24 * 1024 * 1024;
const _imageLimit = 40 * 1024 * 1024;
const _previewLimit = 1024 * 1024;
const _metadataLimit = 24 * 1024;
const _maxEntries = 15000;
const _localPrefix = 'local:';
const _imageNames = {'image.png', 'image.jpg', 'image.webp'};
final _hexDigest = RegExp(r'^[0-9a-f]{64}$');
final _unsafeUriPath = RegExp(r'[/\\\x00]');

class CharacterReferenceCatalogRepository {
  /// Online catalog compiled by Langbai NovelAI Studio. The resource project
  /// provides the same catalog and the downloadable images.
  static const sourceName = 'Langbai NovelAI Studio';
  static const sourceProject =
      'https://github.com/2786886095/novelai-image-desktop';
  static const sourceResources =
      'https://github.com/2786886095/novelai-reference-assets';

  // Index endpoints documented by the upstream Android reference_catalog.dart.
  static const catalogSources = [
    'https://2786886095.github.io/novelai-image-desktop/reference-catalog/index.json',
    'https://raw.githubusercontent.com/2786886095/novelai-reference-assets/main/catalog/index.json',
  ];

  final Dio _dio;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _cacheDirectory;
  List<CharacterReferenceAsset>? _catalog;
  Future<List<CharacterReferenceAsset>>? _loading;
  final Map<String, Future<String?>> _previews = {};
  final List<Completer<void>> _previewQueue = [];
  int _runningPreviews = 0;
  int _previewsSinceTrim = 16;

  // The picker and the library can use separate repository instances.
  static final _saves = <String, Future<SavedCharacterReference>>{};
  static final _removals = <String, Future<void>>{};

  CharacterReferenceCatalogRepository({
    Dio? dio,
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? cacheDirectory,
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 18),
            )),
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;

  Future<List<CharacterReferenceAsset>> load({bool refresh = false}) async {
    if (!refresh) {
      final cached = _catalog ?? await _readCatalogCache();
      if (cached != null) return _catalog ??= cached;
    }
    final pending = _loading;
    if (pending != null) return pending;
    final operation = _loadOnline();
    _loading = operation;
    try {
      return await operation;
    } finally {
      _loading = null;
    }
  }

  Future<List<CharacterReferenceAsset>> _loadOnline() async {
    for (final source in catalogSources) {
      try {
        final catalog = await _readCatalog(Uri.parse(source));
        _catalog = catalog;
        await _writeCatalogCache(catalog);
        return catalog;
      } on Exception {
        // Try the secondary source if HTTP, parsing or a catalog chunk failed.
      }
    }
    final cached = _catalog ?? await _readCatalogCache();
    if (cached != null) return _catalog ??= cached;
    throw StateError('暂时无法加载参考预设在线目录，请检查网络后重试');
  }

  Future<List<CharacterReferenceAsset>> _readCatalog(Uri source) async {
    final root = await _readCatalogPart(source);
    final assets = <String, CharacterReferenceAsset>{
      for (final asset in root.assets) asset.id: asset,
    };
    // Fetch a few game chunks at once. A failed chunk must not replace a
    // complete cached catalog with a partial one.
    for (var i = 0; i < root.chunks.length; i += 3) {
      final parts = await Future.wait(root.chunks.skip(i).take(3).map(
            (chunk) => _readCatalogPart(source.resolve(chunk)),
          ));
      for (final part in parts) {
        if (part.chunks.isNotEmpty) throw const FormatException('图录分片格式错误');
        for (final asset in part.assets) {
          assets.putIfAbsent(asset.id, () => asset);
        }
      }
      if (assets.length > _maxEntries) throw const FormatException('图录条目过多');
    }
    return List.unmodifiable(assets.values);
  }

  Future<_CatalogPart> _readCatalogPart(Uri uri) async {
    final bytes = await _getBytes(uri, limit: _catalogLimit, catalog: true);
    return compute(_parseCatalogPart, bytes);
  }

  Future<List<CharacterReferenceAsset>?> _readCatalogCache() async {
    try {
      final root = await _managedDirectory(_supportDirectory);
      final file = File(p.join(root.path, 'index.json'));
      if (!await _isFile(file)) return null;
      final bytes = await _readFile(file, _catalogLimit);
      return await compute(_parseSnapshot, bytes);
    } on Exception {
      return null;
    }
  }

  Future<void> _writeCatalogCache(List<CharacterReferenceAsset> catalog) async {
    try {
      final root = await _managedDirectory(_supportDirectory);
      final encoded = await compute(_encodeSnapshot, catalog);
      if (encoded.length > _catalogLimit) return;
      final staging = await root.createTemp('.catalog-');
      final file = File(p.join(staging.path, 'index.json'));
      try {
        await file.writeAsBytes(encoded, flush: true);
        await file.rename(p.join(root.path, 'index.json'));
      } finally {
        if (await file.exists()) await file.delete();
        await staging.delete();
      }
    } on Exception {
      // Keep the live catalog usable even if this device cannot store the cache.
    }
  }

  Future<String?> previewPath(CharacterReferenceAsset asset) async {
    final urls = _trustedUrls(asset.thumbnailUrls);
    if (urls.isEmpty) return null;
    final key = _hashText(urls.join('\n'));
    final pending = _previews[key];
    if (pending != null) return pending;
    final operation = _preview(key, urls);
    _previews[key] = operation;
    try {
      return await operation;
    } finally {
      _previews.remove(key);
    }
  }

  Future<String?> _preview(String key, List<String> urls) async {
    if (_runningPreviews >= 3) {
      final ready = Completer<void>();
      _previewQueue.add(ready);
      await ready.future;
    } else {
      _runningPreviews++;
    }
    try {
      final root = await _managedDirectory(_cacheDirectory, 'previews');
      final file = File(p.join(root.path, '$key.preview'));
      if (await _isFile(file)) {
        final length = await file.length();
        if (length > 0 && length <= _previewLimit) return file.path;
      }
      final image = await _fetchImage(urls, limit: _previewLimit);
      final staging = await root.createTemp('.preview-');
      final temporary = File(p.join(staging.path, 'preview'));
      try {
        await temporary.writeAsBytes(image.bytes);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
        await staging.delete();
      }
      if (++_previewsSinceTrim >= 16) {
        _previewsSinceTrim = 0;
        await _trimPreviews(root, keep: file.path);
      }
      return file.path;
    } on Exception {
      return null;
    } finally {
      if (_previewQueue.isEmpty) {
        _runningPreviews--;
      } else {
        _previewQueue.removeAt(0).complete();
      }
    }
  }

  Future<void> _trimPreviews(Directory root, {required String keep}) async {
    final entries = <(File, FileStat)>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File &&
          p.extension(entity.path) == '.preview' &&
          _hexDigest.hasMatch(p.basenameWithoutExtension(entity.path))) {
        entries.add((entity, await entity.stat()));
      }
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var total = entries.fold(0, (sum, entry) => sum + entry.$2.size);
    for (final (file, stat) in entries) {
      if (total <= 48 * 1024 * 1024) break;
      if (file.path == keep) continue;
      await file.delete();
      total -= stat.size;
    }
  }

  Future<SavedCharacterReference> download(
    CharacterReferenceAsset asset, {
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    _checkCanceled(cancelToken);
    if (asset.id.trim().isEmpty || asset.id.startsWith(_localPrefix)) {
      throw ArgumentError('该角色参考图没有可下载的在线条目');
    }
    final entry = await _savedEntry(asset.id);
    return _saveOnce(entry, () async {
      final image = await _fetchImage(
        _trustedUrls(asset.downloadUrls),
        limit: _imageLimit,
        asset: asset,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      return _storeSaved(entry, asset, image, cancelToken: cancelToken);
    }, cancelToken: cancelToken);
  }

  Future<SavedCharacterReference> importLocal({
    required String path,
    required String name,
    String game = '其他',
    String category = '本地导入',
    String variant = '',
  }) async {
    final normalizedName = name.trim();
    final normalizedGame = game.trim().isEmpty ? '其他' : game.trim();
    final normalizedCategory =
        category.trim().isEmpty ? '本地导入' : category.trim();
    final normalizedVariant = variant.trim();
    if (normalizedName.isEmpty) throw ArgumentError('请输入角色名称');
    final bytes = await _readFile(File(path), _imageLimit);
    final image = await _inspectImage(bytes);
    final checksum = await compute(_hashBytes, bytes);
    final id = _localPrefix +
        _hashText(jsonEncode([
          checksum,
          normalizedName,
          normalizedGame,
          normalizedCategory,
          normalizedVariant,
        ]));
    final asset = CharacterReferenceAsset(
      id: id,
      game: normalizedGame,
      category: normalizedCategory,
      name: normalizedName,
      variant: normalizedVariant,
      width: image.width,
      height: image.height,
      bytes: bytes.length,
      thumbnailUrls: const [],
      downloadUrls: const [],
      checksum: checksum,
    );
    final entry = await _savedEntry(asset.id);
    return _saveOnce(entry, () => _storeSaved(entry, asset, image));
  }

  Future<Directory> _savedEntry(String id) async {
    final root = await _managedDirectory(_supportDirectory, 'saved');
    return Directory(p.join(root.path, _hashText(id)));
  }

  Future<SavedCharacterReference> _saveOnce(
    Directory entry,
    Future<SavedCharacterReference> Function() save, {
    CancelToken? cancelToken,
  }) async {
    final deleting = _removals[entry.path];
    if (deleting != null) await deleting;
    _checkCanceled(cancelToken);
    final pending = _saves[entry.path];
    if (pending != null) {
      if (cancelToken == null) return pending;
      return Future.any([
        pending,
        cancelToken.whenCancel
            .then<SavedCharacterReference>((error) => throw error),
      ]);
    }
    final operation = () async {
      final existing = await _readSaved(entry);
      _checkCanceled(cancelToken);
      return existing ?? await save();
    }();
    _saves[entry.path] = operation;
    try {
      return await operation;
    } finally {
      _saves.remove(entry.path);
    }
  }

  Future<SavedCharacterReference> _storeSaved(
    Directory entry,
    CharacterReferenceAsset asset,
    _ImageFile image, {
    CancelToken? cancelToken,
  }) async {
    final filename = 'image.${image.extension}';
    final metadata = _encodeAsset(asset)
      ..['width'] = image.width
      ..['height'] = image.height
      ..['bytes'] = image.bytes.length
      ..['file'] = filename;
    final encoded = utf8.encode(jsonEncode(metadata));
    if (encoded.length > _metadataLimit) {
      throw const FormatException('角色参考图资料过长');
    }
    final storedAsset = _storedAsset(metadata);
    if (storedAsset == null) throw const FormatException('角色参考图资料不完整');
    final staging = await entry.parent.createTemp('.save-');
    try {
      await File(p.join(staging.path, filename))
          .writeAsBytes(image.bytes, flush: true);
      await File(p.join(staging.path, 'asset.json'))
          .writeAsBytes(encoded, flush: true);
      _checkCanceled(cancelToken);
      final existing = await _readSaved(entry);
      if (existing != null) return existing;
      await _deleteKnownFiles(entry);
      _checkCanceled(cancelToken);
      await staging.rename(entry.path);
      return SavedCharacterReference(
        asset: storedAsset,
        path: p.join(entry.path, filename),
      );
    } finally {
      await _deleteKnownFiles(staging);
    }
  }

  Future<List<SavedCharacterReference>> listSaved() async {
    final root = await _managedDirectory(_supportDirectory, 'saved');
    final saved = <SavedCharacterReference>[];
    final batch = <Future<SavedCharacterReference?>>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory && _hexDigest.hasMatch(p.basename(entity.path))) {
        batch.add(_readSaved(entity));
        if (batch.length == 16) {
          saved.addAll((await Future.wait(batch)).whereType());
          batch.clear();
        }
      }
    }
    saved.addAll((await Future.wait(batch)).whereType());
    saved.sort((a, b) => a.asset.name.compareTo(b.asset.name));
    return saved;
  }

  Future<SavedCharacterReference?> _readSaved(Directory entry) async {
    try {
      if (!await _isDirectory(entry)) return null;
      final metadataFile = File(p.join(entry.path, 'asset.json'));
      if (!await _isFile(metadataFile)) return null;
      final metadata =
          _decodeObject(await _readFile(metadataFile, _metadataLimit));
      final asset = _storedAsset(metadata);
      final filename = _string(metadata['file']);
      if (asset == null ||
          !_imageNames.contains(filename) ||
          p.basename(entry.path) != _hashText(asset.id)) {
        return null;
      }
      final file = File(p.join(entry.path, filename));
      if (!await _isFile(file) || await file.length() != asset.bytes) {
        return null;
      }
      return SavedCharacterReference(asset: asset, path: file.path);
    } on Exception {
      return null;
    }
  }

  Future<void> remove(SavedCharacterReference saved) async {
    final entry = await _savedEntry(saved.asset.id);
    final filename = p.basename(saved.path);
    if (!_imageNames.contains(filename) ||
        !p.equals(p.absolute(saved.path), p.join(entry.path, filename))) {
      throw ArgumentError('该文件不在参考预设中');
    }
    final pending = _removals[entry.path];
    if (pending != null) return pending;
    final operation = () async {
      await _saves[entry.path]?.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      final stored = await _readSaved(entry);
      if (stored == null) return;
      if (!p.equals(stored.path, saved.path)) {
        throw ArgumentError('该文件不在参考预设中');
      }
      await _deleteKnownFiles(entry);
    }();
    _removals[entry.path] = operation;
    try {
      await operation;
    } finally {
      _removals.remove(entry.path);
    }
  }

  Future<_ImageFile> _fetchImage(
    List<String> urls, {
    required int limit,
    CharacterReferenceAsset? asset,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    FormatException? invalidImage;
    for (final url in urls) {
      _checkCanceled(cancelToken);
      try {
        final bytes = await _getBytes(
          Uri.parse(url),
          limit: limit,
          expectedBytes: asset?.bytes ?? 0,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
        final checksum = asset?.checksum;
        if (checksum != null && await compute(_hashBytes, bytes) != checksum) {
          throw const FormatException('图片内容与图录记录不一致');
        }
        final image =
            await _inspectImage(bytes, preview: limit == _previewLimit);
        if (asset != null &&
            ((asset.width > 0 && image.width != asset.width) ||
                (asset.height > 0 && image.height != asset.height))) {
          throw const FormatException('图片尺寸与图录记录不一致');
        }
        _checkCanceled(cancelToken);
        return image;
      } on FormatException catch (error) {
        invalidImage = error;
      } on Exception {
        _checkCanceled(cancelToken);
      }
    }
    _checkCanceled(cancelToken);
    if (invalidImage != null) throw invalidImage;
    throw const HttpException('参考图下载失败，请检查网络后重试');
  }

  Future<Uint8List> _getBytes(
    Uri uri, {
    required int limit,
    bool catalog = false,
    int expectedBytes = 0,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final deadline = Stopwatch()..start();
    for (var hop = 0; hop <= 3; hop++) {
      _checkCanceled(cancelToken);
      if (!_isTrusted(uri)) throw const FormatException('图录来源地址不受支持');
      final requestCancel = CancelToken();
      var finished = false;
      var consumed = false;
      if (cancelToken != null) {
        unawaited(cancelToken.whenCancel.then((error) {
          if (!finished) requestCancel.cancel(error.error);
        }));
      }
      try {
        final response = await _dio.getUri<ResponseBody>(
          uri,
          cancelToken: requestCancel,
          options: Options(
            followRedirects: false,
            responseType: ResponseType.stream,
            validateStatus: (_) => true,
            headers: {
              'Accept': catalog ? 'application/json, text/plain' : 'image/*',
              'User-Agent': 'WorldPainter/1.2 (Android; CharacterReference)',
            },
          ),
        );
        final body = response.data;
        if (body == null) throw const FormatException('图录来源返回空响应');
        final status = response.statusCode;
        if (const {301, 302, 303, 307, 308}.contains(status)) {
          final location = response.headers.value('location');
          if (location == null) throw const FormatException('图录来源跳转地址缺失');
          uri = uri.resolve(location);
          continue;
        }
        if (status != 200) throw const HttpException('图录来源暂时不可用');
        final contentType = response.headers
            .value(Headers.contentTypeHeader)
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        final declaredLength = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        );
        final isEncoded = response.headers.value('content-encoding') != null;
        final total = isEncoded ? null : declaredLength;
        if (!_validType(contentType, catalog) ||
            (total != null && (total <= 0 || total > limit))) {
          throw const FormatException('来源返回的文件格式或大小不受支持');
        }
        final buffer = _BoundedBytes(limit);
        await for (final chunk
            in body.stream.timeout(const Duration(seconds: 18))) {
          _checkCanceled(cancelToken);
          if (deadline.elapsed > const Duration(minutes: 1)) {
            throw TimeoutException('图录来源读取超时');
          }
          buffer.add(chunk);
          final received = buffer.length;
          onProgress?.call(received,
              total ?? (expectedBytes > 0 ? expectedBytes : received));
        }
        consumed = true;
        final bytes = buffer.takeBytes();
        if (bytes.isEmpty ||
            (total != null && bytes.length != total) ||
            (expectedBytes > 0 && bytes.length != expectedBytes)) {
          throw const FormatException('来源返回的文件不完整');
        }
        return bytes;
      } finally {
        finished = true;
        if (!consumed) requestCancel.cancel('结束当前来源的响应读取');
      }
    }
    throw const FormatException('图录来源跳转次数过多');
  }
}

bool _isTrusted(Uri uri) {
  if (uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.authority.contains('@') ||
      uri.port != 443 ||
      uri.hasFragment ||
      uri.pathSegments
          .any((part) => part == '..' || part.contains(_unsafeUriPath))) {
    return false;
  }
  final path = uri.path;
  return switch (uri.host) {
    '2786886095.github.io' =>
      path.startsWith('/novelai-image-desktop/reference-catalog/'),
    'raw.githubusercontent.com' =>
      path.startsWith('/2786886095/novelai-reference-assets/') ||
          path.startsWith('/2786886095/novelai-image-desktop/'),
    'media.githubusercontent.com' =>
      path.startsWith('/media/2786886095/novelai-reference-assets/'),
    _ => false,
  };
}

List<String> _trustedUrls(Iterable<String> candidates) => List.unmodifiable({
      for (final candidate in candidates)
        if (Uri.tryParse(candidate) case final Uri uri)
          if (_isTrusted(uri)) uri.toString(),
    });

bool _validType(String? type, bool catalog) =>
    type == null ||
    type == 'application/octet-stream' ||
    (catalog
        ? type == 'text/plain' ||
            type == 'application/json' ||
            type.endsWith('+json')
        : type.startsWith('image/'));

void _checkCanceled(CancelToken? token) {
  final error = token?.cancelError;
  if (error != null) throw error;
}

class _BoundedBytes implements Sink<List<int>> {
  final int limit;
  final _buffer = BytesBuilder(copy: false);

  _BoundedBytes(this.limit);

  int get length => _buffer.length;

  @override
  void add(List<int> data) {
    if (length + data.length > limit) throw const FormatException('文件超过大小上限');
    _buffer.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _buffer.takeBytes();
}

class _CatalogPart {
  final List<CharacterReferenceAsset> assets;
  final List<String> chunks;

  const _CatalogPart({this.assets = const [], this.chunks = const []});
}

_CatalogPart _parseCatalogPart(Uint8List bytes) {
  var payload = _decodeObject(bytes);
  if (payload['encoding'] == 'gzip-base64' && payload['payload'] is String) {
    final sink = _BoundedBytes(_catalogLimit);
    final decoder = gzip.decoder.startChunkedConversion(sink);
    decoder.add(base64.decode(payload['payload'] as String));
    decoder.close();
    payload = _decodeObject(sink.takeBytes());
  }
  if (payload['schema'] == _federatedSchema) {
    final chunks =
        _rows(payload['chunks']).map((row) => _string(row['url'])).toList();
    if (chunks.isEmpty ||
        chunks.length > 32 ||
        chunks.any((url) => url.isEmpty)) {
      throw const FormatException('图录分片列表格式错误');
    }
    return _CatalogPart(chunks: chunks);
  }
  if (payload['schema'] != _catalogSchema) {
    throw const FormatException('图录格式不受支持');
  }
  final rows = _rows(payload['assets']);
  if (rows.length > _maxEntries) throw const FormatException('图录条目过多');
  final games = {
    for (final row in _rows(payload['games']))
      _string(row['id']): _object(row['names']),
  };
  final assets = rows
      .map((row) => _onlineAsset(row, games))
      .whereType<CharacterReferenceAsset>()
      .toList();
  if (assets.isEmpty) throw const FormatException('图录没有可用的角色参考图');
  return _CatalogPart(assets: assets);
}

CharacterReferenceAsset? _onlineAsset(
  Map<String, dynamic> row,
  Map<String, Map<String, dynamic>> gameNames,
) {
  final id = _string(row['id']);
  final rawGame = _string(row['game']);
  final category = _string(row['category']);
  final precise = _object(_object(row['files'])['precise']);
  final mirrors = _object(row['downloadMirrors']);
  final preciseMirrors = _object(precise['mirrors']);
  final downloadUrls = _trustedUrls([
    _string(mirrors['github']),
    _string(preciseMirrors['github']),
    _string(row['downloadUrl']),
    _string(precise['url']),
    ..._strings(mirrors.values),
    ..._strings(preciseMirrors.values),
  ]);
  if (id.isEmpty ||
      id.startsWith(_localPrefix) ||
      rawGame.isEmpty ||
      category.isEmpty ||
      downloadUrls.isEmpty) {
    return null;
  }
  final thumbnailMirrors = _object(row['thumbnailMirrors']);
  final names = _object(row['names']);
  final localizedGames = {
    ...?gameNames[rawGame],
    ..._object(row['gameNames']),
  };
  final variant = _string(row['variant']);
  final role = _string(row['roleId']);
  final width = _integer(row['width'] ?? precise['width']);
  final height = _integer(row['height'] ?? precise['height']);
  final bytes = _integer(row['bytes'] ?? precise['bytes']);
  if (!_validDimensions(width, height) || bytes <= 0 || bytes > _imageLimit) {
    return null;
  }
  return CharacterReferenceAsset(
    id: id,
    game: _firstText([localizedGames['zh-CN'], rawGame]),
    category: category,
    name: _firstText([names['zh-CN'], names['en-US'], role, variant, id]),
    variant: variant,
    width: width,
    height: height,
    bytes: bytes,
    downloadUrls: downloadUrls,
    thumbnailUrls: _trustedUrls([
      _string(thumbnailMirrors['github']),
      _string(row['thumbnailUrl']),
      ..._strings(thumbnailMirrors.values),
    ]),
    aliases: List.unmodifiable({
      ..._strings([rawGame, role]),
      ..._strings(names.values),
      ..._strings(localizedGames.values),
      ..._strings(_list(row['searchAliases'])),
    }),
    checksum: _checksum(precise['sha256'] ?? row['sha256']),
  );
}

Map<String, dynamic> _encodeAsset(CharacterReferenceAsset asset) => {
      'id': asset.id,
      'name': asset.name,
      'game': asset.game,
      'category': asset.category,
      'variant': asset.variant,
      'width': asset.width,
      'height': asset.height,
      'bytes': asset.bytes,
      'thumbnails': asset.thumbnailUrls,
      'downloads': asset.downloadUrls,
      'aliases': asset.aliases,
      if (asset.checksum != null) 'checksum': asset.checksum,
    };

CharacterReferenceAsset? _storedAsset(Map<String, dynamic> row) {
  final id = _string(row['id']);
  final name = _string(row['name']);
  final game = _string(row['game']);
  final category = _string(row['category']);
  final width = _integer(row['width']);
  final height = _integer(row['height']);
  final bytes = _integer(row['bytes']);
  if (id.isEmpty ||
      name.isEmpty ||
      game.isEmpty ||
      category.isEmpty ||
      !_validDimensions(width, height) ||
      bytes <= 0 ||
      bytes > _imageLimit) {
    return null;
  }
  return CharacterReferenceAsset(
    id: id,
    name: name,
    game: game,
    category: category,
    variant: _string(row['variant']),
    width: width,
    height: height,
    bytes: bytes,
    thumbnailUrls: _trustedUrls(_strings(_list(row['thumbnails']))),
    downloadUrls: _trustedUrls(_strings(_list(row['downloads']))),
    aliases: List.unmodifiable(_strings(_list(row['aliases']))),
    checksum: _checksum(row['checksum']),
  );
}

Uint8List _encodeSnapshot(List<CharacterReferenceAsset> catalog) =>
    utf8.encode(jsonEncode({
      'schema': _snapshotSchema,
      'assets': catalog.map(_encodeAsset).toList(),
    }));

List<CharacterReferenceAsset>? _parseSnapshot(Uint8List bytes) {
  final json = _decodeObject(bytes);
  if (json['schema'] != _snapshotSchema) return null;
  final rows = _rows(json['assets']);
  if (rows.isEmpty || rows.length > _maxEntries) return null;
  final assets =
      rows.map(_storedAsset).whereType<CharacterReferenceAsset>().toList();
  if (assets.length != rows.length ||
      assets.any((asset) => asset.downloadUrls.isEmpty)) {
    return null;
  }
  return List.unmodifiable(assets);
}

Map<String, dynamic> _decodeObject(Uint8List bytes) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) throw const FormatException('图录格式错误');
  return value;
}

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : const {};
List<dynamic> _list(Object? value) => value is List ? value : const [];
Iterable<Map<String, dynamic>> _rows(Object? value) =>
    _list(value).whereType<Map<String, dynamic>>();
String _string(Object? value) => value is String ? value.trim() : '';
int _integer(Object? value) => value is int ? value : 0;
Iterable<String> _strings(Iterable<dynamic> values) =>
    values.map(_string).where((value) => value.isNotEmpty);
String _firstText(Iterable<dynamic> values) =>
    _strings(values).firstOrNull ?? '';
String _hashBytes(Uint8List value) => sha256.convert(value).toString();
String _hashText(String value) => _hashBytes(utf8.encode(value));

String? _checksum(Object? value) {
  final digest = _string(value).toLowerCase();
  return _hexDigest.hasMatch(digest) ? digest : null;
}

typedef _ImageFile = ({
  Uint8List bytes,
  int width,
  int height,
  String extension
});

bool _validDimensions(int width, int height, {bool preview = false}) =>
    width > 0 &&
    height > 0 &&
    width <= (preview ? 1024 : 8192) &&
    height <= (preview ? 1024 : 8192) &&
    width * height <= (preview ? 1024 * 1024 : 32000000);

Future<_ImageFile> _inspectImage(Uint8List bytes,
    {bool preview = false}) async {
  final extension = _imageExtension(bytes);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (!_validDimensions(width, height, preview: preview)) {
      throw const FormatException('图片尺寸超出支持范围');
    }
    codec =
        await descriptor.instantiateCodec(targetWidth: width > 64 ? 64 : width);
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    return (bytes: bytes, width: width, height: height, extension: extension);
  } on FormatException {
    rethrow;
  } on Exception {
    throw const FormatException('无法读取图片，请选择有效的 PNG、JPEG 或 WebP');
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

String _imageExtension(Uint8List bytes) {
  bool startsWith(List<int> magic, [int offset = 0]) {
    if (bytes.length < magic.length + offset) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [137, 80, 78, 71, 13, 10, 26, 10])) return 'png';
  if (startsWith(const [255, 216, 255])) return 'jpg';
  if (startsWith(const [82, 73, 70, 70]) &&
      startsWith(const [87, 69, 66, 80], 8)) {
    return 'webp';
  }
  throw const FormatException('无法读取图片，请选择有效的 PNG、JPEG 或 WebP');
}

Future<Directory> _managedDirectory(Future<Directory> Function() base,
    [String? subdirectory]) async {
  final parent = await base();
  final root = Directory(p.absolute(parent.path, _storageName));
  await _ensureDirectory(root);
  if (subdirectory == null) return root;
  final directory = Directory(p.join(root.path, subdirectory));
  await _ensureDirectory(directory);
  return directory;
}

Future<void> _ensureDirectory(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.directory) return;
  if (type != FileSystemEntityType.notFound) {
    throw const FileSystemException('参考预设存储目录不可用');
  }
  await directory.create(recursive: true);
}

Future<bool> _isDirectory(Directory directory) async =>
    await FileSystemEntity.type(directory.path, followLinks: false) ==
    FileSystemEntityType.directory;

Future<bool> _isFile(File file) async =>
    await FileSystemEntity.type(file.path, followLinks: false) ==
    FileSystemEntityType.file;

Future<Uint8List> _readFile(File file, int limit) async {
  final length = await file.length();
  if (length <= 0 || length > limit) throw const FormatException('文件为空或超过大小上限');
  final bounded = _BoundedBytes(limit);
  await for (final bytes in file.openRead(0, length)) {
    bounded.add(bytes);
  }
  if (bounded.length != length) throw const FormatException('文件读取不完整');
  return bounded.takeBytes();
}

Future<void> _deleteKnownFiles(Directory entry) async {
  if (!await _isDirectory(entry)) return;
  for (final name in {'asset.json', ..._imageNames}) {
    final file = File(p.join(entry.path, name));
    if (await _isFile(file)) await file.delete();
  }
  if (await entry.list(followLinks: false).isEmpty) await entry.delete();
}
