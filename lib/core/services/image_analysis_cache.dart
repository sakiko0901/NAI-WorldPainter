import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Stores WD-Tagger text only, keyed by image bytes and tagger settings.
class ImageAnalysisCache {
  ImageAnalysisCache({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;
  ImageAnalysisCache.memory() : _directory = null;

  final Future<Directory> Function()? _directory;
  final Map<String, String> _entries = {};
  Future<void> _queue = Future.value();
  bool _loaded = false;
  int _epoch = 0;
  static const maxEntries = 256;
  static const maxBytes = 2 * 1024 * 1024;

  static String key(String imageBase64, List<Object?> configuration) => sha256
      .convert(utf8.encode(jsonEncode([
        'image-analysis-v1',
        sha256.convert(base64Decode(imageBase64)).toString(),
        ...configuration,
      ])))
      .toString();

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<File?> _file() async {
    if (_directory == null) return null;
    final dir = await _directory!();
    // Old mixed caches cannot distinguish LLM descriptions from tagger text.
    // Discard them rather than retaining any previous LLM analysis.
    for (final suffix in ['', '.tmp']) {
      final legacy =
          File('${dir.path}/assistant_image_analysis_v1.json$suffix');
      if (await legacy.exists()) await legacy.delete();
    }
    return File('${dir.path}/assistant_wd_tagger_v1.json');
  }

  Future<void> initialize() => _locked(_load);

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final file = await _file();
      if (file != null &&
          await file.exists() &&
          await file.length() <= maxBytes) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          for (final entry in data.entries.take(maxEntries)) {
            if (entry.key is String &&
                RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) &&
                entry.value is String &&
                (entry.value as String).trim().isNotEmpty) {
              _entries[entry.key] = entry.value;
            }
          }
        }
      }
    } catch (_) {
      // Corrupt or unavailable storage must not prevent image analysis.
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final file = await _file();
    if (file == null) return;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(_entries), flush: true);
    await temp.rename(file.path);
  }

  Future<String> resolve(String key, Future<String> Function() analyze) async {
    final epoch = _epoch;
    final cached = await _locked(() async {
      await _load();
      return _entries[key];
    });
    if (cached != null) return cached;
    final result = await analyze();
    if (result.trim().isEmpty || utf8.encode(result).length > maxBytes ~/ 2) {
      return result;
    }
    await _locked(() async {
      if (_epoch != epoch) return;
      _entries.remove(key);
      _entries[key] = result;
      while (_entries.length > maxEntries ||
          utf8.encode(jsonEncode(_entries)).length > maxBytes) {
        _entries.remove(_entries.keys.first);
      }
      try {
        await _persist();
      } catch (_) {
        // Still reuse in memory if disk storage is unavailable.
      }
    });
    return result;
  }

  Future<void> clear() {
    _epoch++;
    return _locked(() async {
      await _load();
      _entries.clear();
      final file = await _file();
      if (file != null && await file.exists()) await file.delete();
      final temp = file == null ? null : File('${file.path}.tmp');
      if (temp != null && await temp.exists()) await temp.delete();
    });
  }
}
