import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;
  late List<_CapturedRequest> requests;
  var responseStatus = HttpStatus.ok;
  var responseBody = '{"data":[]}';

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      requests.add(_CapturedRequest(
        request.uri.path,
        await utf8.decoder.bind(request.cast<List<int>>()).join(),
      ));
      request.response
        ..statusCode = responseStatus
        ..headers.contentType = ContentType.json
        ..write(responseBody);
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('chat-completions keeps the legacy route and omits steps', () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(protocol: AppConstants.novelAiChatCompletionsProtocol),
      'key',
      baseUri.toString(),
    );

    expect(requests.single.path, '/v1/chat/completions');
    expect(requests.single.body, isNot(contains('"steps"')));
  });

  test('image-generations sends the minimal text-to-image contract', () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(protocol: AppConstants.novelAiImageGenerationsProtocol),
      'key',
      baseUri.toString(),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(requests.single.path, '/v1/images/generations');
    expect(body['steps'], 31);
    expect(body['size'], '832x1216');
    expect(body['width'], 832);
    expect(body['height'], 1216);
    expect(body['response_format'], 'b64_json');
    expect(body, isNot(contains('negative_prompt')));
    expect(body, isNot(contains('characterPrompts')));
    expect(body, isNot(contains('use_coords')));
    expect(body, isNot(contains('reference_images')));
    expect(body, isNot(contains('reference_strength_multiple')));
    expect(body, isNot(contains('reference_information_extracted_multiple')));
  });
  test(
      'image-generations includes character fields only for enabled characters',
      () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        characters: const [
          CharacterSpec(prompt: 'girl', enabled: true),
          CharacterSpec(prompt: 'boy', enabled: false),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['characterPrompts'], [
      {'prompt': 'girl', 'uc': ''},
    ]);
    expect(body['use_coords'], isFalse);
  });

  test(
      'image-generations honors valid response format and normalizes parameters',
      () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        sampler: 'ddim',
        noiseSchedule: 'polyexponential',
        responseFormat: 'url',
      ),
      'key',
      baseUri.toString(),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['sampler'], 'ddim_v3');
    expect(body['noise_schedule'], 'exponential');
    expect(body['response_format'], 'url');
  });

  test('image-generations preserves a 500 response summary', () async {
    responseStatus = HttpStatus.internalServerError;
    responseBody = '{"detail":"invalid sampler"}';
    final service = NovelAiApiService(Dio());

    await expectLater(
      service.generateImage(
        _task(protocol: AppConstants.novelAiImageGenerationsProtocol),
        'key',
        baseUri.toString(),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '服务器错误 (500)：invalid sampler',
        ),
      ),
    );
  });
}

GenerationTask _task({
  required String protocol,
  List<CharacterSpec>? characters,
  String sampler = 'k_euler',
  String noiseSchedule = 'native',
  String? responseFormat,
}) =>
    GenerationTask(
      taskId: 'task',
      model: 'model',
      protocol: protocol,
      prompt: '1girl',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: sampler,
      noiseSchedule: noiseSchedule,
      characters: characters,
      responseFormat: responseFormat,
      steps: 31,
      useCoords: false,
      status: 'pending',
      createdAt: DateTime(2026),
    );

class _CapturedRequest {
  final String path;
  final String body;

  const _CapturedRequest(this.path, this.body);
}
