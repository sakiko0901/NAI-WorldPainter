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
  var responseBytes = false;

  setUp(() async {
    requests = [];
    responseStatus = HttpStatus.ok;
    responseBody = '{"data":[]}';
    responseBytes = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      requests.add(_CapturedRequest(
        request.uri.path,
        await utf8.decoder.bind(request.cast<List<int>>()).join(),
      ));
      request.response.statusCode = responseStatus;
      if (responseBytes) {
        request.response
          ..headers.contentType = ContentType('image', 'png')
          ..add([137, 80, 78, 71]);
      } else {
        request.response
          ..headers.contentType = ContentType.json
          ..write(responseBody);
      }
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
    expect(body, isNot(contains('reference_image')));
    expect(body, isNot(contains('reference_strength')));
    expect(body, isNot(contains('reference_information_extracted')));
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

  test('image-generations sends one global vibe reference', () async {
    final directory = await Directory.systemTemp.createTemp('nai_reference_');
    addTearDown(() => directory.delete(recursive: true));
    final vibe = File('${directory.path}/vibe.png');
    await vibe.writeAsBytes(const [1, 2, 3]);
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        vibeReferences: [
          CharacterReferenceImage(
            path: vibe.path,
            strength: 0.3,
            informationExtracted: 0.8,
          ),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['reference_image'], base64Encode(const [1, 2, 3]));
    expect(body['reference_strength'], 0.3);
    expect(body['reference_information_extracted'], 0.8);
    expect(body, isNot(contains('reference_images')));
    expect(body, isNot(contains('reference_strength_multiple')));
    expect(body, isNot(contains('reference_information_extracted_multiple')));
  });

  test('image-generations only sends the first vibe reference', () async {
    final directory = await Directory.systemTemp.createTemp('nai_reference_');
    addTearDown(() => directory.delete(recursive: true));
    final first = File('${directory.path}/first.png');
    final second = File('${directory.path}/second.png');
    await first.writeAsBytes(const [1]);
    await second.writeAsBytes(const [2]);
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        vibeReferences: [
          CharacterReferenceImage(path: first.path),
          CharacterReferenceImage(path: second.path),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['reference_image'], base64Encode(const [1]));
    expect(body['reference_image'], isNot(base64Encode(const [2])));
  });

  test('precise-reference sends independent references', () async {
    final directory = await Directory.systemTemp.createTemp('nai_reference_');
    addTearDown(() => directory.delete(recursive: true));
    final first = File('${directory.path}/first.png');
    final second = File('${directory.path}/second.png');
    await first.writeAsBytes(const [4]);
    await second.writeAsBytes(const [5]);
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        characters: const [CharacterSpec(prompt: 'girl')],
        preciseReferences: [
          PreciseReferenceImage(
            path: first.path,
            referenceType: 'character',
            strength: 0.7,
            fidelity: 0.9,
          ),
          PreciseReferenceImage(path: second.path, referenceType: 'style'),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(requests.single.path, '/v1/images/precise-reference');
    expect(body['references'], [
      {
        'reference_image': base64Encode(const [4]),
        'reference_type': 'character',
        'strength': 0.7,
        'fidelity': 0.9,
      },
      {
        'reference_image': base64Encode(const [5]),
        'reference_type': 'style',
        'strength': 1.0,
        'fidelity': 1.0,
      },
    ]);
    expect(body['steps'], 31);
    expect(body['width'], 832);
    expect(body['height'], 1216);
    expect(body, isNot(contains('characters')));
    expect(body, isNot(contains('characterPrompts')));
    expect(body, isNot(contains('use_coords')));
    expect(body, isNot(contains('reference_image')));
    expect(body, isNot(contains('reference_strength')));
  });

  test('precise-reference reports an unsupported gateway route', () async {
    responseStatus = HttpStatus.notFound;
    responseBody =
        '{"detail":"Invalid URL (POST /v1/images/precise-reference)"}';
    final directory = await Directory.systemTemp.createTemp('nai_reference_');
    addTearDown(() => directory.delete(recursive: true));
    final reference = File('${directory.path}/reference.png');
    await reference.writeAsBytes(const [4]);
    final service = NovelAiApiService(Dio());

    await expectLater(
      service.generateImage(
        _task(
          protocol: AppConstants.novelAiImageGenerationsProtocol,
          preciseReferences: [PreciseReferenceImage(path: reference.path)],
        ),
        'key',
        baseUri.toString(),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('当前中转站不支持精密参照图像接口'),
        ),
      ),
    );
    expect(requests.single.path, '/v1/images/precise-reference');
  });

  test('precise-reference rejects a missing reference file', () async {
    final service = NovelAiApiService(Dio());

    await expectLater(
      service.generateImage(
        _task(
          protocol: AppConstants.novelAiImageGenerationsProtocol,
          preciseReferences: const [
            PreciseReferenceImage(path: 'missing-reference.png'),
          ],
        ),
        'key',
        baseUri.toString(),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('精密参照图像 1 不可用'),
        ),
      ),
    );
    expect(requests, isEmpty);
  });

  test('image-generations omits a missing vibe reference', () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        vibeReferences: const [
          CharacterReferenceImage(path: 'missing-reference.png'),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body, isNot(contains('reference_image')));
    expect(body, isNot(contains('reference_strength')));
    expect(body, isNot(contains('reference_information_extracted')));
    expect(body, isNot(contains('reference_images')));
    expect(body, isNot(contains('reference_strength_multiple')));
    expect(body, isNot(contains('reference_information_extracted_multiple')));
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

  test('director colorize sends base64 JSON and receives PNG bytes', () async {
    responseBytes = true;
    final source = File(
        '${Directory.systemTemp.path}/director_${DateTime.now().microsecondsSinceEpoch}.png');
    await source.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final service = NovelAiApiService(Dio());

    final result = await service.processDirectorImage(
      imagePath: source.path,
      endpointPath: '/v1/images/director/colorize',
      apiKey: 'key',
      baseUrl: baseUri.toString(),
      model: 'nai-v4.5-full',
      prompt: 'red hair',
      defry: 20,
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(requests.single.path, '/v1/images/director/colorize');
    expect(body['image'], base64Encode([1, 2, 3]));
    expect(body['model'], 'nai-v4.5-full');
    expect(body['prompt'], 'red hair');
    expect(body['defry'], 10);
    expect(body, isNot(contains('level')));
    expect(result, [137, 80, 78, 71]);
  });

  test('director emotion clamps level and omits unrelated parameters',
      () async {
    responseBytes = true;
    final source = File(
        '${Directory.systemTemp.path}/director_${DateTime.now().microsecondsSinceEpoch}.png');
    await source.writeAsBytes([4, 5]);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final service = NovelAiApiService(Dio());

    await service.processDirectorImage(
      imagePath: source.path,
      endpointPath: '/v1/images/director/emotion',
      apiKey: 'key',
      baseUrl: baseUri.toString(),
      prompt: 'smile',
      level: 0,
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['level'], 1);
    expect(body, isNot(contains('defry')));
  });

  test('director preserves JSON error detail from a bytes response', () async {
    responseStatus = HttpStatus.badRequest;
    responseBody = '{"detail":"model is unavailable"}';
    final source = File(
        '${Directory.systemTemp.path}/director_${DateTime.now().microsecondsSinceEpoch}.png');
    await source.writeAsBytes([1]);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final service = NovelAiApiService(Dio());

    await expectLater(
      service.processDirectorImage(
        imagePath: source.path,
        endpointPath: '/v1/images/director/declutter',
        apiKey: 'key',
        baseUrl: baseUri.toString(),
        model: 'nai-v4.5-full',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'model is unavailable',
        ),
      ),
    );
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
  List<CharacterReferenceImage> vibeReferences = const [],
  List<PreciseReferenceImage> preciseReferences = const [],
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
      vibeReferences: vibeReferences,
      preciseReferences: preciseReferences,
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
