import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';

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
}
