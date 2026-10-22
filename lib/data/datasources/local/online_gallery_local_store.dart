import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/online_gallery.dart';

/// Bookmarks have their own keys and never enter generation history/statistics.
class OnlineGalleryLocalStore {
  static const favoritesKey = 'online_gallery.favorites.v1';
  static const queryKey = 'online_gallery.query.v1';
  final SharedPreferences prefs;
  Future<void> _writes = Future.value();
  OnlineGalleryLocalStore(this.prefs);

  List<OnlineGalleryItem> _readFavorites() {
    final raw = prefs.getString(favoritesKey);
    if (raw == null) return [];
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1 || json['items'] is! List) {
      throw const FormatException('在线收藏数据格式不正确');
    }
    return (json['items'] as List)
        .map((value) =>
            OnlineGalleryItem.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<List<OnlineGalleryItem>> favorites() async {
    await _writes;
    return _readFavorites();
  }

  Future<void> setFavorite(OnlineGalleryItem item, bool value) {
    final operation = _writes.then((_) async {
      final items =
          _readFavorites().where((entry) => entry.key != item.key).toList();
      if (value) items.insert(0, item);
      final saved = await prefs.setString(
          favoritesKey,
          jsonEncode({
            'version': 1,
            'items': items.map((entry) => entry.toJson()).toList(),
          }));
      if (!saved) throw StateError('在线收藏保存失败');
    });
    _writes =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  OnlineGalleryQuery? loadQuery() {
    final raw = prefs.getString(queryKey);
    if (raw == null) return null;
    return OnlineGalleryQuery.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  Future<void> saveQuery(OnlineGalleryQuery query) async {
    if (!await prefs.setString(queryKey, jsonEncode(query.toJson()))) {
      throw StateError('图库筛选保存失败');
    }
  }
}

class OnlineGalleryCredentialStore {
  static const key = 'online_gallery.gelbooru.credentials.v1';
  final FlutterSecureStorage storage;
  OnlineGalleryCredentialStore([FlutterSecureStorage? storage])
      : storage = storage ?? const FlutterSecureStorage();

  Future<OnlineGalleryCredentials?> read() async {
    final raw = await storage.read(key: key);
    if (raw == null) return null;
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final userId = value['userId'] as String? ?? '';
    final apiKey = value['apiKey'] as String? ?? '';
    if (userId.isEmpty || apiKey.isEmpty) return null;
    return OnlineGalleryCredentials(userId: userId, apiKey: apiKey);
  }

  Future<void> write(OnlineGalleryCredentials credentials) async {
    final userId = credentials.userId.trim();
    final apiKey = credentials.apiKey.trim();
    if (userId.isEmpty && apiKey.isEmpty) {
      await storage.delete(key: key);
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(userId) || apiKey.isEmpty) {
      throw ArgumentError('请填写有效的 Gelbooru User ID 和 API Key');
    }
    await storage.write(
        key: key, value: jsonEncode({'userId': userId, 'apiKey': apiKey}));
  }
}
