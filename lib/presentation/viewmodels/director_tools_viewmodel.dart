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
  String prompt = '';
  int defry = 5;
  int level = 1;
  bool isProcessing = false;
  bool isLoadingModels = false;
  List<String> availableModels = const [];
  String? selectedModel;
  String? errorMessage;
  ApiEndpoint? _endpoint;

  Future<void> load() async {
    isLoadingModels = true;
    errorMessage = null;
    notifyListeners();
    try {
      final endpoints = await _settings.getEndpoints(ImageProviderType.novelAi);
      _endpoint = endpoints
          .where((endpoint) =>
              endpoint.id == AppConstants.novelAiImageGenerationsEndpointId)
          .firstOrNull;
      final endpoint = _endpoint;
      if (endpoint == null || endpoint.baseUrl.trim().isEmpty) {
        availableModels = const [];
        selectedModel = null;
        errorMessage = '请先在 API 配置中配置 ikun 渠道';
        return;
      }

      final seen = <String>{};
      availableModels =
          endpoint.models.map((model) => model.trim()).where((model) {
        final lower = model.toLowerCase();
        return model.isNotEmpty &&
            !lower.endsWith('-limit') &&
            !lower.contains('inpaint') &&
            seen.add(model);
      }).toList();
      final activeModel =
          await _settings.getActiveModel(ImageProviderType.novelAi);
      selectedModel = availableModels.contains(activeModel)
          ? activeModel
          : availableModels.firstOrNull;
      if (selectedModel == null) {
        errorMessage = 'ikun 渠道没有可用于导演工具的模型';
      }
    } catch (e) {
      availableModels = const [];
      selectedModel = null;
      errorMessage = '加载 ikun 模型失败：$e';
    } finally {
      isLoadingModels = false;
      notifyListeners();
    }
  }

  void selectModel(String? model) {
    if (model == null || !availableModels.contains(model)) return;
    selectedModel = model;
    outputPath = null;
    errorMessage = null;
    notifyListeners();
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
    defry = value.clamp(0, 10);
    notifyListeners();
  }

  void updateLevel(int value) {
    level = value.clamp(1, 5);
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
      errorMessage = '请先在 API 配置中配置 ikun 渠道';
      notifyListeners();
      return false;
    }
    if (model == null || model.isEmpty) {
      errorMessage = '请选择 ikun NovelAI 模型';
      notifyListeners();
      return false;
    }

    isProcessing = true;
    errorMessage = null;
    notifyListeners();
    try {
      final bytes = await _api.processDirectorImage(
        imagePath: source,
        endpointPath: selectedTool.endpoint,
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: model,
        prompt: selectedTool.usesPrompt ? prompt : null,
        defry: selectedTool.usesDefry ? defry : null,
        level: selectedTool.usesLevel ? level : null,
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
