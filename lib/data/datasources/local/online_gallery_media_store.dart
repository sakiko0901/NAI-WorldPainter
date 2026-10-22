import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../domain/entities/online_gallery.dart';
import '../remote/gallery/gallery_http.dart';

class OnlineGalleryMediaStore {
  static const maxImageBytes = 40 * 1024 * 1024;
  static const maxCacheBytes = 160 * 1024 * 1024;
  final GalleryHttp http;
  final Future<Directory> Function() cacheDirectory, downloadDirectory;
  final Future<bool> Function(String) saveToAlbum;
  final Map<String, Future<String?>> _previews = {};
  final Map<String, Future<OnlineGalleryDownloadResult>> _downloads = {};
  final Map<String, Future<String>> _originals = {};
  final List<Completer<void>> _waiting = [];
  Future<void> _maintenance = Future<void>.value();
  Future<void>? _clearingCache;
  int _active = 0;

  OnlineGalleryMediaStore(
    this.http, {
    Future<Directory> Function()? cacheDirectory,
    Future<Directory> Function()? downloadDirectory,
    Future<bool> Function(String)? saveToAlbum,
  })  : cacheDirectory = cacheDirectory ??
            (() async => Directory(p.join(
                (await getTemporaryDirectory()).path, 'online_gallery_cache'))),
        downloadDirectory = downloadDirectory ??
            (() async => Directory(p.join(
                (await getApplicationDocumentsDirectory()).path,
                'online_gallery_downloads'))),
        saveToAlbum = saveToAlbum ?? _saveToAlbum;

  static Future<bool> _saveToAlbum(String path) async {
    final result = await ImageGallerySaverPlus.saveFile(path);
    return result is Map &&
        (result['isSuccess'] == true || result['success'] == true);
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  Future<T> _bounded<T>(Future<T> Function() run) async {
    if (_active >= 4) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await run();
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeAt(0).complete();
      }
    }
  }

  static String imageExtension(Uint8List bytes) {
    String extension;
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      extension = 'png';
    } else if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      extension = 'jpg';
    } else if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      extension = 'webp';
    } else if (bytes.length >= 6 &&
        ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'GIF') {
      extension = 'gif';
    } else {
      throw const FormatException('来源没有返回支持的图片');
    }
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > 16384 ||
        info.height > 16384 ||
        info.width * info.height > 64000000) {
      throw const FormatException('图片尺寸不受支持');
    }
    return extension;
  }

  Future<Uint8List> _fetch(String url, OnlineGallerySource source) async {
    if (!GalleryHttp.isPublicUrl(url)) throw ArgumentError('图片地址不受支持');
    final response = await http.get(url,
        referer: '${source.siteUrl}/', responseType: ResponseType.stream);
    final body = response.data as ResponseBody;
    final declared =
        int.tryParse(response.headers.value('content-length') ?? '');
    if (declared != null && declared > maxImageBytes) {
      await body.stream.listen(null).cancel();
      throw StateError('图片超过 40 MB，请在来源网站查看');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > maxImageBytes) {
        throw StateError('图片超过 40 MB，请在来源网站查看');
      }
      bytes.add(chunk);
    }
    final result = bytes.takeBytes();
    imageExtension(result);
    return result;
  }

  Future<String?> preview(
      OnlineGalleryItem item, OnlineGalleryMedia media) async {
    final clearing = _clearingCache;
    if (clearing != null) await clearing;
    final url =
        media.previewUrl.isNotEmpty ? media.previewUrl : media.displayUrl;
    if (!GalleryHttp.isPublicUrl(url)) return null;
    final key = '${item.source.id}:$url';
    final pending = _previews[key];
    if (pending != null) return pending;
    final operation = _bounded<String?>(() async {
      final directory = await cacheDirectory();
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, '${_hash(key)}.image'));
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
        return file.path;
      }
      final bytes = await _fetch(url, item.source);
      final temporary = File('${file.path}.part');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      await _maintainCache(() => _trimCache(directory, keep: file.path));
      return file.path;
    });
    _previews[key] = operation;
    try {
      return await operation;
    } finally {
      _previews.remove(key);
    }
  }

  Future<void> _maintainCache(Future<void> Function() operation) {
    final pending = _maintenance.then((_) => operation());
    _maintenance =
        pending.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return pending;
  }

  Future<void> _trimCache(Directory directory, {required String keep}) async {
    final entries = <({File file, FileStat stat})>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.image')) {
        final stat = await entity.stat();
        if (stat.type == FileSystemEntityType.file) {
          entries.add((file: entity, stat: stat));
        }
      }
    }
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.stat.size);
    entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final entry in entries) {
      if (total <= maxCacheBytes) break;
      if (entry.file.path != keep && await entry.file.exists()) {
        await entry.file.delete();
        total -= entry.stat.size;
      }
    }
  }

  Future<String> original(
      OnlineGalleryItem item, OnlineGalleryMedia media) async {
    final url =
        media.downloadUrl.isNotEmpty ? media.downloadUrl : media.displayUrl;
    if (!GalleryHttp.isPublicUrl(url)) throw ArgumentError('原图地址不受支持');
    final key = '${item.key}:$url';
    final pending = _originals[key];
    if (pending != null) return pending;
    final operation = _bounded(() async {
      final root = await downloadDirectory();
      final directory = Directory(
          p.join(root.path, item.source.id, _hash(item.key).substring(0, 16)));
      await directory.create(recursive: true);
      final stem = _hash(url);
      for (final extension in const ['png', 'jpg', 'webp', 'gif']) {
        final existing = File(p.join(directory.path, '$stem.$extension'));
        if (await existing.exists()) return existing.path;
      }
      final bytes = await _fetch(url, item.source);
      final extension = imageExtension(bytes);
      final file = File(p.join(directory.path, '$stem.$extension'));
      final part = File('${file.path}.part');
      try {
        await part.writeAsBytes(bytes, flush: true);
        if (!await file.exists()) await part.rename(file.path);
      } finally {
        if (await part.exists()) await part.delete();
      }
      return file.path;
    });
    _originals[key] = operation;
    try {
      return await operation;
    } finally {
      _originals.remove(key);
    }
  }

  Future<OnlineGalleryDownloadResult> download(
      OnlineGalleryItem item, List<OnlineGalleryMedia> images) async {
    if (images.isEmpty || images.length > 100) {
      throw ArgumentError('请选择 1–100 张图片');
    }
    final uniqueImages = <String, OnlineGalleryMedia>{
      for (final image in images)
        (image.downloadUrl.isNotEmpty ? image.downloadUrl : image.displayUrl):
            image,
    };
    final key = '${item.key}:${uniqueImages.keys.join('|')}';
    final pending = _downloads[key];
    if (pending != null) return pending;
    final operation = () async {
      final paths = <String>[];
      var failed = 0;
      for (final media in uniqueImages.values) {
        try {
          final path = await original(item, media);
          if (await saveToAlbum(path)) {
            paths.add(path);
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
      }
      return OnlineGalleryDownloadResult(
          saved: paths.length, failed: failed, paths: paths);
    }();
    _downloads[key] = operation;
    try {
      return await operation;
    } finally {
      _downloads.remove(key);
    }
  }

  Future<void> clearCache() async {
    final clearing = _clearingCache;
    if (clearing != null) return clearing;
    final operation = _clearCache();
    _clearingCache = operation;
    try {
      await operation;
    } finally {
      _clearingCache = null;
    }
  }

  Future<void> _clearCache() async {
    await Future.wait(_previews.values
        .map((future) =>
            future.then<void>((_) {}, onError: (Object _, StackTrace __) {}))
        .toList());
    await _maintainCache(() async {
      final directory = await cacheDirectory();
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File &&
            (entity.path.endsWith('.image') || entity.path.endsWith('.part'))) {
          await entity.delete();
        }
      }
    });
  }
}
