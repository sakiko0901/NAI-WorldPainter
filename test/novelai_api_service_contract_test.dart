import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _NetworkTestBinding();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.path,
  );
  late HttpServer server;
  late Uri baseUri;
  late List<_CapturedRequest> requests;
  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      final bodyBytes = <int>[];
      await for (final chunk in request) {
        bodyBytes.addAll(chunk);
      }
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });
      requests.add(_CapturedRequest(
        request.uri.path,
        utf8.decode(bodyBytes),
        method: request.method,
        headers: headers,
      ));
      if (request.uri.path.startsWith('/origin/')) {
        final archive = Archive()
          ..addFile(ArchiveFile('result.png', 4, const [137, 80, 78, 71]));
        request.response
          ..headers.contentType = ContentType('application', 'zip')
          ..add(ZipEncoder().encode(archive));
      } else {
        final isVibeEncoding =
            utf8.decode(bodyBytes).contains('"extra":"encode-vibe"');
        request.response
          ..headers.contentType = ContentType.json
          ..write(isVibeEncoding
              ? '{"data":[{"b64_json":"AQID"}]}'
              : '{"data":[{"b64_json":"data:image/png;base64,AQID"}]}');
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('ikun 采样器严格匹配 gateway 当前白名单', () {
    const expected = [
      'k_euler',
      'k_euler_ancestral',
      'k_dpmpp_2s_ancestral',
      'k_dpmpp_2m',
      'k_dpmpp_2m_sde',
      'k_dpmpp_sde',
      'ddim_v3',
    ];
    expect(ApiConstants.ikunSupportedSamplers, expected);
    expect(ApiConstants.ikunSupportedSamplers, isNot(contains('k_dpm_2')));
    expect(ApiConstants.ikunSupportedSamplers, isNot(contains('ddim')));
  });

  test('7877 文生图使用统一接口和标准模型名', () async {
    final service = _service();

    final result =
        await service.generateImage(_task(), 'key', baseUri.toString());
    expect(result.status, 'success');
    expect(result.imagePath, isNotNull);
    expect(await File(result.imagePath!).exists(), isTrue);
    addTearDown(() async {
      final file = File(result.imagePath!);
      if (await file.exists()) await file.delete();
    });

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    expect(body['prompt'], '1girl');
    expect(body['model'], 'nai-diffusion-4-5-full');
    expect(body['n'], 1);
    expect(body['response_format'], 'b64_json');
    expect(body['params']['steps'], 31);
    expect(body['params']['sampler'], 'k_dpm_2');
    expect(body['params']['noise_schedule'], 'polyexponential');
    expect(body['params'], isNot(contains('novelai_operation')));
  });

  test('7877 endpoint ID 优先于旧协议标签路由到新版接口', () async {
    final service = _service();

    final result = await service.generateImage(
      _task(
        endpointId: AppConstants.novelAiChatCompletionsEndpointId,
        protocol: AppConstants.novelAiImageGenerationsProtocol,
      ),
      'key',
      baseUri.toString(),
    );
    expect(result.status, 'success');
    expect(requests.single.path, ApiConstants.imageGenerations);
    final body = _body(requests.single);
    expect(body['model'], 'nai-diffusion-4-5-full');
    await File(result.imagePath!).delete();
  });

  test('7877 图生图通过 image 字段自动路由并携带多角色', () async {
    final directory = await Directory.systemTemp.createTemp('nai_img2img_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    await source.writeAsBytes(const [1, 2, 3]);
    final service = _service();

    await service.generateImage(
      _task(
        img2imgSourceImagePath: source.path,
        img2imgStrength: 0.55,
        characters: const [
          CharacterSpec(
            prompt: 'red hair',
            uc: 'blue hair',
            centerX: 0.25,
            centerY: 0.75,
          ),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.last);
    expect(requests.last.path, ApiConstants.imageGenerations);
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['strength'], 0.55);
    expect(body['noise'], 0.0);
    expect(body['color_correct'], true);
    expect(body['params']['characters'], [
      {
        'prompt': 'red hair',
        'uc': 'blue hair',
        'center': {'x': 0.25, 'y': 0.75},
      },
    ]);
  });

  test('ikun 图生图通过 NewAPI 统一入口发送顶层 gateway 参数', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_ikun_img2img_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    await source.writeAsBytes(const [1, 2, 3]);
    final service = _service();

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        img2imgSourceImagePath: source.path,
        img2imgStrength: 0.55,
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.method, 'POST');
    expect(requests.single.path, ApiConstants.imageGenerations);
    expect(body['novelai_operation'], 'img2img');
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['strength'], 0.55);
    expect(body['noise'], 0.0);
    expect(body['width'], 832);
    expect(body['height'], 1216);
    expect(body['steps'], 31);
    expect(body['scale'], 5);
    expect(body['sampler'], 'k_euler_ancestral');
    expect(body['noise_schedule'], 'polyexponential');
    expect(body['response_format'], 'b64_json');
    expect(body, isNot(contains('params')));
    expect(body, isNot(contains('color_correct')));
  });

  test('ikun 图生图明确拒绝 gateway 无法消费的多角色控制', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_ikun_img2img_chars_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    await source.writeAsBytes(const [1, 2, 3]);
    final service = _service();

    await expectLater(
      service.generateImage(
        _task(
          protocol: AppConstants.novelAiImageGenerationsProtocol,
          img2imgSourceImagePath: source.path,
          characters: const [CharacterSpec(prompt: 'red hair')],
        ),
        'key',
        baseUri.toString(),
      ),
      throwsA(isA<ApiException>().having(
        (error) => error.code,
        'code',
        'IKUN_CHARACTERS_IMG2IMG_UNSUPPORTED',
      )),
    );
    expect(requests, isEmpty);
  });

  test('7877 局部重绘通过 image 和 mask 字段自动路由', () async {
    final directory = await Directory.systemTemp.createTemp('nai_inpaint_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = _service();

    await service.inpaintImage(
      _task(sourceImagePath: source.path, maskImagePath: mask.path),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    expect(body['model'], 'nai-diffusion-4-5-full');
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['mask'], base64Encode(const [4, 5, 6]));
    expect(body['n'], 1);
    expect(body['response_format'], 'b64_json');
    expect(body['params']['steps'], 31);
    expect(body, isNot(contains('novelai_operation')));
  });

  test('ikun 局部重绘始终请求 b64_json 结果', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_inpaint_format_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = _service();

    await service.inpaintImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        responseFormat: 'url',
        sourceImagePath: source.path,
        maskImagePath: mask.path,
      ),
      'key',
      baseUri.toString(),
    );

    expect(_body(requests.single)['response_format'], 'b64_json');
  });

  test('ikun 局部重绘拒绝 gateway 无法消费的多角色控制', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_ikun_inpaint_chars_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = _service();

    await expectLater(
      service.inpaintImage(
        _task(
          protocol: AppConstants.novelAiImageGenerationsProtocol,
          sourceImagePath: source.path,
          maskImagePath: mask.path,
          characters: const [CharacterSpec(prompt: 'red hair')],
        ),
        'key',
        baseUri.toString(),
      ),
      throwsA(isA<ApiException>().having(
        (error) => error.code,
        'code',
        'IKUN_CHARACTERS_INPAINTING_UNSUPPORTED',
      )),
    );
    expect(requests, isEmpty);
  });

  test('ikun 局部重绘通过 NewAPI 统一入口发送顶层参数', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_ikun_inpaint_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = _service();

    await service.inpaintImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        endpointId: AppConstants.novelAiImageGenerationsEndpointId,
        model: 'nai-diffusion-5-full',
        sourceImagePath: source.path,
        maskImagePath: mask.path,
        disabledOriginalImage: true,
        colorCorrect: false,
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.method, 'POST');
    expect(requests.single.path, ApiConstants.imageGenerations);
    expect(body['novelai_operation'], 'inpainting');
    expect(body['model'], 'nai-diffusion-5-full');
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['mask'], base64Encode(const [4, 5, 6]));
    expect(body['strength'], 1.0);
    expect(body['noise'], 0.0);
    expect(body['add_original_image'], isFalse);
    expect(body['color_correct'], isFalse);
    expect(body['width'], 832);
    expect(body['height'], 1216);
    expect(body['steps'], 31);
    expect(body['scale'], 5);
    expect(body['cfg_rescale'], 0);
    expect(body['sampler'], ApiConstants.defaultSampler);
    expect(body['noise_schedule'], 'polyexponential');
    expect(body, isNot(contains('params')));
    expect(body['response_format'], 'b64_json');
  });

  test('ikun full-limit 局部重绘使用当前选择的模型', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_ikun_limit_inpaint_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = _service();

    await service.inpaintImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        endpointId: AppConstants.novelAiImageGenerationsEndpointId,
        model: 'nai-v4.5-full-limit',
        sourceImagePath: source.path,
        maskImagePath: mask.path,
      ),
      'key',
      baseUri.toString(),
    );

    expect(_body(requests.single)['model'], 'nai-v4.5-full-limit');
    expect(_body(requests.single)['response_format'], 'b64_json');
  });

  test('ikun 已是 inpaint 或未知模型时不改写模型', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_ikun_standard_inpaint_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = _service();

    await service.inpaintImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        model: 'custom-inpaint-model',
        sourceImagePath: source.path,
        maskImagePath: mask.path,
      ),
      'key',
      baseUri.toString(),
    );

    expect(_body(requests.single)['model'], 'custom-inpaint-model');
  });

  test('7877 Vibe 先编码每张参考图再传入多个编码结果', () async {
    final directory = await Directory.systemTemp.createTemp('nai_vibe_');
    addTearDown(() => directory.delete(recursive: true));
    final first = File('${directory.path}/first.png');
    final second = File('${directory.path}/second.png');
    await first.writeAsBytes(const [1]);
    await second.writeAsBytes(const [2]);
    final service = _service();

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
    expect(requests[0].path, ApiConstants.imageGenerations);
    expect(requests[1].path, ApiConstants.imageGenerations);
    expect(firstEncoding['extra'], 'encode-vibe');
    expect(secondEncoding['extra'], 'encode-vibe');
    expect(firstEncoding['image'], base64Encode(const [1]));
    expect(secondEncoding['image'], base64Encode(const [2]));
    final generation = _body(requests[2]);
    expect(requests[2].path, ApiConstants.imageGenerations);
    expect(generation['params']['reference_image_multiple'], ['AQID', 'AQID']);
    expect(generation['params']['reference_strength_multiple'], [0.3, 0.7]);
    expect(generation['params']['reference_information_extracted_multiple'],
        [1.0, 0.8]);
  });

  test('7877 预编码 Vibe 直接复用且不请求 encode-vibe', () async {
    final service = _service();

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
    expect(requests.single.path, ApiConstants.imageGenerations);
    expect(body['params']['reference_image_multiple'], ['saved-vibe']);
    expect(body['params']['reference_strength_multiple'], [0.4]);
    expect(body['params']['reference_information_extracted_multiple'], [0.9]);
  });

  test('7877 导演工具使用新版 extra 接口', () async {
    final source = File('${Directory.systemTemp.path}/director_test.png');
    await source.writeAsBytes(img.encodePng(img.Image(width: 1, height: 1)));
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final service = _service();

    await service.processDirectorImage(
      imagePath: source.path,
      operation: 'director-colorize',
      model: 'nai-v4.5-full',
      apiKey: 'key',
      baseUrl: baseUri.toString(),
      prompt: 'blue hair',
      defry: 2,
    );

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    expect(body['extra'], 'director-colorize');
    expect(body['prompt'], 'blue hair');
    expect(body['defry'], 2);
  });

  test('7877 4x 放大使用 extra upscale', () async {
    final source = File('${Directory.systemTemp.path}/upscale_test.png');
    await source.writeAsBytes(const [1, 2, 3]);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    final service = _service();

    await service.upscaleImage7877(
      imagePath: source.path,
      model: 'nai-v4.5-full',
      apiKey: 'key',
      baseUrl: baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.originUpscale);
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['scale'], 4);
  });

  test('ikun 原图 Vibe 由 gateway 通过顶层 reference_image 编码', () async {
    final directory = await Directory.systemTemp.createTemp('nai_ikun_vibe_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/vibe.png');
    await source.writeAsBytes(const [7, 8, 9]);
    final service = _service();

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
    expect(requests.single.path, ApiConstants.imageGenerations);
    expect(body['reference_image'], base64Encode(const [7, 8, 9]));
    expect(body['reference_strength'], 0.35);
    expect(body['reference_information_extracted'], 0.75);
    expect(body, isNot(contains('params')));
    expect(body, isNot(contains('extra')));
  });

  test('7877 Vibe 编码走原生接口', () async {
    final directory = await Directory.systemTemp.createTemp('nai_encode_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/vibe.png');
    await source.writeAsBytes(const [7, 8, 9]);
    final service = _service();

    final encoded = await service.encode7877VibeReference(
      task: _task(),
      reference: CharacterReferenceImage(path: source.path),
      apiKey: 'key',
      baseUrl: baseUri.toString(),
    );

    expect(encoded, 'AQID');
    expect(requests, hasLength(1));
    expect(requests.single.path, ApiConstants.imageGenerations);
    final body = _body(requests.single);
    expect(body['extra'], 'encode-vibe');
    expect(body['model'], 'nai-diffusion-4-5-full');
    expect(body['image'], base64Encode(const [7, 8, 9]));
  });

  test('ikun 不允许误用 7877 的 extra Vibe 编码协议', () async {
    final directory = await Directory.systemTemp.createTemp('nai_ikun_encode_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/vibe.png');
    await source.writeAsBytes(const [7, 8, 9]);
    final service = _service();

    await expectLater(
      service.encode7877VibeReference(
        task: _task(
          protocol: AppConstants.novelAiImageGenerationsProtocol,
          model: 'nai-v4.5-full-limit',
        ),
        reference: CharacterReferenceImage(path: source.path),
        apiKey: 'key',
        baseUrl: baseUri.toString(),
      ),
      throwsA(isA<ApiException>().having(
        (error) => error.code,
        'code',
        'IKUN_VIBE_ENCODING_VIA_GENERATION',
      )),
    );
    expect(requests, isEmpty);
  });

  test('ikun 预编码 Vibe 通过顶层 reference_image 直接复用', () async {
    final service = _service();

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
    expect(body, isNot(contains('params')));
    expect(body, isNot(contains('extra')));
  });

  test('ikun 支持四条 Vibe 并使用 gateway 多值字段', () async {
    final service = _service();
    final references = List.generate(
      AppConstants.maxIkunVibeReferences,
      (index) => CharacterReferenceImage(
        path: '',
        encodedVibe: 'vibe-$index',
        strength: 0.2 + index * 0.1,
        informationExtracted: 0.6 + index * 0.1,
      ),
    );

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        vibeReferences: references,
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(body['reference_images'], ['vibe-0', 'vibe-1', 'vibe-2', 'vibe-3']);
    expect(body['reference_strength_multiple'], [
      closeTo(0.2, 1e-9),
      closeTo(0.3, 1e-9),
      closeTo(0.4, 1e-9),
      closeTo(0.5, 1e-9),
    ]);
    expect(body['reference_information_extracted_multiple'], [
      closeTo(0.6, 1e-9),
      closeTo(0.7, 1e-9),
      closeTo(0.8, 1e-9),
      closeTo(0.9, 1e-9),
    ]);
  });

  test('ikun 拒绝超过 gateway 上限的 Vibe', () async {
    final service = _service();

    await expectLater(
      service.generateImage(
        _task(
          protocol: AppConstants.novelAiImageGenerationsProtocol,
          vibeReferences: List.generate(
            AppConstants.maxIkunVibeReferences + 1,
            (index) =>
                CharacterReferenceImage(path: '', encodedVibe: 'vibe-$index'),
          ),
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

  test('ikun 保留 native 噪声计划并使用 ikun 采样器归一化', () async {
    final service = _service();

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        sampler: 'k_dpm_2',
        noiseSchedule: 'native',
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(body['sampler'], ApiConstants.defaultSampler);
    expect(body['noise_schedule'], 'native');
  });

  test('ikun 精密参考走 precise-reference 操作', () async {
    final directory =
        await Directory.systemTemp.createTemp('nai_ikun_precise_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/reference.png');
    await source.writeAsBytes(const [1, 2, 3]);
    final service = _service();

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

  test('7877 非法采样器和噪声计划回退到网关默认值', () async {
    final service = _service();

    await service.generateImage(
      _task(
        sampler: 'native',
        noiseSchedule: 'native',
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(body['params']['sampler'], ApiConstants.defaultSampler);
    expect(body['params']['noise_schedule'], ApiConstants.defaultNoiseSchedule);
  });

  test('7877 默认 native 噪声计划转换为网关支持的 karras', () async {
    final service = _service();

    await service.generateImage(
      _task(
        protocol: AppConstants.novelAiChatCompletionsProtocol,
        noiseSchedule: 'native',
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(body['params']['noise_schedule'], 'karras');
  });

  test('ikun 文生图使用 gateway 顶层契约和 characterPrompts', () async {
    final service = _service();

    await service.generateImage(
      _task(
        endpointId: AppConstants.novelAiImageGenerationsEndpointId,
        protocol: AppConstants.novelAiChatCompletionsProtocol,
        characters: const [
          CharacterSpec(
            prompt: 'red hair',
            uc: 'bad hair',
            centerX: 0.25,
            centerY: 0.75,
          ),
          CharacterSpec(prompt: 'black hair', enabled: false),
        ],
      ),
      'key',
      baseUri.toString(),
    );

    final body = _body(requests.single);
    expect(requests.single.method, 'POST');
    expect(requests.single.path, '/v1/images/generations');
    expect(body['model'], 'nai-v4.5-full');
    expect(body['prompt'], '1girl');
    expect(body['n'], 1);
    expect(body['size'], '832x1216');
    expect(body['response_format'], 'b64_json');
    expect(body['steps'], 31);
    expect(body['scale'], 5);
    expect(body['sampler'], ApiConstants.defaultSampler);
    expect(body['noise_schedule'], 'polyexponential');
    expect(body['characterPrompts'], [
      {
        'prompt': 'red hair',
        'center': {'x': 0.25, 'y': 0.75},
      },
    ]);
    expect(body['use_coords'], true);
    expect(body['v4_negative_prompt'], {
      'caption': {
        'base_caption': '',
        'char_captions': [
          {
            'char_caption': 'bad hair',
            'centers': [
              {'x': 0.25, 'y': 0.75},
            ],
          },
        ],
      },
      'legacy_uc': false,
    });
    expect(body, isNot(contains('params')));
  });
}

NovelAiApiService _service() {
  final dio = Dio()
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient(),
    );
  return NovelAiApiService(dio);
}

Map<String, dynamic> _body(_CapturedRequest request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

GenerationTask _task({
  String model = 'nai-v4.5-full',
  String protocol = AppConstants.novelAiChatCompletionsProtocol,
  String sampler = 'k_dpm_2',
  String? img2imgSourceImagePath,
  double? img2imgStrength,
  String? sourceImagePath,
  String? maskImagePath,
  List<CharacterReferenceImage> vibeReferences = const [],
  List<PreciseReferenceImage> preciseReferences = const [],
  List<CharacterSpec>? characters,
  bool useCoords = true,
  String? endpointId,
  String noiseSchedule = 'polyexponential',
  String? responseFormat,
}) =>
    GenerationTask(
      taskId: 'task',
      model: model,
      protocol: protocol,
      endpointId: endpointId,
      prompt: '1girl',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: sampler,
      noiseSchedule: noiseSchedule,
      steps: 31,
      useCoords: useCoords,
      characters: characters,
      status: 'pending',
      createdAt: DateTime(2026),
      img2imgSourceImagePath: img2imgSourceImagePath,
      img2imgStrength: img2imgStrength,
      sourceImagePath: sourceImagePath,
      maskImagePath: maskImagePath,
      vibeReferences: vibeReferences,
      preciseReferences: preciseReferences,
      responseFormat: responseFormat,
    );

class _CapturedRequest {
  final String path;
  final String body;
  final String method;
  final Map<String, String> headers;

  const _CapturedRequest(
    this.path,
    this.body, {
    this.method = 'POST',
    this.headers = const {},
  });
}
