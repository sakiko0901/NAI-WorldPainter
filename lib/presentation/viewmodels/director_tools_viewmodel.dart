import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/director_tool.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';

class DirectorToolsViewModel extends ChangeNotifier {
  final NovelAiApiService _api;
  final ManageSettingsUseCase _settings;
  final SaveImageUseCase _saveImage;

  DirectorToolsViewModel(this._api, this._settings, this._saveImage);

  String? inputPath;
  String? outputPath;
  DirectorToolType selectedTool = DirectorToolType.declutter;
  DirectorChannel selectedChannel = DirectorChannel.gateway7877;
  String prompt = '';
  int defry = 5;
  bool isProcessing = false;
  bool isLoadingModels = false;
  List<String> availableModels = const [];
  String? selectedModel;
  String? errorMessage;
  ApiEndpoint? _endpoint7877;
  ApiEndpoint? _endpointIkun;
  List<String> _models7877 = const [];
  List<String> _modelsIkun = const [];
  String? _model7877;
  String? _modelIkun;

  String get channelName =>
      selectedChannel == DirectorChannel.gateway7877 ? '7877' : 'ikun';

  ApiEndpoint? get _endpoint => selectedChannel == DirectorChannel.gateway7877
      ? _endpoint7877
      : _endpointIkun;

  Future<void> load() async {
    isLoadingModels = true;
    errorMessage = null;
    notifyListeners();
    try {
      final endpoints = await _settings.getEndpoints(ImageProviderType.novelAi);
      _endpoint7877 = endpoints
          .where((endpoint) =>
              endpoint.id == AppConstants.novelAiChatCompletionsEndpointId)
          .firstOrNull;
      _endpointIkun = endpoints
          .where((endpoint) =>
              endpoint.id == AppConstants.novelAiImageGenerationsEndpointId)
          .firstOrNull;
      _models7877 = _availableModels(_endpoint7877);
      _modelsIkun = _availableModels(_endpointIkun);

      final activeId =
          await _settings.getActiveEndpointId(ImageProviderType.novelAi);
      selectedChannel =
          activeId == AppConstants.novelAiImageGenerationsEndpointId
              ? DirectorChannel.ikun
              : DirectorChannel.gateway7877;
      final activeModel =
          await _settings.getActiveModel(ImageProviderType.novelAi);
      _model7877 = _models7877.firstOrNull;
      _modelIkun = _modelsIkun.firstOrNull;
      if (selectedChannel == DirectorChannel.gateway7877 &&
          _models7877.contains(activeModel)) {
        _model7877 = activeModel;
      }
      if (selectedChannel == DirectorChannel.ikun &&
          _modelsIkun.contains(activeModel)) {
        _modelIkun = activeModel;
      }
      _syncSelectedModel();
    } catch (e) {
      availableModels = const [];
      selectedModel = null;
      errorMessage = '加载 $channelName 模型失败：$e';
    } finally {
      isLoadingModels = false;
      notifyListeners();
    }
  }

  List<String> _availableModels(ApiEndpoint? endpoint) {
    if (endpoint == null) return const [];
    final seen = <String>{};
    return endpoint.models.map((model) => model.trim()).where((model) {
      final lower = model.toLowerCase();
      return model.isNotEmpty &&
          !lower.endsWith('-limit') &&
          !lower.contains('inpaint') &&
          seen.add(model);
    }).toList();
  }

  void _syncSelectedModel() {
    if (selectedChannel == DirectorChannel.gateway7877) {
      availableModels = _models7877;
      selectedModel = _model7877;
    } else {
      availableModels = _modelsIkun;
      selectedModel = _modelIkun;
    }
    final endpoint = _endpoint;
    if (endpoint == null || endpoint.baseUrl.trim().isEmpty) {
      errorMessage = '请先在 API 配置中配置 $channelName 渠道';
    } else if (selectedModel == null) {
      errorMessage = '$channelName 渠道没有可用于导演工具的模型';
    } else {
      errorMessage = null;
    }
  }

  Future<void> selectChannel(DirectorChannel channel) async {
    if (channel == selectedChannel) return;
    selectedChannel = channel;
    outputPath = null;
    _syncSelectedModel();
    notifyListeners();

    final endpoint = _endpoint;
    if (endpoint == null) return;
    await _settings.setActiveEndpointId(ImageProviderType.novelAi, endpoint.id);
    await _settings.setActiveModel(ImageProviderType.novelAi, selectedModel);
  }

  Future<void> selectModel(String? model) async {
    if (model == null || !availableModels.contains(model)) return;
    if (selectedChannel == DirectorChannel.gateway7877) {
      _model7877 = model;
    } else {
      _modelIkun = model;
    }
    selectedModel = model;
    outputPath = null;
    errorMessage = null;
    notifyListeners();
    await _settings.setActiveModel(ImageProviderType.novelAi, model);
  }

  void selectInput(String path) {
    inputPath = path;
    outputPath = null;
    errorMessage = null;
    notifyListeners();
  }

  void selectTool(DirectorToolType tool) {
    selectedTool = tool;
    outputPath = null;
    errorMessage = null;
    notifyListeners();
  }

  void updatePrompt(String value) => prompt = value;

  void updateDefry(int value) {
    defry = value.clamp(0, 5);
    notifyListeners();
  }

  Future<bool> process() async {
    final source = inputPath;
    if (source == null) {
      errorMessage = '请先选择图片';
      notifyListeners();
      return false;
    }
    final endpoint = _endpoint;
    final model = selectedModel;
    if (endpoint == null || endpoint.baseUrl.trim().isEmpty) {
      errorMessage = '请先在 API 配置中配置 $channelName 渠道';
      notifyListeners();
      return false;
    }
    if (model == null || model.isEmpty) {
      errorMessage = '请选择 $channelName NovelAI 模型';
      notifyListeners();
      return false;
    }

    isProcessing = true;
    errorMessage = null;
    notifyListeners();
    try {
      final bytes = selectedChannel == DirectorChannel.gateway7877
          ? await _api.processDirectorImage(
              imagePath: source,
              operation: selectedTool.operation,
              model: model,
              apiKey: endpoint.apiKey,
              baseUrl: endpoint.baseUrl,
              prompt: selectedTool.usesPrompt ? prompt : null,
              defry: selectedTool.usesDefry ? defry : null,
            )
          : await _api.processDirectorImageIkun(
              imagePath: source,
              operation: selectedTool.operation,
              model: model,
              apiKey: endpoint.apiKey,
              baseUrl: endpoint.baseUrl,
              prompt: selectedTool.usesPrompt ? prompt : null,
              defry: selectedTool.usesDefry ? defry : null,
            );
      outputPath = await ImageUtils.saveBase64Image(
        base64Encode(bytes),
        ImageUtils.generateFilename(),
      );
      return true;
    } catch (e) {
      errorMessage = '处理失败：${e is AppException ? e.message : e}';
      return false;
    } finally {
      isProcessing = false;
      notifyListeners();
    }
  }

  Future<bool> saveToGallery() async {
    final path = outputPath;
    if (path == null) return false;
    try {
      return await _saveImage.saveToGallery(path);
    } catch (e) {
      errorMessage = '保存失败：$e';
      notifyListeners();
      return false;
    }
  }
}
