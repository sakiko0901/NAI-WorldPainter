import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';
import 'package:nai_huishi/domain/usecases/manage_vibe_encodings.dart';

class VibeEncodingViewModel extends ChangeNotifier {
  final ManageVibeEncodingsUseCase _manage;

  VibeEncodingViewModel(this._manage);

  List<VibeEncoding> encodings = const [];
  bool isLoading = false;
  String? error;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      encodings = await _manage.getAll();
    } catch (e) {
      error = '读取氛围编码失败：$e';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<VibeEncoding?> findBySourceImagePath(String path) =>
      _manage.findBySourceImagePath(path);

  Future<List<VibeEncoding>> createManyFromEncodings({
    required String titlePrefix,
    required String sourceImagePath,
    required List<String> encodedVibes,
    String? encodedModel,
  }) async {
    final created = await _manage.createManyFromEncodings(
      titlePrefix: titlePrefix,
      sourceImagePath: sourceImagePath,
      encodedVibes: encodedVibes,
      encodedModel: encodedModel,
    );
    await load();
    return created;
  }

  Future<VibeEncoding> updateTitle(VibeEncoding encoding, String title) async {
    final updated = await _manage.updateTitle(encoding, title);
    await load();
    return updated;
  }

  Future<void> delete(int id) async {
    await _manage.delete(id);
    await load();
  }
}
