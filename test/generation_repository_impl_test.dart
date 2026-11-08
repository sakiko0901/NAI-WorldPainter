import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/data/datasources/remote/gpt_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/nano_banana_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/repositories/generation_repository_impl.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'official Vibe caches content/model/extraction and saves reusable library entries',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final tokens = OfficialNovelAiTokenStore();
    await tokens.write('test-token');
    final api = _EncodingApi();
    final library = _EncodingLibrary();
    final repository = GenerationRepositoryImpl(
        apiService: _RecordingNovelAiService(),
        officialApiService: api,
        officialTokenStore: tokens,
        gptApiService: GptApiService(Dio()),
        nanoApiService: NanoBananaApiService(Dio()),
        settingsRepo:
            _FakeSettingsRepository(endpoints: const [], activeId: ''),
        vibeEncodingRepo: library);
    final dir = await Directory.systemTemp.createTemp('vibe-cache-test');
    addTearDown(() => dir.delete(recursive: true));
    final source = await File('${dir.path}/image.png').writeAsBytes([1, 2, 3]);
    final copy = await source.copy('${dir.path}/copy.png');
    GenerationTask task(String path, double info,
            {String model = 'nai-diffusion-4-5-full'}) =>
        _task(
            endpointId: AppConstants.novelAiOfficialEndpointId,
            protocol: AppConstants.novelAiOfficialProtocol,
            vibeReferences: [
              CharacterReferenceImage(path: path, informationExtracted: info)
            ]).copyWith(model: model);
    await repository.submitGeneration(task(source.path, .7));
    await repository.submitGeneration(task(copy.path, .7));
    expect(api.encodes, 1);
    expect(library.entries, hasLength(1));
    await repository.submitGeneration(task(source.path, .8));
    expect(api.encodes, 2);
    await repository
        .submitGeneration(task(source.path, .7, model: 'nai-diffusion-4-full'));
    expect(api.encodes, 3);
    final saved = library.entries.first;
    await repository.submitGeneration(_task(
        endpointId: AppConstants.novelAiOfficialEndpointId,
        protocol: AppConstants.novelAiOfficialProtocol,
        vibeReferences: [
          CharacterReferenceImage(path: '', vibeLibraryId: saved.id)
        ]).copyWith(model: saved.encodedModel));
    expect(api.encodes, 3, reason: 'imported encoding needs no source image');
  });

  test('official payload maps fidelity to one minus the slider value',
      () async {
    final dir = await Directory.systemTemp.createTemp('precise-payload');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/ref.png')
        .writeAsBytes(img.encodePng(img.Image(width: 4, height: 4)));
    final payload = await OfficialNovelAiApiService(Dio()).buildPayload(_task()
        .copyWith(model: 'nai-diffusion-4-5-full', preciseReferences: [
      PreciseReferenceImage(
          path: file.path, fidelity: .35, referenceType: 'style')
    ]));
    final params = payload['parameters'] as Map;
    expect(
        (params['director_reference_secondary_strength_values'] as List).single,
        closeTo(.65, .00001));
    expect(
        (params['director_reference_descriptions'] as List).single['caption']
            ['base_caption'],
        'style');
  });

  for (final custom in [false, true]) {
    for (final enabled in <bool?>[null, false, true]) {
      test(
          'native streaming preference $enabled for custom=$custom selects one endpoint',
          () async {
        FlutterSecureStorage.setMockInitialValues({});
        final tokens = OfficialNovelAiTokenStore();
        final baseUrl = custom
            ? 'https://relay.example/native'
            : ApiConstants.officialImageBaseUrl;
        await tokens.writeForBaseUrl(baseUrl, 'configured-key');
        final adapter = _CaptureNativeAdapter();
        final repository = GenerationRepositoryImpl(
          apiService: _RecordingNovelAiService(),
          officialApiService: OfficialNovelAiApiService(
              Dio(BaseOptions(baseUrl: ApiConstants.officialImageBaseUrl))
                ..httpClientAdapter = adapter),
          officialTokenStore: tokens,
          gptApiService: GptApiService(Dio()),
          nanoApiService: NanoBananaApiService(Dio()),
          settingsRepo: _FakeSettingsRepository(
            endpoints: [
              ApiEndpoint(
                id: AppConstants.novelAiOfficialEndpointId,
                name: 'NovelAI',
                baseUrl: baseUrl,
                apiKey: '',
                models: const ['nai-diffusion-5-full'],
                protocol: AppConstants.novelAiOfficialProtocol,
                streamEnabled: enabled,
              ),
            ],
            activeId: AppConstants.novelAiOfficialEndpointId,
          ),
          vibeEncodingRepo: _FakeVibeEncodingRepository(),
        );
        await expectLater(
          repository.submitGeneration(_task(
            endpointId: AppConstants.novelAiOfficialEndpointId,
            protocol: AppConstants.novelAiOfficialProtocol,
          ).copyWith(model: 'nai-diffusion-5-full')),
          throwsA(isA<ApiException>()),
        );
        // A stream failure must not submit a second, chargeable generation.
        expect(adapter.requests, hasLength(1));
        final request = adapter.requests.single;
        final stream = enabled ?? !custom;
        expect(request.uri.toString(),
            '$baseUrl${stream ? ApiConstants.officialGenerateImageStream : ApiConstants.officialGenerateImage}');
        expect(request.headers['Authorization'], 'Bearer configured-key');
        final parameters = (request.data as Map)['parameters'] as Map;
        if (stream) {
          expect(parameters['stream'], 'msgpack');
        } else {
          expect(parameters, isNot(contains('stream')));
        }
      });
    }
  }

  test('custom native route uses the saved relay URL and its own API key',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final tokens = OfficialNovelAiTokenStore();
    await tokens.write('official-token');
    await tokens.writeForBaseUrl('https://relay.example/proxy', 'relay-key');
    final adapter = _CaptureNativeAdapter();
    final dio = Dio(BaseOptions(baseUrl: ApiConstants.officialImageBaseUrl))
      ..httpClientAdapter = adapter;
    final repository = GenerationRepositoryImpl(
      apiService: _RecordingNovelAiService(),
      officialApiService: OfficialNovelAiApiService(dio),
      officialTokenStore: tokens,
      gptApiService: GptApiService(Dio()),
      nanoApiService: NanoBananaApiService(Dio()),
      settingsRepo: _FakeSettingsRepository(
        endpoints: const [
          ApiEndpoint(
            id: AppConstants.novelAiOfficialEndpointId,
            name: 'NovelAI 自定义渠道',
            baseUrl: 'https://relay.example/proxy/',
            apiKey: '',
            models: ['model'],
            protocol: AppConstants.novelAiOfficialProtocol,
          ),
        ],
        activeId: AppConstants.novelAiOfficialEndpointId,
      ),
      vibeEncodingRepo: _FakeVibeEncodingRepository(),
    );
    // An intentional mock rejection stops before any file or real generation.
    await expectLater(
      repository.submitGeneration(_task(
        endpointId: AppConstants.novelAiOfficialEndpointId,
        protocol: AppConstants.novelAiOfficialProtocol,
      )),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.uri.toString(),
        'https://relay.example/proxy${ApiConstants.officialGenerateImage}');
    expect(request.headers['Authorization'], 'Bearer relay-key');
    expect(request.followRedirects, isFalse);
    expect(dio.options.baseUrl, ApiConstants.officialImageBaseUrl);
    expect(await tokens.read(), 'official-token');
  });

  test('custom native route never falls back to the official token', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final tokens = OfficialNovelAiTokenStore();
    await tokens.write('official-token');
    final adapter = _CaptureNativeAdapter();
    final repository = GenerationRepositoryImpl(
      apiService: _RecordingNovelAiService(),
      officialApiService:
          OfficialNovelAiApiService(Dio()..httpClientAdapter = adapter),
      officialTokenStore: tokens,
      gptApiService: GptApiService(Dio()),
      nanoApiService: NanoBananaApiService(Dio()),
      settingsRepo: _FakeSettingsRepository(
        endpoints: const [
          ApiEndpoint(
            id: AppConstants.novelAiOfficialEndpointId,
            name: 'relay',
            baseUrl: 'https://new-relay.example',
            apiKey: '',
            models: ['model'],
            protocol: AppConstants.novelAiOfficialProtocol,
          ),
        ],
        activeId: AppConstants.novelAiOfficialEndpointId,
      ),
      vibeEncodingRepo: _FakeVibeEncodingRepository(),
    );
    await expectLater(
      repository.submitGeneration(_task(
        endpointId: AppConstants.novelAiOfficialEndpointId,
        protocol: AppConstants.novelAiOfficialProtocol,
      )),
      throwsA(isA<ApiException>()
          .having((error) => error.message, 'message', contains('自定义渠道'))),
    );
    expect(adapter.requests, isEmpty);
  });

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

class _CaptureNativeAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('{"message":"mock rejection"}', 400,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
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

class _EncodingApi extends OfficialNovelAiApiService {
  _EncodingApi() : super(Dio());
  int encodes = 0;
  @override
  OfficialNovelAiApiService forBaseUrl(String baseUrl) => this;
  @override
  Future<String> encodeVibeReference(
      {required String imagePath,
      required String model,
      required double informationExtracted,
      required String token}) async {
    encodes++;
    return 'AQID';
  }

  @override
  Future<GenerationTask> generateImageStream(GenerationTask task, String token,
          {void Function(Uint8List, int?)? onFrame}) async =>
      task;
}

class _EncodingLibrary extends _FakeVibeEncodingRepository {
  final entries = <VibeEncoding>[];
  @override
  Future<List<VibeEncoding>> getAll() async => entries;
  @override
  Future<VibeEncoding?> getById(int id) async =>
      entries.where((e) => e.id == id).firstOrNull;
  @override
  Future<VibeEncoding> createFromEncoding(
      {required String title,
      required String encodedVibe,
      required String sourceImagePath,
      String? encodedModel,
      double informationExtracted = 1,
      String? sourceHash}) async {
    final entry = VibeEncoding(
        id: entries.length + 1,
        title: title,
        thumbnailPath: '',
        sourceImagePath: sourceImagePath,
        encodedVibe: encodedVibe,
        encodedModel: encodedModel,
        informationExtracted: informationExtracted,
        sourceHash: sourceHash,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026));
    entries.add(entry);
    return entry;
  }
}
