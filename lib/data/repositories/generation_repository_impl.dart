import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/gpt_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/nano_banana_api_service.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';

class GenerationRepositoryImpl implements GenerationRepository {
  final NovelAiApiService _apiService;
  final GptApiService _gptApiService;
  final NanoBananaApiService _nanoApiService;
  final SettingsRepository _settingsRepo;

  GenerationRepositoryImpl({
    required NovelAiApiService apiService,
    required GptApiService gptApiService,
    required NanoBananaApiService nanoApiService,
    required SettingsRepository settingsRepo,
  })  : _apiService = apiService,
        _gptApiService = gptApiService,
        _nanoApiService = nanoApiService,
        _settingsRepo = settingsRepo;

  @override
  Future<GenerationTask> submitGeneration(GenerationTask task) async {
    switch (task.providerType) {
      case ImageProviderType.gpt:
        return _submitGpt(task);
      case ImageProviderType.nanoBanana:
        return _submitNano(task);
      case ImageProviderType.novelAi:
        return _submitNovelAi(task);
    }
  }

  /// 取某 provider 的当前有效 (apiKey, baseUrl)：先看 v2 active endpoint，再回退 v1 单值
  Future<({String apiKey, String baseUrl})> _resolveCreds(
      ImageProviderType p) async {
    final ep = await _settingsRepo.getActiveEndpoint(p);
    if (ep != null && ep.baseUrl.isNotEmpty) {
      return (apiKey: ep.apiKey, baseUrl: ep.baseUrl);
    }
    String legacyUrl;
    String? legacyKey;
    switch (p) {
      case ImageProviderType.novelAi:
        legacyUrl = await _settingsRepo.getImageProviderNovelAiBaseUrl();
        legacyKey = await _settingsRepo.getImageProviderNovelAiApiKey();
        break;
      case ImageProviderType.gpt:
        legacyUrl = await _settingsRepo.getImageProviderGptBaseUrl();
        legacyKey = await _settingsRepo.getImageProviderGptApiKey();
        break;
      case ImageProviderType.nanoBanana:
        legacyUrl = await _settingsRepo.getImageProviderNanoBaseUrl();
        legacyKey = await _settingsRepo.getImageProviderNanoApiKey();
        break;
    }
    return (apiKey: legacyKey ?? '', baseUrl: legacyUrl);
  }

  Future<({String apiKey, String baseUrl})> _resolveNovelAiCreds(
      String? endpointId) async {
    if (endpointId != null) {
      final endpoints =
          await _settingsRepo.getEndpoints(ImageProviderType.novelAi);
      final endpoint = endpoints.where((ep) => ep.id == endpointId).firstOrNull;
      if (endpoint != null) {
        return (apiKey: endpoint.apiKey, baseUrl: endpoint.baseUrl);
      }
      return (apiKey: '', baseUrl: '');
    }
    return _resolveCreds(ImageProviderType.novelAi);
  }

  Future<GenerationTask> _submitNovelAi(GenerationTask task) async {
    final creds = await _resolveNovelAiCreds(task.endpointId);
    if (creds.apiKey.isEmpty) {
      throw ApiException(
          message: '请先在设置中配置 NovelAI API Key', code: 'NO_API_KEY');
    }
    if (creds.baseUrl.isEmpty) {
      throw ApiException(
          message: '请先在设置中配置 NovelAI Base URL', code: 'NO_BASE_URL');
    }

    if (task.mode == GenerationMode.inpainting) {
      return _apiService.inpaintImage(task, creds.apiKey, creds.baseUrl);
    }
    return _apiService.generateImage(task, creds.apiKey, creds.baseUrl);
  }

  Future<GenerationTask> _submitGpt(GenerationTask task) async {
    final creds = await _resolveCreds(ImageProviderType.gpt);
    if (creds.apiKey.isEmpty) {
      throw ApiException(message: '请先在设置中配置 GPT API Key', code: 'NO_API_KEY');
    }
    if (creds.baseUrl.isEmpty) {
      throw ApiException(message: '请先在设置中配置 GPT Base URL', code: 'NO_BASE_URL');
    }

    if (task.mode == GenerationMode.inpainting) {
      return _gptApiService.editImage(task, creds.apiKey, creds.baseUrl);
    }
    // 文生图有参考图时走 edits 接口
    if (task.gptImagePaths != null && task.gptImagePaths!.isNotEmpty) {
      return _gptApiService.editImage(task, creds.apiKey, creds.baseUrl);
    }
    return _gptApiService.generateImage(task, creds.apiKey, creds.baseUrl);
  }

  Future<GenerationTask> _submitNano(GenerationTask task) async {
    final creds = await _resolveCreds(ImageProviderType.nanoBanana);
    if (creds.apiKey.isEmpty) {
      throw ApiException(
          message: '请先在设置中配置 Nano Banana API Key', code: 'NO_API_KEY');
    }
    if (creds.baseUrl.isEmpty) {
      throw ApiException(
          message: '请先在设置中配置 Nano Banana Base URL', code: 'NO_BASE_URL');
    }

    if (task.gptImagePaths != null && task.gptImagePaths!.isNotEmpty) {
      return _nanoApiService.editImage(task, creds.apiKey, creds.baseUrl);
    }
    if (task.sourceImagePath != null && task.sourceImagePath!.isNotEmpty) {
      return _nanoApiService.editImage(task, creds.apiKey, creds.baseUrl);
    }
    return _nanoApiService.generateImage(task, creds.apiKey, creds.baseUrl);
  }

  @override
  Future<List<NaiModel>> fetchModels() async {
    final creds = await _resolveCreds(ImageProviderType.novelAi);
    if (creds.apiKey.isEmpty) {
      throw ApiException(
          message: '请先在设置中配置 NovelAI API Key', code: 'NO_API_KEY');
    }
    if (creds.baseUrl.isEmpty) {
      throw ApiException(
          message: '请先在设置中配置 NovelAI Base URL', code: 'NO_BASE_URL');
    }
    return _apiService.fetchModels(creds.apiKey, creds.baseUrl);
  }

  @override
  Future<void> cancelTask(String taskId) async {
    // 队列中的任务通过 GenerationQueue.cancel 取消
  }
}
