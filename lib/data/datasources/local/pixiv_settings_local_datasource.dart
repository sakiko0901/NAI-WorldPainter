import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/entities/pixiv_settings.dart';

/// Pixiv 配置在 SharedPreferences 中的存取
class PixivSettingsLocalDatasource {
  final SharedPreferences _prefs;

  PixivSettingsLocalDatasource(this._prefs);

  // ── PixivSettings ──
  PixivSettings load() {
    return PixivSettings(
      cookie: _prefs.getString(AppConstants.keyPixivCookie) ?? '',
      csrfToken: _prefs.getString(AppConstants.keyPixivCsrfToken) ?? '',
      proxy: _prefs.getString(AppConstants.keyPixivProxy) ?? '',
      captionPrefix: _prefs.getString(AppConstants.keyPixivCaptionPrefix) ??
          AppConstants.defaultPixivCaptionPrefix,
      defaultTags: _readStringList(AppConstants.keyPixivDefaultTags) ??
          List<String>.from(AppConstants.defaultPixivTags),
      r18Default: _prefs.getBool(AppConstants.keyPixivR18Default) ?? false,
      allowTagEdit: _prefs.getBool(AppConstants.keyPixivAllowTagEdit) ?? true,
      stripMetadata: _prefs.getBool(AppConstants.keyPixivStripMetadata) ?? false,
      suggestTagsEnabled:
          _prefs.getBool(AppConstants.keyPixivSuggestTagsEnabled) ?? true,
      cooldownMinutes: _prefs.getInt(AppConstants.keyPixivCooldownMinutes) ??
          AppConstants.defaultPixivCooldownMinutes,
      repTagsPercent: _prefs.getDouble(AppConstants.keyPixivRepTagsPercent) ??
          AppConstants.defaultPixivRepTagsPercent,
      repTagsFill: _prefs.getString(AppConstants.keyPixivRepTagsFill) ??
          AppConstants.defaultPixivRepTagsFill,
      junkText: _prefs.getString(AppConstants.keyPixivJunkText) ??
          AppConstants.defaultPixivJunkText,
    );
  }

  Future<void> save(PixivSettings s) async {
    await _prefs.setString(AppConstants.keyPixivCookie, s.cookie);
    await _prefs.setString(AppConstants.keyPixivCsrfToken, s.csrfToken);
    await _prefs.setString(AppConstants.keyPixivProxy, s.proxy);
    await _prefs.setString(AppConstants.keyPixivCaptionPrefix, s.captionPrefix);
    await _writeStringList(AppConstants.keyPixivDefaultTags, s.defaultTags);
    await _prefs.setBool(AppConstants.keyPixivR18Default, s.r18Default);
    await _prefs.setBool(AppConstants.keyPixivAllowTagEdit, s.allowTagEdit);
    await _prefs.setBool(AppConstants.keyPixivStripMetadata, s.stripMetadata);
    await _prefs.setBool(
        AppConstants.keyPixivSuggestTagsEnabled, s.suggestTagsEnabled);
    await _prefs.setInt(AppConstants.keyPixivCooldownMinutes, s.cooldownMinutes);
    await _prefs.setDouble(AppConstants.keyPixivRepTagsPercent, s.repTagsPercent);
    await _prefs.setString(AppConstants.keyPixivRepTagsFill, s.repTagsFill);
    await _prefs.setString(AppConstants.keyPixivJunkText, s.junkText);
  }

  // ── 自定义角色 / 场景字典 ──
  List<Map<String, String>> loadCustomCharacters() =>
      _readMapList(AppConstants.keyPixivCustomCharacters);

  Future<void> saveCustomCharacters(List<Map<String, String>> entries) =>
      _writeMapList(AppConstants.keyPixivCustomCharacters, entries);

  List<Map<String, String>> loadCustomSurroundings() =>
      _readMapList(AppConstants.keyPixivCustomSurroundings);

  Future<void> saveCustomSurroundings(List<Map<String, String>> entries) =>
      _writeMapList(AppConstants.keyPixivCustomSurroundings, entries);

  // ── helpers ──
  List<String>? _readStringList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeStringList(String key, List<String> values) async {
    await _prefs.setString(key, jsonEncode(values));
  }

  List<Map<String, String>> _readMapList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeMapList(
      String key, List<Map<String, String>> entries) async {
    await _prefs.setString(key, jsonEncode(entries));
  }
}
