import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/director_tool.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/novelai_connection.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';

class DirectorToolsViewModel extends ChangeNotifier {
  final NovelAiApiService _api;
  final OfficialNovelAiApiService _officialApi;
  final OfficialNovelAiTokenStore _officialTokenStore;
  final ManageSettingsUseCase _settings;
  final SaveImageUseCase _saveImage;
  final AppUpdateInstallGuard? _updateGuard;

  DirectorToolsViewModel(
    this._api,
    this._officialApi,
    this._officialTokenStore,
    this._settings,
    this._saveImage, {
    AppUpdateInstallGuard? updateGuard,
  }) : _updateGuard = updateGuard;

  String? inputPath;
  String? outputPath;
  DirectorToolType selectedTool = DirectorToolType.declutter;
  DirectorChannel selectedChannel = DirectorChannel.gateway7877;
  String prompt = '';
  int defry = 5;
  bool isProcessing = false;
  bool isLoading = false;
  String? selectedModel;
  String? errorMessage;
  ApiEndpoint? _endpoint7877;
  ApiEndpoint? _endpointIkun;
  ApiEndpoint? _endpointOfficial;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String get channelName => switch (selectedChannel) {
        DirectorChannel.gateway7877 => '7877',
        DirectorChannel.ikun => 'ikun',
        DirectorChannel.official =>
          NovelAiConnection.isCustomBaseUrl(_endpointOfficial?.baseUrl ?? '')
              ? 'NovelAI 自定义渠道'
              : 'NovelAI 官方',
      };

  bool get _usesOfficial => selectedChannel == DirectorChannel.official;

  ApiEndpoint? get _endpoint => switch (selectedChannel) {
        DirectorChannel.gateway7877 => _endpoint7877,
        DirectorChannel.ikun => _endpointIkun,
        DirectorChannel.official => _endpointOfficial,
      };

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    _notify();
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
      _endpointOfficial = endpoints
          .where((endpoint) =>
              endpoint.id == AppConstants.novelAiOfficialEndpointId)
          .firstOrNull;

      final activeId =
          await _settings.getActiveEndpointId(ImageProviderType.novelAi);
      selectedChannel = activeId == AppConstants.novelAiOfficialEndpointId
          ? DirectorChannel.official
          : activeId == AppConstants.novelAiImageGenerationsEndpointId
              ? DirectorChannel.ikun
              : DirectorChannel.gateway7877;
      selectedModel = await _settings.getActiveModel(ImageProviderType.novelAi);
      _validateChannel();
    } catch (e) {
      selectedModel = null;
      errorMessage = '加载渠道失败：$e';
    } finally {
      isLoading = false;
      _notify();
    }
  }

  void _validateChannel() {
    final endpoint = _endpoint;
    if (endpoint == null ||
        (!_usesOfficial && endpoint.baseUrl.trim().isEmpty)) {
      errorMessage = '请先在 API 配置中配置 $channelName 渠道';
    } else if (!_usesOfficial &&
        (selectedModel == null || selectedModel!.trim().isEmpty)) {
      errorMessage = '请先在生成页选择 NovelAI 模型';
    } else {
      errorMessage = null;
    }
  }

  Future<void> selectChannel(DirectorChannel channel) async {
    if (isProcessing || isLoading || channel == selectedChannel) return;
    selectedChannel = channel;
    outputPath = null;
    _validateChannel();
    _notify();
  }

  void selectInput(String path) {
    if (isProcessing) return;
    inputPath = path;
    outputPath = null;
    errorMessage = null;
    _notify();
  }

  void selectTool(DirectorToolType tool) {
    if (isProcessing) return;
    selectedTool = tool;
    outputPath = null;
    errorMessage = null;
    _notify();
  }

  void updatePrompt(String value) => prompt = value;

  void updateDefry(int value) {
    defry = value.clamp(0, 5);
    _notify();
  }

  Future<bool> process() async {
    if (_updateGuard?.isInstalling ?? false) {
      errorMessage = '正在安装更新，请稍后重试';
      _notify();
      return false;
    }
    final finish = _updateGuard?.beginActivity('导演工具处理尚未完成');
    try {
      return await _processBeforeUpdate();
    } finally {
      finish?.call();
    }
  }

  Future<bool> _processBeforeUpdate() async {
    if (isProcessing || isLoading || _disposed) return false;
    final source = inputPath;
    if (source == null) {
      errorMessage = '请先选择图片';
      _notify();
      return false;
    }
    final endpoint = _endpoint;
    if (endpoint == null ||
        (!_usesOfficial && endpoint.baseUrl.trim().isEmpty)) {
      errorMessage = '请先在 API 配置中配置 $channelName 渠道';
      _notify();
      return false;
    }
    isProcessing = true;
    errorMessage = null;
    _notify();
    try {
      // The generation page owns the model; channel changes never overwrite it.
      selectedModel = await _settings.getActiveModel(ImageProviderType.novelAi);
      final model = selectedModel;
      if (!_usesOfficial && (model == null || model.trim().isEmpty)) {
        errorMessage = '请先在生成页选择 NovelAI 模型';
        return false;
      }
      if (_disposed) return false;
      final bytes = _usesOfficial
          ? await _officialApi.forBaseUrl(endpoint.baseUrl).augmentImage(
                imagePath: source,
                tool: selectedTool,
                token: await _requireOfficialToken(),
                prompt: selectedTool.usesPrompt ? prompt : null,
                defry: selectedTool.usesDefry ? defry : null,
              )
          : selectedChannel == DirectorChannel.gateway7877
              ? await _api.processDirectorImage(
                  imagePath: source,
                  operation: selectedTool.operation,
                  model: model!,
                  apiKey: endpoint.apiKey,
                  baseUrl: endpoint.baseUrl,
                  prompt: selectedTool.usesPrompt ? prompt : null,
                  defry: selectedTool.usesDefry ? defry : null,
                )
              : await _api.processDirectorImageIkun(
                  imagePath: source,
                  operation: selectedTool.operation,
                  model: model!,
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
      _notify();
    }
  }

  Future<String> _requireOfficialToken() async {
    final baseUrl = _endpointOfficial?.baseUrl ?? '';
    final token = await _officialTokenStore.readForBaseUrl(baseUrl);
    if (token == null || token.trim().isEmpty) {
      throw AppException(
          message: NovelAiConnection.isCustomBaseUrl(baseUrl)
              ? '请先在 API 配置中填写此自定义渠道的 API Key'
              : '请先在 API 配置中填写 NovelAI 官方 Token');
    }
    return token;
  }

  Future<bool> saveToGallery() async {
    final path = outputPath;
    if (path == null) return false;
    try {
      return await _saveImage.saveToGallery(path);
    } catch (e) {
      errorMessage = '保存失败：$e';
      _notify();
      return false;
    }
  }
}
