import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

class NsfwBookEntry {
  final int id;
  final String title;
  final String source;
  final List<String> keywords;
  final String content;

  NsfwBookEntry({
    required this.id,
    required this.title,
    required this.source,
    required this.keywords,
    required this.content,
  });

  factory NsfwBookEntry.fromJson(Map<String, dynamic> json) {
    return NsfwBookEntry(
      id: json['id'] as int,
      title: json['title'] as String,
      source: json['source'] as String,
      keywords: (json['keywords'] as List<dynamic>).cast<String>(),
      content: json['content'] as String,
    );
  }
}

class NsfwBook {
  /// 默认打包进 APK 的知识库 asset 路径。
  static const String defaultAssetPath = 'lib/assets/nsfw_knowledge.json';

  final List<NsfwBookEntry> _entries = [];
  bool _loaded = false;
  String? _lastPath;

  bool get isLoaded => _loaded;
  int get entryCount => _entries.length;
  String? get lastPath => _lastPath;

  /// 从 APK 内打包的 asset 加载默认知识库。
  Future<bool> loadFromAsset({String assetPath = defaultAssetPath}) async {
    try {
      final jsonStr = await rootBundle.loadString(assetPath);
      _entries.clear();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final entriesJson = data['entries'] as List<dynamic>;
      for (final e in entriesJson) {
        _entries.add(NsfwBookEntry.fromJson(e as Map<String, dynamic>));
      }
      _loaded = true;
      _lastPath = 'asset:$assetPath';
      return true;
    } catch (_) {
      _loaded = false;
      return false;
    }
  }

  /// 从外部文件路径加载知识库 JSON（覆盖 asset 默认知识库）。
  Future<bool> load(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _loaded = false;
        return false;
      }
      final jsonStr = await file.readAsString();
      _entries.clear();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final entriesJson = data['entries'] as List<dynamic>;
      for (final e in entriesJson) {
        _entries.add(NsfwBookEntry.fromJson(e as Map<String, dynamic>));
      }
      _loaded = true;
      _lastPath = filePath;
      return true;
    } catch (_) {
      _loaded = false;
      return false;
    }
  }

  /// 从 JSON 字符串加载（测试/动态构建用）。
  void loadFromString(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final entriesJson = data['entries'] as List<dynamic>;
    _entries.clear();
    for (final e in entriesJson) {
      _entries.add(NsfwBookEntry.fromJson(e as Map<String, dynamic>));
    }
    _loaded = true;
  }

  /// 清除当前加载的知识库。
  void unload() {
    _entries.clear();
    _loaded = false;
    _lastPath = null;
  }

  /// 对用户输入做关键词匹配，返回命中的知识条目。
  ///
  /// 匹配规则：将用户输入转小写，检查 entry.keywords 中是否有任意词出现在输入中。
  /// 英文关键词要求作为独立词元匹配（前后边界非字母数字），中文关键词做子串匹配。
  ///
  /// [maxResults] 限制返回条数；[maxTotalLength] 限制所有返回内容的总字符数。
  List<NsfwBookEntry> match(
    String userInput, {
    int maxResults = 5,
    int maxTotalLength = 2000,
  }) {
    if (!_loaded || userInput.trim().isEmpty) return [];

    final input = userInput.toLowerCase();
    final hitSet = <int>{};

    for (final entry in _entries) {
      for (final kw in entry.keywords) {
        final kwLower = kw.toLowerCase();
        // 英文关键词：按词边界匹配
        if (RegExp(r'^[a-z][a-z0-9_]+$').hasMatch(kwLower)) {
          final re = RegExp('\\b${RegExp.escape(kwLower)}\\b');
          if (re.hasMatch(input)) {
            hitSet.add(entry.id);
            break;
          }
        } else {
          // 中文/其他：子串包含即可
          if (input.contains(kwLower)) {
            hitSet.add(entry.id);
            break;
          }
        }
      }
    }

    if (hitSet.isEmpty) return [];

    // 按 id 排序（即原有顺序），截断
    final matched = _entries.where((e) => hitSet.contains(e.id)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    // 限制条数和总字符
    final result = <NsfwBookEntry>[];
    int totalLen = 0;
    for (final e in matched) {
      if (result.length >= maxResults) break;
      final addedLen = e.content.length;
      if (totalLen + addedLen > maxTotalLength) {
        // 这条放不下时尝试截断内容
        final allowed = maxTotalLength - totalLen;
        if (allowed > 200) {
          result.add(NsfwBookEntry(
            id: e.id,
            title: e.title,
            source: e.source,
            keywords: e.keywords,
            content: e.content.substring(0, allowed),
          ));
        }
        break;
      }
      result.add(e);
      totalLen += addedLen;
    }

    return result;
  }
}
