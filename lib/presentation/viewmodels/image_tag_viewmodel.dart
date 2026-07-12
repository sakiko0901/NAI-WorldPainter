import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/nai_metadata_parser.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/domain/entities/image_tag_result.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/analyze_image_tags.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';

/// 分析模式
enum TagAnalysisMode { naiMetadata, wdTagger }

class ImageTagViewModel extends ChangeNotifier {
  final AnalyzeImageTagsUseCase _useCase;

  ImageTagViewModel({required AnalyzeImageTagsUseCase useCase})
      : _useCase = useCase;

  // ── 状态 ──
  String? imagePath;
  TagAnalysisMode mode = TagAnalysisMode.naiMetadata;
  ImageTagResult? result;
  bool isAnalyzing = false;
  String? error;

  // WD-Tagger 设置
  double generalThreshold = 0.35;
  double characterThreshold = 0.85;

  // 中文翻译
  Map<String, String> tagTranslations = {}; // tag → 中文
  bool isTranslating = false;

  // ── 初始化：从缓存恢复 ──
  Future<void> loadCache() async {
    final prefs = sl<SharedPreferences>();
    imagePath = prefs.getString(AppConstants.keyImageTagImagePath);
    final modeIndex = prefs.getInt(AppConstants.keyImageTagMode) ?? 0;
    mode =
        modeIndex == 1 ? TagAnalysisMode.wdTagger : TagAnalysisMode.naiMetadata;
    generalThreshold =
        prefs.getDouble(AppConstants.keyImageTagGeneralThreshold) ?? 0.35;
    characterThreshold =
        prefs.getDouble(AppConstants.keyImageTagCharacterThreshold) ?? 0.85;

    final resultJson = prefs.getString(AppConstants.keyImageTagResultJson);
    if (resultJson != null) {
      try {
        result = ImageTagResult.fromJson(
            jsonDecode(resultJson) as Map<String, dynamic>);
      } catch (_) {
        result = null;
      }
    }
    notifyListeners();
  }

  // ── 图片选择 ──
  Future<void> setImagePath(String path) async {
    imagePath = path;
    result = null;
    error = null;
    tagTranslations = {};
    await _saveCache();
    notifyListeners();
  }

  // ── 模式切换 ──
  Future<void> setMode(TagAnalysisMode m) async {
    mode = m;
    result = null;
    error = null;
    tagTranslations = {};
    await _saveCache();
    notifyListeners();
  }

  // ── WD-Tagger 设置 ──
  Future<void> setGeneralThreshold(double v) async {
    generalThreshold = v;
    final prefs = sl<SharedPreferences>();
    await prefs.setDouble(AppConstants.keyImageTagGeneralThreshold, v);
    notifyListeners();
  }

  Future<void> setCharacterThreshold(double v) async {
    characterThreshold = v;
    final prefs = sl<SharedPreferences>();
    await prefs.setDouble(AppConstants.keyImageTagCharacterThreshold, v);
    notifyListeners();
  }

  // ── 分析 ──
  Future<void> analyze() async {
    if (imagePath == null) return;
    isAnalyzing = true;
    error = null;
    notifyListeners();

    try {
      if (mode == TagAnalysisMode.naiMetadata) {
        result = await NaiMetadataParser.parse(imagePath!);
        if (result == null) {
          error = '未检测到 NAI 元数据，该图片可能不是 NovelAI 生成的';
        }
      } else {
        // WD-Tagger：在线分析
        final wdResult = await _useCase.analyze(
          imagePath: imagePath!,
          modelRepo: 'SmilingWolf/wd-swinv2-tagger-v3',
          generalThreshold: generalThreshold,
          characterThreshold: characterThreshold,
        );
        final generalTags = wdResult.generalTags.entries
            .map((e) =>
                TagEntry(tag: e.key, confidence: e.value, selected: true))
            .toList();
        final characterTags = wdResult.characterTags.entries
            .map((e) =>
                TagEntry(tag: e.key, confidence: e.value, selected: true))
            .toList();
        result = ImageTagResult(
          source: TagSource.wdTagger,
          general: generalTags,
          character: characterTags,
        );
      }
    } catch (e) {
      error = '分析失败: $e';
      result = null;
    }

    isAnalyzing = false;
    await _saveCache();
    notifyListeners();
  }

  // ── 标签选择 ──
  Future<void> toggleTag(TagSource source,
      {int? generalIndex, int? characterIndex, int? negativeIndex}) async {
    if (result == null) return;
    List<TagEntry> newGeneral = List.from(result!.general);
    List<TagEntry> newCharacter = List.from(result!.character);
    List<TagEntry> newNegative = List.from(result!.negativeEntries);

    if (generalIndex != null && generalIndex < newGeneral.length) {
      newGeneral[generalIndex] = newGeneral[generalIndex]
          .copyWith(selected: !newGeneral[generalIndex].selected);
    }
    if (characterIndex != null && characterIndex < newCharacter.length) {
      newCharacter[characterIndex] = newCharacter[characterIndex]
          .copyWith(selected: !newCharacter[characterIndex].selected);
    }
    if (negativeIndex != null && negativeIndex < newNegative.length) {
      newNegative[negativeIndex] = newNegative[negativeIndex]
          .copyWith(selected: !newNegative[negativeIndex].selected);
    }

    result = result!.copyWithTagSelections(
      general: newGeneral,
      character: newCharacter,
      negativeEntries: newNegative,
    );
    await _saveCache();
    notifyListeners();
  }

  Future<void> selectAllGeneral() async {
    if (result == null) return;
    result = result!.copyWithTagSelections(
      general: result!.general.map((e) => e.copyWith(selected: true)).toList(),
    );
    await _saveCache();
    notifyListeners();
  }

  /// 反选：未选中→选中，选中→取消
  Future<void> invertGeneral() async {
    if (result == null) return;
    result = result!.copyWithTagSelections(
      general: result!.general
          .map((e) => e.copyWith(selected: !e.selected))
          .toList(),
    );
    await _saveCache();
    notifyListeners();
  }

  Future<void> selectAllNegative() async {
    if (result == null) return;
    result = result!.copyWithTagSelections(
      negativeEntries: result!.negativeEntries
          .map((e) => e.copyWith(selected: true))
          .toList(),
    );
    await _saveCache();
    notifyListeners();
  }

  Future<void> invertNegative() async {
    if (result == null) return;
    result = result!.copyWithTagSelections(
      negativeEntries: result!.negativeEntries
          .map((e) => e.copyWith(selected: !e.selected))
          .toList(),
    );
    await _saveCache();
    notifyListeners();
  }

  // ── 中文翻译 ──
  Future<void> translateTags() async {
    if (result == null || isTranslating) return;
    isTranslating = true;
    notifyListeners();

    try {
      // 优先用 main 角色，回退到 vision 角色
      final chatVm = sl<LlmChatViewModel>();
      await chatVm.ensureInitialized();
      var config = chatVm.mainConfig;
      if (!config.isConfigured) {
        config = chatVm.visionConfig;
      }

      if (!config.isConfigured) {
        isTranslating = false;
        error = '请先在 LLM 配置中设置主模型或识图模型';
        notifyListeners();
        return;
      }
      final String apiKeyFinal = config.apiKey;
      final String baseUrl = config.baseUrl;
      final String model = config.model;

      // 收集所有需要翻译的 tag
      final allTags = <String>{
        ...result!.general.map((e) => e.tag),
        ...result!.character.map((e) => e.tag),
        ...result!.negativeEntries.map((e) => e.tag),
      };
      if (allTags.isEmpty) {
        isTranslating = false;
        notifyListeners();
        return;
      }

      final tagList = allTags.join(', ');
      final api = sl<LlmApiService>();
      final reply = await api.chatCompletions(
        apiKey: apiKeyFinal,
        baseUrl: baseUrl,
        model: model,
        messages: [
          {
            'role': 'system',
            'content': '你是一个 Danbooru 标签翻译器。用户会给你一串英文标签（逗号分隔），'
                '你需要把每个标签翻译成简体中文，返回一个 JSON 对象，key 是原英文标签，value 是中文翻译。'
                '只输出 JSON，不要任何其他文字。例如：\n'
                '输入：1girl, long_hair, blue_eyes\n'
                '输出：{"1girl": "1个女孩", "long_hair": "长发", "blue_eyes": "蓝眼睛"}'
          },
          {'role': 'user', 'content': tagList},
        ],
      );

      // 解析翻译结果
      final cleaned = reply.trim();
      final jsonStr = _extractJsonObject(cleaned) ?? cleaned;
      final parsed = jsonDecode(jsonStr);
      if (parsed is Map) {
        final newTranslations = <String, String>{};
        for (final e in parsed.entries) {
          newTranslations[e.key.toString()] = e.value.toString();
        }
        tagTranslations = newTranslations;
      }
    } catch (e) {
      // 翻译失败不影响主功能，静默处理
    }

    isTranslating = false;
    notifyListeners();
  }

  String? _extractJsonObject(String s) {
    final start = s.indexOf('{');
    if (start < 0) return null;
    int depth = 0;
    for (int i = start; i < s.length; i++) {
      if (s[i] == '{') depth++;
      if (s[i] == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }

  // ── 缓存 ──
  Future<void> _saveCache() async {
    final prefs = sl<SharedPreferences>();
    if (imagePath != null) {
      await prefs.setString(AppConstants.keyImageTagImagePath, imagePath!);
    }
    await prefs.setInt(
        AppConstants.keyImageTagMode, mode == TagAnalysisMode.wdTagger ? 1 : 0);
    if (result != null) {
      await prefs.setString(
          AppConstants.keyImageTagResultJson, jsonEncode(result!.toJson()));
    } else {
      await prefs.remove(AppConstants.keyImageTagResultJson);
    }
  }
}
