import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';

/// 设置 ViewModel
class SettingsViewModel extends ChangeNotifier {
  final ManageSettingsUseCase _manageSettings;

  SettingsViewModel(this._manageSettings);

  String? _apiKey;
  String _baseUrl = '';
  String? _defaultModel;
  String _defaultResolution = '832x1216';
  String _defaultSampler = 'k_euler';
  double _defaultScale = 5.0;
  double _defaultCfgRescale = 0.0;
  String _defaultNoiseSchedule = 'native';
  String _defaultStyleWords = '';
  bool _isTesting = false;
  bool? _connectionResult;
  String? errorMessage;

  // 图像 API 供应商配置（旧 v1 单值，保留 getter 兼容）
  String _novelAiBaseUrl = '';
  String? _novelAiApiKey;
  String _novelAiModel = '';
  String _gptBaseUrl = '';
  String? _gptApiKey;
  String _gptModel = '';
  String _nanoBaseUrl = '';
  String? _nanoApiKey;
  String _nanoModel = '';

  // v2 多中转站
  Map<ImageProviderType, List<ApiEndpoint>> _endpoints = {
    ImageProviderType.novelAi: const [],
    ImageProviderType.gpt: const [],
    ImageProviderType.nanoBanana: const [],
  };
  Map<ImageProviderType, String?> _activeEndpointId = {
    ImageProviderType.novelAi: null,
    ImageProviderType.gpt: null,
    ImageProviderType.nanoBanana: null,
  };
  Map<ImageProviderType, String?> _activeModel = {
    ImageProviderType.novelAi: null,
    ImageProviderType.gpt: null,
    ImageProviderType.nanoBanana: null,
  };

  String? get apiKey => _apiKey;
  String get baseUrl => _baseUrl;
  String? get defaultModel => _defaultModel;
  String get defaultResolution => _defaultResolution;
  String get defaultSampler => _defaultSampler;
  double get defaultScale => _defaultScale;
  double get defaultCfgRescale => _defaultCfgRescale;
  String get defaultNoiseSchedule => _defaultNoiseSchedule;
  String get defaultStyleWords => _defaultStyleWords;
  bool get isTesting => _isTesting;
  bool? get connectionResult => _connectionResult;

  String get novelAiBaseUrl => _novelAiBaseUrl;
  String? get novelAiApiKey => _novelAiApiKey;
  String get novelAiModel => _novelAiModel;
  String get gptBaseUrl => _gptBaseUrl;
  String? get gptApiKey => _gptApiKey;
  String get gptModel => _gptModel;
  String get nanoBaseUrl => _nanoBaseUrl;
  String? get nanoApiKey => _nanoApiKey;
  String get nanoModel => _nanoModel;

  // v2 多中转站访问器
  List<ApiEndpoint> endpoints(ImageProviderType p) =>
      _endpoints[p] ?? const <ApiEndpoint>[];
  String? activeEndpointId(ImageProviderType p) => _activeEndpointId[p];
  String? activeModel(ImageProviderType p) => _activeModel[p];
  ApiEndpoint? activeEndpoint(ImageProviderType p) {
    final list = endpoints(p);
    if (list.isEmpty) return null;
    final id = activeEndpointId(p);
    if (id != null) {
      try {
        return list.firstWhere((e) => e.id == id);
      } catch (_) {/* fall through */}
    }
    return list.first;
  }

  /// 加载所有设置
  Future<void> loadSettings() async {
    _apiKey = await _manageSettings.getApiKey();
    _baseUrl = await _manageSettings.getBaseUrl();
    _defaultModel = await _manageSettings.getDefaultModel();
    _defaultResolution = await _manageSettings.getDefaultResolution();
    _defaultSampler = await _manageSettings.getDefaultSampler();
    _defaultScale = await _manageSettings.getDefaultScale();
    _defaultCfgRescale = await _manageSettings.getDefaultCfgRescale();
    _defaultNoiseSchedule = await _manageSettings.getDefaultNoiseSchedule();
    _defaultStyleWords = await _manageSettings.getDefaultStyleWords();

    // 加载图像供应商配置
    _novelAiBaseUrl = await _manageSettings.getImageProviderNovelAiBaseUrl();
    _novelAiApiKey = await _manageSettings.getImageProviderNovelAiApiKey();
    _novelAiModel = await _manageSettings.getImageProviderNovelAiModel();
    _gptBaseUrl = await _manageSettings.getImageProviderGptBaseUrl();
    _gptApiKey = await _manageSettings.getImageProviderGptApiKey();
    _gptModel = await _manageSettings.getImageProviderGptModel();
    _nanoBaseUrl = await _manageSettings.getImageProviderNanoBaseUrl();
    _nanoApiKey = await _manageSettings.getImageProviderNanoApiKey();
    _nanoModel = await _manageSettings.getImageProviderNanoModel();

    // 加载 v2 多中转站
    await _reloadEndpoints();

    notifyListeners();
  }

  Future<void> _reloadEndpoints() async {
    final loaded = <ImageProviderType, List<ApiEndpoint>>{};
    final ids = <ImageProviderType, String?>{};
    final models = <ImageProviderType, String?>{};
    for (final p in ImageProviderType.values) {
      loaded[p] = await _manageSettings.getEndpoints(p);
      ids[p] = await _manageSettings.getActiveEndpointId(p);
      models[p] = await _manageSettings.getActiveModel(p);
    }
    _endpoints = loaded;
    _activeEndpointId = ids;
    _activeModel = models;
  }

  /// 添加一个中转站
  Future<void> addEndpoint(ImageProviderType p, ApiEndpoint endpoint) async {
    final list = [...endpoints(p), endpoint];
    await _manageSettings.setEndpoints(p, list);
    // 若没有 active，把新加的设为 active
    if (_activeEndpointId[p] == null) {
      await _manageSettings.setActiveEndpointId(p, endpoint.id);
      if (endpoint.models.isNotEmpty) {
        await _manageSettings.setActiveModel(p, endpoint.models.first);
      }
    }
    await _reloadEndpoints();
    notifyListeners();
  }

  /// 更新一个中转站
  Future<void> updateEndpoint(ImageProviderType p, ApiEndpoint endpoint) async {
    final list = [...endpoints(p)];
    final i = list.indexWhere((e) => e.id == endpoint.id);
    if (i < 0) return;
    list[i] = endpoint;
    await _manageSettings.setEndpoints(p, list);
    // 若 active 模型已经不在新模型列表里，重置 active 模型为列表第一个
    if (_activeEndpointId[p] == endpoint.id) {
      final activeM = _activeModel[p];
      if (activeM == null || !endpoint.models.contains(activeM)) {
        await _manageSettings.setActiveModel(
          p,
          endpoint.models.isEmpty ? null : endpoint.models.first,
        );
      }
    }
    await _reloadEndpoints();
    notifyListeners();
  }

  /// 删除一个中转站
  Future<void> removeEndpoint(ImageProviderType p, String endpointId) async {
    final list = endpoints(p).where((e) => e.id != endpointId).toList();
    await _manageSettings.setEndpoints(p, list);
    if (_activeEndpointId[p] == endpointId) {
      // 重置 active 到第一项或清空
      final next = list.isEmpty ? null : list.first;
      await _manageSettings.setActiveEndpointId(p, next?.id);
      await _manageSettings.setActiveModel(
        p,
        next == null || next.models.isEmpty ? null : next.models.first,
      );
    }
    await _reloadEndpoints();
    notifyListeners();
  }

  /// 设置 active 中转站 + 模型
  Future<void> setActive(
      ImageProviderType p, String endpointId, String? model) async {
    await _manageSettings.setActiveEndpointId(p, endpointId);
    await _manageSettings.setActiveModel(p, model);
    await _reloadEndpoints();
    notifyListeners();
  }

  /// 设置 API Key
  Future<void> setApiKey(String key) async {
    await _manageSettings.setApiKey(key);
    _apiKey = key;
    _connectionResult = null;
    notifyListeners();
  }

  /// 删除 API Key
  Future<void> deleteApiKey() async {
    await _manageSettings.deleteApiKey();
    _apiKey = null;
    notifyListeners();
  }

  /// 设置 Base URL
  Future<void> setBaseUrl(String url) async {
    await _manageSettings.setBaseUrl(url);
    _baseUrl = url;
    _connectionResult = null;
    notifyListeners();
  }

  /// 设置默认模型
  Future<void> setDefaultModel(String model) async {
    await _manageSettings.setDefaultModel(model);
    _defaultModel = model;
    notifyListeners();
  }

  /// 设置默认分辨率
  Future<void> setDefaultResolution(String r) async {
    await _manageSettings.setDefaultResolution(r);
    _defaultResolution = r;
    notifyListeners();
  }

  /// 设置默认采样器
  Future<void> setDefaultSampler(String s) async {
    await _manageSettings.setDefaultSampler(s);
    _defaultSampler = s;
    notifyListeners();
  }

  /// 设置默认 scale
  Future<void> setDefaultScale(double s) async {
    await _manageSettings.setDefaultScale(s);
    _defaultScale = s;
    notifyListeners();
  }

  /// 设置默认 cfg_rescale
  Future<void> setDefaultCfgRescale(double v) async {
    await _manageSettings.setDefaultCfgRescale(v);
    _defaultCfgRescale = v;
    notifyListeners();
  }

  /// 设置默认 noise_schedule
  Future<void> setDefaultNoiseSchedule(String s) async {
    await _manageSettings.setDefaultNoiseSchedule(s);
    _defaultNoiseSchedule = s;
    notifyListeners();
  }

  /// 设置默认画风词
  Future<void> setDefaultStyleWords(String v) async {
    await _manageSettings.setDefaultStyleWords(v);
    _defaultStyleWords = v;
    notifyListeners();
  }

  // 图像 API 供应商 — NovelAI
  Future<void> setNovelAiBaseUrl(String value) async {
    await _manageSettings.setImageProviderNovelAiBaseUrl(value);
    _novelAiBaseUrl = value;
    notifyListeners();
  }

  Future<void> setNovelAiApiKey(String value) async {
    await _manageSettings.setImageProviderNovelAiApiKey(value);
    _novelAiApiKey = value;
    notifyListeners();
  }

  Future<void> setNovelAiModel(String value) async {
    await _manageSettings.setImageProviderNovelAiModel(value);
    _novelAiModel = value;
    notifyListeners();
  }

  // 图像 API 供应商 — GPT
  Future<void> setGptBaseUrl(String value) async {
    await _manageSettings.setImageProviderGptBaseUrl(value);
    _gptBaseUrl = value;
    notifyListeners();
  }

  Future<void> setGptApiKey(String value) async {
    await _manageSettings.setImageProviderGptApiKey(value);
    _gptApiKey = value;
    notifyListeners();
  }

  Future<void> setGptModel(String value) async {
    await _manageSettings.setImageProviderGptModel(value);
    _gptModel = value;
    notifyListeners();
  }

  // 图像 API 供应商 — Nano Banana
  Future<void> setNanoBaseUrl(String value) async {
    await _manageSettings.setImageProviderNanoBaseUrl(value);
    _nanoBaseUrl = value;
    notifyListeners();
  }

  Future<void> setNanoApiKey(String value) async {
    await _manageSettings.setImageProviderNanoApiKey(value);
    _nanoApiKey = value;
    notifyListeners();
  }

  Future<void> setNanoModel(String value) async {
    await _manageSettings.setImageProviderNanoModel(value);
    _nanoModel = value;
    notifyListeners();
  }

  /// 测试连接
  Future<void> testConnection() async {
    _isTesting = true;
    _connectionResult = null;
    errorMessage = null;
    notifyListeners();

    try {
      _connectionResult = await _manageSettings.testConnection();
    } catch (e) {
      _connectionResult = false;
      errorMessage = '连接测试失败: $e';
    }

    _isTesting = false;
    notifyListeners();
  }
}
