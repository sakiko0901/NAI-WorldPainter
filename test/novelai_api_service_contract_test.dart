import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;
  late List<_CapturedRequest> requests;
  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      final body = await utf8.decoder.bind(request.cast<List<int>>()).join();
      requests.add(_CapturedRequest(request.uri.path, body));
      request.response
        ..headers.contentType = ContentType.json
        ..write(body.contains('"extra":')
            ? '{"data":[{"b64_json":"AQID"}]}'
            : '{"data":[]}');
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('两个渠道均使用新文档规定的九个采样器', () {
    const expected = [
      'k_euler',
      'k_euler_ancestral',
      'k_dpm_2',
      'k_dpm_2_ancestral',
      'k_dpmpp_2m',
      'k_dpmpp_2m_sde',
      'k_dpmpp_2s_ancestral',
      'k_dpmpp_sde',
      'ddim',
    ];
    expect(ApiConstants.supportedSamplers, expected);
    expect(ApiConstants.ikunSupportedSamplers, expected);
    expect(ApiConstants.supportedSamplers, isNot(contains('ddim_v3')));
    expect(ApiConstants.supportedSamplers, isNot(contains('gans')));
  });

  test('7877 文生图使用统一接口和标准模型名', () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(_task(), 'key', baseUri.toString());

    final body = _body(requests.single);
    expect(requests.single.path, '/v1/images/generations');
    expect(body['model'], 'nai-diffusion-4-5-full');
    expect(body['sampler'], 'k_dpm_2');
    expect(body['noise_schedule'], 'polyexponential');
    expect(body, isNot(contains('novelai_operation')));
    expect(body, isNot(contains('messages')));
  });

  test('7877 图生图通过 image 字段自动路由', () async {
    final directory = await Directory.systemTemp.createTemp('nai_img2img_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    await source.writeAsBytes(const [1, 2, 3]);
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(img2imgSourceImagePath: source.path, img2imgStrength: 0.55),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.path, '/v1/images/generations');
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['strength'], 0.55);
    expect(body, isNot(contains('extra')));
    expect(body, isNot(contains('novelai_operation')));
  });

  test('7877 局部重绘通过 image 和 mask 字段自动路由', () async {
    final directory = await Directory.systemTemp.createTemp('nai_inpaint_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = NovelAiApiService(Dio());

    await service.inpaintImage(
      _task(sourceImagePath: source.path, maskImagePath: mask.path),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.path, '/v1/images/generations');
    expect(body['model'], 'nai-diffusion-4-5-full');
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['mask'], base64Encode(const [4, 5, 6]));
    expect(body, isNot(contains('novelai_operation')));
    expect(body, isNot(contains('add_original_image')));
  });

  test('7877 Vibe 先编码每张参考图再传入多个编码结果', () async {
    final directory = await Directory.systemTemp.createTemp('nai_vibe_');
    addTearDown(() => directory.delete(recursive: true));
    final first = File('${directory.path}/first.png');
    final second = File('${directory.path}/second.png');
    await first.writeAsBytes(const [1]);
    await second.writeAsBytes(const [2]);
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(vibeReferences: [
        CharacterReferenceImage(path: first.path, strength: 0.3),
        CharacterReferenceImage(
          path: second.path,
          strength: 0.7,
          informationExtracted: 0.8,
        ),
      ]),
      'key',
      baseUri.toString(),
    );

    expect(requests, hasLength(3));
    final firstEncoding = _body(requests[0]);
    final secondEncoding = _body(requests[1]);
    expect(firstEncoding['extra'], 'encode-vibe');
    expect(firstEncoding['model'], 'nai-diffusion-4-5-full');
    expect(firstEncoding['image'], base64Encode(const [1]));
    expect(secondEncoding['extra'], 'encode-vibe');
    expect(secondEncoding['image'], base64Encode(const [2]));
    final generation = _body(requests[2]);
    expect(generation['reference_image_multiple'], ['AQID', 'AQID']);
    expect(generation['reference_strength_multiple'], [0.3, 0.7]);
    expect(generation['reference_information_extracted_multiple'], [1.0, 0.8]);
  });

  test('7877 预编码 Vibe 直接复用且不请求 encode-vibe', () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(vibeReferences: [
        const CharacterReferenceImage(
          path: '',
          encodedVibe: 'saved-vibe',
          strength: 0.4,
          informationExtracted: 0.9,
        ),
      ]),
      'key',
      baseUri.toString(),
    );

    expect(requests, hasLength(1));
    final body = _body(requests.single);
    expect(body['reference_image_multiple'], ['saved-vibe']);
    expect(body['reference_strength_multiple'], [0.4]);
    expect(body['reference_information_extracted_multiple'], [0.9]);
    expect(body, isNot(contains('extra')));
  });

  test('7877 导演工具使用 extra 和标准模型名', () async {
    final sourceBytes = img.encodePng(img.Image(width: 64, height: 64));
    final source = File('${Directory.systemTemp.path}/director_test.png');
    await source.writeAsBytes(sourceBytes);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final service = NovelAiApiService(Dio());

    await service.processDirectorImage(
      imagePath: source.path,
      operation: 'director-colorize',
      model: 'nai-v4.5-full',
      apiKey: 'key',
      baseUrl: baseUri.toString(),
      prompt: 'red hair',
      defry: 9,
    );

    final body = _body(requests.single);
    expect(requests.single.path, '/v1/images/generations');
    expect(body['model'], 'nai-diffusion-4-5-full');
    expect(body['extra'], 'director-colorize');
    expect(body['defry'], 5);
    expect(body, isNot(contains('novelai_operation')));
  });

  test('7877 4x 放大使用 extra upscale', () async {
    final source = File('${Directory.systemTemp.path}/upscale_test.png');
    await source.writeAsBytes(const [1, 2, 3]);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final service = NovelAiApiService(Dio());

    await service.upscaleImage7877(
      imagePath: source.path,
      model: 'nai-v4.5-full',
      apiKey: 'key',
      baseUrl: baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.path, '/v1/images/generations');
    expect(body['extra'], 'upscale');
    expect(body['model'], 'nai-diffusion-4-5-full');
  });

  test('ikun 原图 Vibe 保留单数参考字段', () async {
    final directory = await Directory.systemTemp.createTemp('nai_ikun_vibe_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/vibe.png');
    await source.writeAsBytes(const [7, 8, 9]);
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        vibeReferences: [
          CharacterReferenceImage(
            path: source.path,
            strength: 0.35,
            informationExtracted: 0.75,
          ),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(body['reference_image'], base64Encode(const [7, 8, 9]));
    expect(body['reference_strength'], 0.35);
    expect(body['reference_information_extracted'], 0.75);
    expect(body, isNot(contains('reference_image_multiple')));
  });

  test('ikun Vibe 编码请求保留渠道模型名', () async {
    final directory = await Directory.systemTemp.createTemp('nai_ikun_encode_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/vibe.png');
    await source.writeAsBytes(const [7, 8, 9]);
    final service = NovelAiApiService(Dio());
    final task = _task(
      protocol: AppConstants.novelAiImageGenerationsProtocol,
    );

    await service.encode7877VibeReference(
      task: task,
      reference: CharacterReferenceImage(path: source.path),
      apiKey: 'key',
      baseUrl: baseUri.toString(),
    );

    expect(requests, hasLength(1));
    final body = _body(requests.single);
    expect(body['extra'], 'encode-vibe');
    expect(body['model'], 'nai-v4.5-full');
  });

  test('ikun 预编码 Vibe 直接复用到单数参考字段', () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        vibeReferences: const [
          CharacterReferenceImage(
            path: '',
            encodedVibe: 'saved-ikun-vibe',
            strength: 0.45,
            informationExtracted: 0.85,
          ),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    expect(requests, hasLength(1));
    final body = _body(requests.single);
    expect(body['reference_image'], 'saved-ikun-vibe');
    expect(body['reference_strength'], 0.45);
    expect(body['reference_information_extracted'], 0.85);
    expect(body, isNot(contains('extra')));
    expect(body, isNot(contains('reference_image_multiple')));
  });

  test('ikun 拒绝多条 Vibe，避免静默忽略参考图', () async {
    final service = NovelAiApiService(Dio());

    await expectLater(
      service.generateImage(
        _task(
          protocol: AppConstants.novelAiImageGenerationsProtocol,
          vibeReferences: const [
            CharacterReferenceImage(path: '', encodedVibe: 'first'),
            CharacterReferenceImage(path: '', encodedVibe: 'second'),
          ],
        ),
        'key',
        baseUri.toString(),
      ),
      throwsA(isA<ApiException>().having(
        (error) => error.code,
        'code',
        'IKUN_VIBE_LIMIT',
      )),
    );
    expect(requests, isEmpty);
  });

  test('ikun 精密参考走 precise-reference 操作', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_ikun_precise_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/reference.png');
    await source.writeAsBytes(const [1, 2, 3]);
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        preciseReferences: [
          PreciseReferenceImage(
            path: source.path,
            referenceType: 'character',
            strength: 0.7,
          ),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(body['novelai_operation'], 'precise-reference');
    expect(body['model'], 'nai-v4.5-full');
    expect(body['references'], [
      {
        'reference_image': base64Encode(const [1, 2, 3]),
        'reference_type': 'character',
        'strength': 0.7,
        'fidelity': 1.0,
      },
    ]);
  });

  test('ikun 保留现有 unified operation 契约', () async {
    final service = NovelAiApiService(Dio());

    await service.generateImage(
      _task(protocol: AppConstants.novelAiImageGenerationsProtocol),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.path, '/v1/images/generations');
    expect(body['model'], 'nai-v4.5-full');
    expect(body['sampler'], 'k_dpm_2');
    expect(body, isNot(contains('novelai_operation')));
  });
}

Map<String, dynamic> _body(_CapturedRequest request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

GenerationTask _task({
  String protocol = AppConstants.novelAiChatCompletionsProtocol,
  String? img2imgSourceImagePath,
  double? img2imgStrength,
  String? sourceImagePath,
  String? maskImagePath,
  List<CharacterReferenceImage> vibeReferences = const [],
  List<PreciseReferenceImage> preciseReferences = const [],
}) =>
    GenerationTask(
      taskId: 'task',
      model: 'nai-v4.5-full',
      protocol: protocol,
      prompt: '1girl',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_dpm_2',
      noiseSchedule: 'polyexponential',
      steps: 31,
      status: 'pending',
      createdAt: DateTime(2026),
      img2imgSourceImagePath: img2imgSourceImagePath,
      img2imgStrength: img2imgStrength,
      sourceImagePath: sourceImagePath,
      maskImagePath: maskImagePath,
      vibeReferences: vibeReferences,
      preciseReferences: preciseReferences,
    );

class _CapturedRequest {
  final String path;
  final String body;

  const _CapturedRequest(this.path, this.body);
}
