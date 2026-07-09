import 'dart:convert';

import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';

/// 关键词抽取结果。
///
/// 由便宜小模型从用户原文中切出的"用于 Danbooru 检索的种子词"。
/// - characters：每条对应一个角色（多角色时分开列出）
/// - scene：环境/动作/表情/互动
/// - style：画风/构图/镜头/光影
/// - nsfw：NSFW 关键词，无则空数组
class ExtractedKeywords {
  final List<String> characters;
  final List<String> scene;
  final List<String> style;
  final List<String> nsfw;

  const ExtractedKeywords({
    required this.characters,
    required this.scene,
    required this.style,
    required this.nsfw,
  });

  bool get isEmpty =>
      characters.isEmpty && scene.isEmpty && style.isEmpty && nsfw.isEmpty;
}

/// 关键词抽取 UseCase。
///
/// 调一次便宜的小模型，让它把用户原文拆成 JSON 形式的种子词。
/// 系统提示词内联在本类中（内置，用户不可改）。
class ExtractKeywordsUseCase {
  final LlmApiService _api;

  ExtractKeywordsUseCase(this._api);

  static const String _systemPrompt =
      '你是 Danbooru 标签检索的"种子词抽取器"。任务是把用户用中文/英文写的画面描述拆成若干个用于 Danbooru 语义搜索的关键词。\n'
      '\n'
      '【输出格式（必须严格遵守）】\n'
      '只输出一个 JSON 对象，不要任何解释、不要 markdown 代码块包裹、不要前后空行。结构：\n'
      '{\n'
      '  "characters": ["角色1的描述", "角色2的描述"],\n'
      '  "scene": ["场景/动作/表情等关键词"],\n'
      '  "style": ["画风/构图/镜头等关键词"],\n'
      '  "nsfw": ["nsfw 关键词，无则空数组"]\n'
      '}\n'
      '\n'
      '【拆分规则】\n'
      '1. characters：每个角色一项，包含外貌、服装、姿势的简短描述。单角色就一项；多角色就分别列出。如果是有名作品角色，写上"角色名 (作品名)"格式。\n'
      '2. scene：环境、地点、动作、表情、互动关键词，每条一个独立短语。\n'
      '3. style：画质偏好、画风、构图、镜头、光影。用户没说就给空数组。\n'
      '4. nsfw：仅当用户明确要求 NSFW 时才填，其他情况空数组。\n'
      '\n'
      '【关键约束】\n'
      '- 中英文都行，Danbooru 服务支持中文语义检索。\n'
      '- 不要凭空补充用户没写的元素（不加戏）。\n'
      '- 每条短语 1-4 个词，过长会降低检索精度。\n'
      '- 用户文字模糊时（如"画一个少女"），最少给出 characters: ["少女"]，其他可空。\n'
      '- 严禁输出 JSON 之外的任何文字。';

  Future<ExtractedKeywords> call({
    required String userText,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final reply = await _api.chatCompletions(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      messages: [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userText},
      ],
    );
    return _parse(reply, fallbackText: userText);
  }

  /// 解析 LLM 返回的 JSON。容错策略：
  ///   1. 直接尝试 jsonDecode；
  ///   2. 失败则从文本中提取首个 `{...}` 子串再解析；
  ///   3. 全部失败时退化为 `characters=[fallbackText]`，避免完全不可用。
  ExtractedKeywords _parse(String reply, {required String fallbackText}) {
    final cleaned = _stripCodeFence(reply.trim());
    Map<String, dynamic>? obj = _tryDecode(cleaned);
    if (obj == null) {
      final jsonSub = _extractJsonObject(cleaned);
      if (jsonSub != null) obj = _tryDecode(jsonSub);
    }
    if (obj == null) {
      return ExtractedKeywords(
        characters: [fallbackText.trim()],
        scene: const [],
        style: const [],
        nsfw: const [],
      );
    }
    return ExtractedKeywords(
      characters: _toStringList(obj['characters']),
      scene: _toStringList(obj['scene']),
      style: _toStringList(obj['style']),
      nsfw: _toStringList(obj['nsfw']),
    );
  }

  /// 去掉 ```json ... ``` 这种 markdown 包裹（若小模型不听话）。
  String _stripCodeFence(String s) {
    var t = s;
    if (t.startsWith('```')) {
      final firstNl = t.indexOf('\n');
      if (firstNl >= 0) t = t.substring(firstNl + 1);
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    }
    return t.trim();
  }

  Map<String, dynamic>? _tryDecode(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  /// 从含杂质的文本中提取首个完整的 `{...}` 子串（按括号深度匹配）。
  String? _extractJsonObject(String s) {
    final start = s.indexOf('{');
    if (start < 0) return null;
    int depth = 0;
    for (int i = start; i < s.length; i++) {
      final ch = s[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }

  List<String> _toStringList(dynamic v) {
    if (v is! List) return const [];
    final out = <String>[];
    for (final e in v) {
      if (e == null) continue;
      final s = e.toString().trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }
}
