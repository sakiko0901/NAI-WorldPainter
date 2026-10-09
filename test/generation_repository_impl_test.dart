import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/gpt_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/nano_banana_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/repositories/generation_repository_impl.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/domain/repositories/vibe_encoding_repository.dart';

const _ikunEndpoint = ApiEndpoint(
  id: AppConstants.novelAiImageGenerationsEndpointId,
  name: 'ikun',
  baseUrl: 'https://ikun.example',
  apiKey: 'ikun-key',
  models: ['model'],
  protocol: AppConstants.novelAiImageGenerationsProtocol,
);

void main() {
  test(
      'NovelAI task resolves credentials by endpointId instead of active endpoint',
      () async {
    final service = _RecordingNovelAiService();
    final settings = _FakeSettingsRepository(
      endpoints: const [
        ApiEndpoint(
          id: 'selected',
          name: 'Selected',
          baseUrl: 'https://selected.example',
          apiKey: 'selected-key',
          models: ['model'],
        ),
        ApiEndpoint(
          id: 'active',
          name: 'Active',
          baseUrl: 'https://active.example',
          apiKey: 'active-key',
          models: ['model'],
        ),
      ],
      activeId: 'active',
    );
    final repository = GenerationRepositoryImpl(
      apiService: service,
      officialApiService: OfficialNovelAiApiService(Dio()),
      officialTokenStore: OfficialNovelAiTokenStore(),
      gptApiService: GptApiService(Dio()),
      nanoApiService: NanoBananaApiService(Dio()),
      settingsRepo: settings,
      vibeEncodingRepo: _FakeVibeEncodingRepository(),
    );

    await repository.submitGeneration(_task(endpointId: 'selected'));

    expect(service.apiKey, 'selected-key');
    expect(service.baseUrl, 'https://selected.example');
  });

  test('ikun task restores library Vibe encoding before submit', () async {
    final service = _RecordingNovelAiService();
    final repository = GenerationRepositoryImpl(
      apiService: service,
      officialApiService: OfficialNovelAiApiService(Dio()),
      officialTokenStore: OfficialNovelAiTokenStore(),
      gptApiService: GptApiService(Dio()),
      nanoApiService: NanoBananaApiService(Dio()),
      settingsRepo: _FakeSettingsRepository(
        endpoints: const [],
        activeId: '',
      ),
      vibeEncodingRepo: _FakeVibeEncodingRepository(
        saved: VibeEncoding(
          id: 7,
          title: 'saved vibe',
          thumbnailPath: 'thumb.jpg',
          sourceImagePath: 'source.png',
          encodedVibe: 'encoded-vibe',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
    );

    await repository.submitGeneration(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        vibeReferences: const [
          CharacterReferenceImage(path: '', vibeLibraryId: 7),
        ],
      ),
    );

    final reference = service.task!.vibeReferences.single;
    expect(reference.encodedVibe, 'encoded-vibe');
    expect(reference.thumbnailPath, 'thumb.jpg');
    expect(reference.title, 'saved vibe');
  });

  test('ikun raw Vibe is passed to gateway without 7877 pre-encoding',
      () async {
    final service = _RecordingNovelAiService();
    final repository = GenerationRepositoryImpl(
      apiService: service,
      officialApiService: OfficialNovelAiApiService(Dio()),
      officialTokenStore: OfficialNovelAiTokenStore(),
      gptApiService: GptApiService(Dio()),
      nanoApiService: NanoBananaApiService(Dio()),
      settingsRepo: _FakeSettingsRepository(
        endpoints: const [_ikunEndpoint],
        activeId: AppConstants.novelAiImageGenerationsEndpointId,
      ),
      vibeEncodingRepo: _FakeVibeEncodingRepository(),
    );

    await repository.submitGeneration(
      _task(
        endpointId: AppConstants.novelAiImageGenerationsEndpointId,
        protocol: AppConstants.novelAiChatCompletionsProtocol,
        vibeReferences: const [CharacterReferenceImage(path: 'vibe.png')],
      ),
    );

    expect(service.task!.vibeReferences.single.path, 'vibe.png');
    expect(service.task!.vibeReferences.single.encodedVibe, isNull);
  });

  test('ikun rejects img2img with Vibe instead of dropping the reference',
      () async {
    final repository = GenerationRepositoryImpl(
      apiService: _RecordingNovelAiService(),
      officialApiService: OfficialNovelAiApiService(Dio()),
      officialTokenStore: OfficialNovelAiTokenStore(),
      gptApiService: GptApiService(Dio()),
      nanoApiService: NanoBananaApiService(Dio()),
      settingsRepo: _FakeSettingsRepository(
        endpoints: const [_ikunEndpoint],
        activeId: AppConstants.novelAiImageGenerationsEndpointId,
      ),
      vibeEncodingRepo: _FakeVibeEncodingRepository(),
    );

    expect(
      () => repository.submitGeneration(
        _task(
          endpointId: AppConstants.novelAiImageGenerationsEndpointId,
          protocol: AppConstants.novelAiChatCompletionsProtocol,
          img2imgSourceImagePath: 'source.png',
          vibeReferences: const [CharacterReferenceImage(path: 'vibe.png')],
        ),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'VIBE_IMG2IMG_UNSUPPORTED_IKUN',
        ),
      ),
    );
  });
}

GenerationTask _task({
  String? endpointId,
  String protocol = AppConstants.novelAiChatCompletionsProtocol,
  List<CharacterReferenceImage> vibeReferences = const [],
  String? img2imgSourceImagePath,
}) =>
    GenerationTask(
      taskId: 'task',
      endpointId: endpointId,
      protocol: protocol,
      model: 'model',
      prompt: '1girl',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      status: 'pending',
      createdAt: DateTime(2026),
      vibeReferences: vibeReferences,
      img2imgSourceImagePath: img2imgSourceImagePath,
    );

class _RecordingNovelAiService extends NovelAiApiService {
  _RecordingNovelAiService() : super(Dio());

  String? apiKey;
  String? baseUrl;
  GenerationTask? task;

  @override
  Future<GenerationTask> generateImage(
    GenerationTask task,
    String apiKey,
    String baseUrl,
  ) async {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
    this.task = task;
    return task;
  }
}

class _FakeVibeEncodingRepository implements VibeEncodingRepository {
  final VibeEncoding? saved;

  _FakeVibeEncodingRepository({this.saved});

  @override
  Future<VibeEncoding?> getById(int id) async => saved?.id == id ? saved : null;

  @override
  Future<VibeEncoding?> findBySourceImagePath(String path) async =>
      saved?.sourceImagePath == path ? saved : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepository implements SettingsRepository {
  final List<ApiEndpoint> endpoints;
  final String activeId;

  _FakeSettingsRepository({required this.endpoints, required this.activeId});

  @override
  Future<List<ApiEndpoint>> getEndpoints(ImageProviderType p) async =>
      endpoints;

  @override
  Future<ApiEndpoint?> getActiveEndpoint(ImageProviderType p) async =>
      endpoints.where((endpoint) => endpoint.id == activeId).firstOrNull;

  @override
  Future<String> getImageProviderNovelAiBaseUrl() async =>
      'https://novelai.test';

  @override
  Future<String?> getImageProviderNovelAiApiKey() async => 'novelai-key';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
