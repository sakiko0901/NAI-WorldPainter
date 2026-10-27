import 'dart:typed_data';

import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/nai_model.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/domain/entities/novelai_route.dart';
import 'package:nai_huishi/domain/entities/novelai_connection.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/remote/gpt_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/nano_banana_api_service.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/domain/repositories/vibe_encoding_repository.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';

class GenerationRepositoryImpl implements GenerationRepository {
  final NovelAiApiService _apiService;
  final OfficialNovelAiApiService _officialApiService;
  final OfficialNovelAiTokenStore _officialTokenStore;
  final GptApiService _gptApiService;
  final NanoBananaApiService _nanoApiService;
  final SettingsRepository _settingsRepo;
  final VibeEncodingRepository _vibeEncodingRepo;

  /// 流式预览回调（taskId → handler），任务完成后移除。
  final Map<String, void Function(Uint8List bytes, int? step)> _streamHandlers =
      {};

  GenerationRepositoryImpl({
    required NovelAiApiService apiService,
    required OfficialNovelAiApiService officialApiService,
    required OfficialNovelAiTokenStore officialTokenStore,
    required GptApiService gptApiService,
    required NanoBananaApiService nanoApiService,
    required SettingsRepository settingsRepo,
    required VibeEncodingRepository vibeEncodingRepo,
  })  : _apiService = apiService,
        _officialApiService = officialApiService,
        _officialTokenStore = officialTokenStore,
        _gptApiService = gptApiService,
        _nanoApiService = nanoApiService,
        _settingsRepo = settingsRepo,
        _vibeEncodingRepo = vibeEncodingRepo;

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

  @override
  void setStreamPreviewHandler(
      String taskId, void Function(Uint8List bytes, int? step)? onFrame) {
    if (onFrame == null) {
      _streamHandlers.remove(taskId);
    } else {
      _streamHandlers[taskId] = onFrame;
    }
  }

  Future<GenerationTask> _submitNovelAi(GenerationTask task) async {
    final route = NovelAiRoute.fromIds(task.endpointId, task.protocol);
    if (route.isOfficial) {
      final endpoints =
          await _settingsRepo.getEndpoints(ImageProviderType.novelAi);
      final endpoint = endpoints
          .where((ep) =>
              ep.id ==
              (task.endpointId ?? AppConstants.novelAiOfficialEndpointId))
          .firstOrNull;
      final baseUrl = endpoint?.baseUrl ?? '';
      final isCustom = NovelAiConnection.isCustomBaseUrl(baseUrl);
      final api = _officialApiService.forBaseUrl(baseUrl);
      final token = await _officialTokenStore.readForBaseUrl(baseUrl);
      if (token == null || token.trim().isEmpty) {
        throw ApiException(
          message: isCustom
              ? '请先在 API 配置中填写此自定义渠道的 API Key'
              : '请先在 API 配置中填写 NovelAI 官方 Token',
          code: 'NO_OFFICIAL_TOKEN',
        );
      }
      final prepared = await _prepareOfficialVibeReferences(task, token, api);
      final handler = _streamHandlers.remove(task.taskId);
      final hasPrecise = prepared.preciseReferences.isNotEmpty;
      // Older official configurations streamed by default. Relays opt in, since
      // many only implement the regular endpoint. Multipart references require
      // the regular endpoint regardless of the preference.
      final canStream = !hasPrecise && (endpoint?.streamEnabled ?? !isCustom);
      if (canStream) {
        return api.generateImageStream(
          prepared,
          token,
          onFrame: handler,
        );
      }
      return api.generateImage(prepared, token);
    }

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
    if (route.isIkun &&
        task.img2imgSourceImagePath != null &&
        task.vibeReferences.isNotEmpty) {
      throw ApiException(
        message: 'ikun 暂不支持图生图与 Vibe 编码同时使用，请先移除其中一种参考',
        code: 'VIBE_IMG2IMG_UNSUPPORTED_IKUN',
      );
    }
    final prepared = await _prepareVibeReferences(
      task,
      creds.apiKey,
      creds.baseUrl,
      route,
    );
    return _apiService.generateImage(prepared, creds.apiKey, creds.baseUrl);
  }

  Future<GenerationTask> _prepareVibeReferences(
    GenerationTask task,
    String apiKey,
    String baseUrl,
    NovelAiRoute route,
  ) async {
    if (task.vibeReferences.isEmpty) return task;

    final prepared = <CharacterReferenceImage>[];
    for (final reference in task.vibeReferences) {
      if (reference.encodedVibe?.isNotEmpty == true) {
        prepared.add(reference);
        continue;
      }

      VibeEncoding? saved;
      if (reference.vibeLibraryId != null) {
        saved = await _vibeEncodingRepo.getById(reference.vibeLibraryId!);
        if (saved == null) {
          throw ApiException(message: '已保存的氛围编码不存在，请重新选择');
        }
      } else if (reference.path.isNotEmpty) {
        saved = await _vibeEncodingRepo.findBySourceImagePath(reference.path);
      }

      if (saved != null) {
        prepared.add(reference.copyWith(
          vibeLibraryId: saved.id,
          encodedVibe: saved.encodedVibe,
          thumbnailPath: saved.thumbnailPath,
          title: saved.title,
        ));
        continue;
      }

      if (reference.path.isEmpty) {
        throw ApiException(message: '氛围参考图像不可用，请重新选择');
      }
      if (route.isIkun) {
        prepared.add(reference);
        continue;
      }
      final encoded = await _apiService.encode7877VibeReference(
        task: task,
        reference: reference,
        apiKey: apiKey,
        baseUrl: baseUrl,
      );
      final created = await _vibeEncodingRepo.createFromEncoding(
        title: _vibeTitleForPath(reference.path),
        encodedVibe: encoded,
        sourceImagePath: reference.path,
        encodedModel: task.model,
      );
      prepared.add(reference.copyWith(
        vibeLibraryId: created.id,
        encodedVibe: encoded,
        thumbnailPath: created.thumbnailPath,
        title: created.title,
      ));
    }
    return task.copyWith(vibeReferences: prepared);
  }

  Future<GenerationTask> _prepareOfficialVibeReferences(
    GenerationTask task,
    String token,
    OfficialNovelAiApiService api,
  ) async {
    if (task.vibeReferences.isEmpty) return task;
    final prepared = <CharacterReferenceImage>[];
    for (final reference in task.vibeReferences) {
      if (reference.path.isEmpty) {
        throw ApiException(message: '氛围参考图像不可用，请重新选择');
      }
      final encoded = await api.encodeVibeReference(
        imagePath: reference.path,
        model: task.model,
        informationExtracted: reference.informationExtracted,
        token: token,
      );
      prepared.add(reference.copyWith(encodedVibe: encoded));
    }
    return task.copyWith(vibeReferences: prepared);
  }

  String _vibeTitleForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
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
