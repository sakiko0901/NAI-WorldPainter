import 'package:flutter/material.dart';

import 'package:nai_huishi/domain/entities/pixiv_settings.dart';
import 'package:nai_huishi/domain/usecases/manage_pixiv_settings.dart';

class PixivSettingsViewModel extends ChangeNotifier {
  final ManagePixivSettingsUseCase _useCase;

  PixivSettingsViewModel(this._useCase);

  PixivSettings? _settings;
  PixivSettings? get settings => _settings;
  bool _loading = false;
  bool get loading => _loading;

  List<Map<String, String>> customCharacters = const [];
  List<Map<String, String>> customSurroundings = const [];

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _settings = await _useCase.load();
      customCharacters = await _useCase.loadCustomCharacters();
      customSurroundings = await _useCase.loadCustomSurroundings();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> save(PixivSettings s) async {
    _settings = s;
    await _useCase.save(s);
    notifyListeners();
  }

  Future<void> updateCustomCharacters(List<Map<String, String>> e) async {
    customCharacters = List<Map<String, String>>.from(e);
    await _useCase.saveCustomCharacters(customCharacters);
    notifyListeners();
  }

  Future<void> updateCustomSurroundings(List<Map<String, String>> e) async {
    customSurroundings = List<Map<String, String>>.from(e);
    await _useCase.saveCustomSurroundings(customSurroundings);
    notifyListeners();
  }
}
