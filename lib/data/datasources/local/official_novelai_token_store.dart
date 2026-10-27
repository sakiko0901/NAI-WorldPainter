import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/entities/novelai_connection.dart';

class OfficialNovelAiTokenStore {
  final FlutterSecureStorage _storage;

  OfficialNovelAiTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> read() =>
      _storage.read(key: AppConstants.keyNovelAiOfficialToken);

  Future<void> write(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(
      key: AppConstants.keyNovelAiOfficialToken,
      value: normalized,
    );
  }

  Future<void> clear() =>
      _storage.delete(key: AppConstants.keyNovelAiOfficialToken);

  // A relay has its own credential. Changing the URL must never forward the
  // user's existing official token (or another relay's key) to a new host.
  String _relayKey(String baseUrl) =>
      '${AppConstants.keyNovelAiOfficialToken}_relay_${sha256.convert(utf8.encode(NovelAiConnection.normalizeBaseUrl(baseUrl)))}';

  Future<String?> readForBaseUrl(String baseUrl) =>
      NovelAiConnection.isCustomBaseUrl(baseUrl)
          ? _storage.read(key: _relayKey(baseUrl))
          : read();

  Future<void> writeForBaseUrl(String baseUrl, String token) async {
    if (!NovelAiConnection.isCustomBaseUrl(baseUrl)) {
      await write(token);
      return;
    }
    final key = _relayKey(baseUrl);
    final normalized = token.trim();
    if (normalized.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: normalized);
    }
  }
}
