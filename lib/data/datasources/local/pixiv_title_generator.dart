import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:nai_huishi/data/datasources/local/pixiv_settings_local_datasource.dart';

/// 从 prompt 中匹配预置/自定义角色，再可选叠加场景，生成花式标题。
/// 移植自 SANP src/image2pixiv.py 的标题生成逻辑。
class PixivTitleGenerator {
  final PixivSettingsLocalDatasource _settings;
  final Random _random;

  PixivTitleGenerator(this._settings, {Random? random})
      : _random = random ?? Random();

  List<Map<String, String>>? _presetChars;
  List<Map<String, String>>? _presetSurroundings;

  Future<List<Map<String, String>>> _loadPresetChars() async {
    if (_presetChars != null) return _presetChars!;
    final raw = await rootBundle.loadString('assets/pixiv/characters.json');
    final list = jsonDecode(raw) as List;
    _presetChars = list
        .whereType<Map>()
        .map((e) => {
              'name': e['name']?.toString() ?? '',
              'tag': e['tag']?.toString() ?? '',
            })
        .where((m) => m['name']!.isNotEmpty && m['tag']!.isNotEmpty)
        .toList();
    return _presetChars!;
  }

  Future<List<Map<String, String>>> _loadPresetSurroundings() async {
    if (_presetSurroundings != null) return _presetSurroundings!;
    final raw = await rootBundle.loadString('assets/pixiv/surroundings.json');
    final list = jsonDecode(raw) as List;
    _presetSurroundings = list
        .whereType<Map>()
        .map((e) => {
              'name': e['name']?.toString() ?? '',
              'tag': e['tag']?.toString() ?? '',
            })
        .where((m) => m['name']!.isNotEmpty && m['tag']!.isNotEmpty)
        .toList();
    return _presetSurroundings!;
  }

  Future<List<Map<String, String>>> _allCharacters() async {
    final preset = await _loadPresetChars();
    final custom = _settings.loadCustomCharacters();
    // 自定义优先，预置后追加
    return [...custom, ...preset];
  }

  Future<List<Map<String, String>>> _allSurroundings() async {
    final preset = await _loadPresetSurroundings();
    final custom = _settings.loadCustomSurroundings();
    return [...custom, ...preset];
  }

  /// 输入 prompt 文本，生成标题。
  /// - 未匹配到角色 → 返回 fallback
  /// - 匹配到 + R18 + 匹配到场景 → 随机出「和X在Y涩涩~」「和X涩涩~」「X~」
  /// - 匹配到 + R18 但没场景 → 随机出「X~」「和X涩涩~」
  /// - 匹配到 + 非 R18 → 「X~」
  Future<String> generate({
    required String prompt,
    required bool isR18,
    String fallback = '无题',
  }) async {
    final lower = prompt.toLowerCase();
    String? hitName;
    for (final entry in await _allCharacters()) {
      final tag = entry['tag']!.toLowerCase();
      if (lower.contains(tag)) {
        hitName = entry['name'];
        break;
      }
    }
    if (hitName == null || hitName.isEmpty) return fallback;

    if (!isR18) return '$hitName~';

    String? hitSurround;
    for (final entry in await _allSurroundings()) {
      final tag = entry['tag']!.toLowerCase();
      if (lower.contains(tag)) {
        hitSurround = entry['name'];
        break;
      }
    }

    final candidates = <String>[
      '$hitName~',
      '和$hitName涩涩~',
      if (hitSurround != null && hitSurround.isNotEmpty)
        '和$hitName在$hitSurround~',
    ];
    return candidates[_random.nextInt(candidates.length)];
  }
}
