import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/remote/gpt_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/nano_banana_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/data/repositories/generation_repository_impl.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';

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
      gptApiService: GptApiService(Dio()),
      nanoApiService: NanoBananaApiService(Dio()),
      settingsRepo: settings,
    );

    await repository.submitGeneration(_task(endpointId: 'selected'));

    expect(service.apiKey, 'selected-key');
    expect(service.baseUrl, 'https://selected.example');
  });
}

GenerationTask _task({String? endpointId}) => GenerationTask(
      taskId: 'task',
      endpointId: endpointId,
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
    );

class _RecordingNovelAiService extends NovelAiApiService {
  _RecordingNovelAiService() : super(Dio());

  String? apiKey;
  String? baseUrl;

  @override
  Future<GenerationTask> generateImage(
    GenerationTask task,
    String apiKey,
    String baseUrl,
  ) async {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
    return task;
  }
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
