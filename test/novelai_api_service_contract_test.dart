import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
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
      if (request.uri.path == ApiConstants.officialGenerateImageStream) {
        request.response.headers.contentType =
            ContentType('application', 'octet-stream');
        for (final event in [
          {
            'event_type': 'intermediate',
            'image': Uint8List.fromList([1, 2, 3]),
            'step_ix': 3,
          },
          {
            'event_type': 'final',
            'image': Uint8List.fromList([137, 80, 78, 71]),
          },
        ]) {
          final data = msgpack.serialize(event);
          final header = ByteData(4)..setUint32(0, data.length);
          request.response.add(header.buffer.asUint8List());
          await request.response.flush();
          request.response.add(data);
          await request.response.flush();
        }
      } else if (request.uri.path.startsWith('/origin/') ||
          request.uri.path == ApiConstants.officialGenerateImage) {
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

  for (final model in ['nai-diffusion-4-5-full', 'nai-diffusion-5-full']) {
    for (final stream in [false, true]) {
      for (final positioned in [false, true]) {
        test(
            'official img2img keeps two roles $model stream=$stream coordinates=$positioned',
            () async {
          final directory =
              await Directory.systemTemp.createTemp('native_roles_');
          addTearDown(() => directory.delete(recursive: true));
          final source = File('${directory.path}/source.png');
          final sourceBytes = img.encodePng(img.Image(width: 16, height: 16));
          await source.writeAsBytes(sourceBytes);
          final task = _task(
            model: model,
            protocol: AppConstants.novelAiOfficialProtocol,
            endpointId: AppConstants.novelAiOfficialEndpointId,
            img2imgSourceImagePath: source.path,
            img2imgStrength: 0.55,
            negativePrompt: 'global negative',
            useCoords: positioned,
            characters: [
              CharacterSpec(
                  prompt: 'red hair',
                  uc: 'blue hair',
                  centerX: positioned ? 0.25 : null,
                  centerY: positioned ? 0.75 : null),
              CharacterSpec(
                  prompt: 'black hair',
                  uc: 'white hair',
                  centerX: positioned ? 0.75 : null,
                  centerY: positioned ? 0.25 : null),
              const CharacterSpec(prompt: 'disabled character', enabled: false),
            ],
          );
          final dio = Dio(BaseOptions(baseUrl: baseUri.toString()))
            ..httpClientAdapter = IOHttpClientAdapter(
              createHttpClient: () => HttpClient(),
            );
          final service = OfficialNovelAiApiService(dio);
          final previews = <int>[];
          final result = stream
              ? await service.generateImageStream(task, 'key',
                  onFrame: (bytes, step) {
                  expect(bytes, [1, 2, 3]);
                  previews.add(step!);
                })
              : await service.generateImage(task, 'key');
          addTearDown(() => _deleteIfPresent(result.imagePath));
          expect(result.status, 'success');
          expect(requests, hasLength(1));
          expect(
              requests.single.path,
              stream
                  ? ApiConstants.officialGenerateImageStream
                  : ApiConstants.officialGenerateImage);
          expect(requests.single.headers['authorization'], 'Bearer key');
          final body = _body(requests.single);
          expect(body['action'], 'img2img');
          expect(body['model'], model);
          final parameters = _asMap(body['parameters']);
          expect(parameters['image'], base64Encode(sourceBytes));
          expect(parameters['strength'], 0.55);
          final positive = _asMap(parameters['v4_prompt']);
          final negative = _asMap(parameters['v4_negative_prompt']);
          final roles = _asMap(positive['caption'])['char_captions'] as List;
          final negativeRoles =
              _asMap(negative['caption'])['char_captions'] as List;
          expect(roles.map((role) => role['char_caption']),
              ['red hair', 'black hair']);
          expect(negativeRoles.map((role) => role['char_caption']),
              ['blue hair', 'white hair']);
          expect(_asMap(positive['caption'])['base_caption'], '1girl');
          expect(
              _asMap(negative['caption'])['base_caption'], 'global negative');
          expect(positive['use_coords'], positioned);
          expect(negative['use_coords'], positioned);
          expect(roles.first['centers'], [
            {'x': positioned ? 0.25 : 0.5, 'y': positioned ? 0.75 : 0.5},
          ]);
          expect(roles.last['centers'], [
            {'x': positioned ? 0.75 : 0.5, 'y': positioned ? 0.25 : 0.5},
          ]);
          expect(previews, stream ? [3] : isEmpty);
        });
      }
    }
  }

  group('V5 无坐标多角色请求不启用位置控制', () {
    for (final contract in _v5CharacterContracts) {
      test('${contract.name} 未指定位置时由模型自行构图', () async {
        final request = await _captureCharacterRequest(
          contract,
          useCoords: false,
          baseUri: baseUri,
          requests: requests,
          characters: const [
            CharacterSpec(prompt: 'red hair'),
            CharacterSpec(prompt: 'black hair'),
          ],
        );

        _expectUnpositionedV5Characters(request, contract);
      });

      test('${contract.name} 保留手动角色坐标能力', () async {
        final request = await _captureCharacterRequest(
          contract,
          useCoords: true,
          baseUri: baseUri,
          requests: requests,
          characters: const [
            CharacterSpec(prompt: 'red hair', centerX: 0.23, centerY: 0.37),
            CharacterSpec(prompt: 'black hair', centerX: 0.77, centerY: 0.69),
          ],
        );

        _expectPositionedV5Characters(request, contract);
      });
    }
  });

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

  test('ikun V5 Medium 文生图使用 LFN 顶层字段和正向角色提示', () async {
    final service = _service();

    final result = await service.generateImage(
      _task(
        model: 'nai-v5-full-medium',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        negativePrompt: 'custom negative',
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
    if (result.imagePath != null) await File(result.imagePath!).delete();

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    _expectV5MediumFields(body, model: 'nai-v5-full-medium');
    expect(body['characterPrompts'], [
      {
        'prompt': 'red hair',
        'center': {'x': 0.25, 'y': 0.75},
      },
    ]);
    expect(body['use_coords'], true);
  });

  test('ikun V5 Medium 图生图使用 img2img operation 和规范原生别名', () async {
    final directory = await Directory.systemTemp.createTemp('nai_medium_i2i_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    await source.writeAsBytes(const [1, 2, 3]);
    final service = _service();

    final result = await service.generateImage(
      _task(
        model: 'nai-diffusion-5-full-medium',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        img2imgSourceImagePath: source.path,
        img2imgStrength: 0.55,
      ),
      'key',
      baseUri.toString(),
    );
    if (result.imagePath != null) await File(result.imagePath!).delete();

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    _expectV5MediumFields(
      body,
      model: 'nai-diffusion-5-full-medium',
      operation: 'img2img',
    );
    expect(body['novelai_operation'], 'img2img');
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['strength'], 0.55);
    expect(body['noise'], 0.0);
  });

  test('ikun V5 Medium 局部重绘使用原生重绘别名和正向角色提示', () async {
    final directory = await Directory.systemTemp.createTemp('nai_medium_inp_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = _service();

    final result = await service.inpaintImage(
      _task(
        model: 'nai-diffusion-5-full-medium-inpainting',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        sourceImagePath: source.path,
        maskImagePath: mask.path,
        characters: const [CharacterSpec(prompt: 'red hair', uc: 'blue hair')],
      ),
      'key',
      baseUri.toString(),
    );
    if (result.imagePath != null) await File(result.imagePath!).delete();

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    _expectV5MediumFields(
      body,
      model: 'nai-diffusion-5-full-medium-inpainting',
      operation: 'inpainting',
    );
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['mask'], base64Encode(const [4, 5, 6]));
    expect(body['characterPrompts'], [
      {'prompt': 'red hair'},
    ]);
  });

  test('7877 V5 Medium 文生图将 canonical 模型别名规范化', () async {
    final service = _service();

    final result = await service.generateImage(
      _task(
        model: 'nai-v5-full-medium',
        negativePrompt: 'custom negative',
      ),
      'key',
      baseUri.toString(),
    );
    if (result.imagePath != null) await File(result.imagePath!).delete();

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    _expectV5MediumFields(body, model: 'nai-diffusion-5-full-medium');
  });

  test('7877 V5 Medium 图生图展平参数并标记 img2img operation', () async {
    final directory = await Directory.systemTemp.createTemp('7877_medium_i2i_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    await source.writeAsBytes(const [1, 2, 3]);
    final service = _service();

    final result = await service.generateImage(
      _task(
        model: 'nai-v5-full-medium',
        img2imgSourceImagePath: source.path,
        img2imgStrength: 0.55,
      ),
      'key',
      baseUri.toString(),
    );
    if (result.imagePath != null) await File(result.imagePath!).delete();

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    _expectV5MediumFields(
      body,
      model: 'nai-diffusion-5-full-medium',
      operation: 'img2img',
    );
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['strength'], 0.55);
    expect(body['noise'], 0.0);
  });

  test('7877 V5 Medium 局部重绘规范 inpaint 别名并展平字段', () async {
    final directory =
        await Directory.systemTemp.createTemp('7877_medium_inpaint_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final mask = File('${directory.path}/mask.png');
    await source.writeAsBytes(const [1, 2, 3]);
    await mask.writeAsBytes(const [4, 5, 6]);
    final service = _service();

    final result = await service.inpaintImage(
      _task(
        model: 'nai-v5-inpaint-medium',
        sourceImagePath: source.path,
        maskImagePath: mask.path,
      ),
      'key',
      baseUri.toString(),
    );
    if (result.imagePath != null) await File(result.imagePath!).delete();

    final body = _body(requests.single);
    expect(requests.single.path, ApiConstants.imageGenerations);
    _expectV5MediumFields(
      body,
      model: 'nai-diffusion-5-full-medium-inpainting',
      operation: 'inpainting',
    );
    expect(body['image'], base64Encode(const [1, 2, 3]));
    expect(body['mask'], base64Encode(const [4, 5, 6]));
  });

  test('V5 Medium 明确拒绝 Vibe 和精密参照，不发起网关请求', () async {
    final service = _service();
    final tasks = [
      _task(
        model: 'nai-v5-full-medium',
        protocol: AppConstants.novelAiImageGenerationsProtocol,
        vibeReferences: const [
          CharacterReferenceImage(path: '', encodedVibe: 'encoded-vibe'),
        ],
      ),
      _task(
        model: 'nai-diffusion-5-full-medium',
        preciseReferences: const [PreciseReferenceImage(path: '')],
      ),
    ];

    for (final task in tasks) {
      await expectLater(
        service.generateImage(task, 'key', baseUri.toString()),
        throwsA(isA<ApiException>().having(
          (error) => error.code,
          'code',
          'V5_MEDIUM_REFERENCES_UNSUPPORTED',
        )),
      );
    }
    expect(requests, isEmpty);
  });

  test('V5 Medium 拒绝非 64 倍数或超像素限制尺寸', () async {
    final service = _service();
    final invalidTasks = [
      _task(model: 'nai-v5-full-medium', width: 800),
      _task(
        model: 'nai-v5-full-medium',
        width: 1088,
        height: 1024,
      ),
    ];

    for (final task in invalidTasks) {
      await expectLater(
        service.generateImage(task, 'key', baseUri.toString()),
        throwsA(isA<ApiException>().having(
          (error) => error.code,
          'code',
          'V5_MEDIUM_DIMENSIONS_UNSUPPORTED',
        )),
      );
    }
    expect(requests, isEmpty);
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

  test('ikun 高模型局部重绘发送自动布局角色与角色负向提示', () async {
    final request = await _captureInpaintCharacterRequest(
      isIkun: true,
      useCoords: false,
      baseUri: baseUri,
      requests: requests,
      characters: const [
        CharacterSpec(prompt: 'red hair', uc: 'bad hair'),
        CharacterSpec(
          prompt: 'disabled role marker',
          uc: 'disabled negative marker',
          enabled: false,
        ),
      ],
    );

    final body = _body(request);
    expect(request.path, ApiConstants.imageGenerations);
    expect(body['characterPrompts'], [
      {'prompt': 'red hair'},
    ]);
    expect(body['use_coords'], false);
    expect(body['v4_negative_prompt'], {
      'caption': {
        'base_caption': 'global negative',
        'char_captions': [
          {'char_caption': 'bad hair', 'centers': <Map<String, double>>[]},
        ],
      },
      'legacy_uc': false,
    });
    expect(request.body, isNot(contains('disabled role marker')));
    expect(request.body, isNot(contains('disabled negative marker')));
    expect(body, isNot(contains('params')));
  });

  test('ikun 高模型局部重绘保留角色手动坐标和负向坐标', () async {
    final request = await _captureInpaintCharacterRequest(
      isIkun: true,
      useCoords: true,
      baseUri: baseUri,
      requests: requests,
      characters: const [
        CharacterSpec(
          prompt: 'red hair',
          uc: 'bad hair',
          centerX: 0.23,
          centerY: 0.37,
        ),
        CharacterSpec(
          prompt: 'disabled role marker',
          uc: 'disabled negative marker',
          centerX: 0.8,
          centerY: 0.7,
          enabled: false,
        ),
      ],
    );

    final body = _body(request);
    expect(body['characterPrompts'], [
      {
        'prompt': 'red hair',
        'center': {'x': 0.23, 'y': 0.37},
      },
    ]);
    expect(body['use_coords'], true);
    expect(body['v4_negative_prompt']['caption']['char_captions'], [
      {
        'char_caption': 'bad hair',
        'centers': [
          {'x': 0.23, 'y': 0.37},
        ],
      },
    ]);
    expect(request.body, isNot(contains('disabled role marker')));
    expect(request.body, isNot(contains('disabled negative marker')));
  });

  test('7877 高模型局部重绘发送自动布局角色正负向并忽略禁用角色', () async {
    final request = await _captureInpaintCharacterRequest(
      isIkun: false,
      useCoords: false,
      baseUri: baseUri,
      requests: requests,
      characters: const [
        CharacterSpec(prompt: 'red hair', uc: 'bad hair'),
        CharacterSpec(
          prompt: 'disabled role marker',
          uc: 'disabled negative marker',
          enabled: false,
        ),
      ],
    );

    final body = _body(request);
    final params = _asMap(body['params']);
    expect(request.path, ApiConstants.imageGenerations);
    expect(params['characters'], [
      {'prompt': 'red hair', 'uc': 'bad hair'},
    ]);
    expect(params['use_coords'], false);
    expect(params['negative_prompt'], 'global negative');
    expect(body, isNot(contains('characterPrompts')));
    expect(request.body, isNot(contains('disabled role marker')));
    expect(request.body, isNot(contains('disabled negative marker')));
  });

  test('7877 高模型局部重绘保留角色手动坐标', () async {
    final request = await _captureInpaintCharacterRequest(
      isIkun: false,
      useCoords: true,
      baseUri: baseUri,
      requests: requests,
      characters: const [
        CharacterSpec(
          prompt: 'red hair',
          uc: 'bad hair',
          centerX: 0.23,
          centerY: 0.37,
        ),
        CharacterSpec(
          prompt: 'disabled role marker',
          uc: 'disabled negative marker',
          centerX: 0.8,
          centerY: 0.7,
          enabled: false,
        ),
      ],
    );

    final params = _asMap(_body(request)['params']);
    expect(params['characters'], [
      {
        'prompt': 'red hair',
        'uc': 'bad hair',
        'center': {'x': 0.23, 'y': 0.37},
      },
    ]);
    expect(params['use_coords'], true);
    expect(request.body, isNot(contains('disabled role marker')));
    expect(request.body, isNot(contains('disabled negative marker')));
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

Future<_CapturedRequest> _captureCharacterRequest(
  _V5CharacterContract contract, {
  required bool useCoords,
  required List<CharacterSpec> characters,
  required Uri baseUri,
  required List<_CapturedRequest> requests,
}) async {
  final task = _task(
    model: contract.model,
    protocol: contract.protocol,
    useCoords: useCoords,
    characters: characters,
  );
  if (contract.isOfficial) {
    final dio = Dio(BaseOptions(baseUrl: baseUri.toString()))
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpClient(),
      );
    final result =
        await OfficialNovelAiApiService(dio).generateImage(task, 'key');
    await _deleteIfPresent(result.imagePath);
  } else {
    final result = await _service().generateImage(
      task,
      'key',
      baseUri.toString(),
    );
    await _deleteIfPresent(result.imagePath);
  }

  expect(requests, hasLength(1));
  return requests.single;
}

Future<_CapturedRequest> _captureInpaintCharacterRequest({
  required bool isIkun,
  required bool useCoords,
  required List<CharacterSpec> characters,
  required Uri baseUri,
  required List<_CapturedRequest> requests,
}) async {
  final directory =
      await Directory.systemTemp.createTemp('nai_inpaint_characters_');
  addTearDown(() => directory.delete(recursive: true));
  final source = File('${directory.path}/source.png');
  final mask = File('${directory.path}/mask.png');
  await source.writeAsBytes(const [1, 2, 3]);
  await mask.writeAsBytes(const [4, 5, 6]);
  final result = await _service().inpaintImage(
    _task(
      model: 'nai-diffusion-5-full',
      protocol: isIkun
          ? AppConstants.novelAiImageGenerationsProtocol
          : AppConstants.novelAiChatCompletionsProtocol,
      sourceImagePath: source.path,
      maskImagePath: mask.path,
      useCoords: useCoords,
      characters: characters,
      negativePrompt: 'global negative',
    ),
    'key',
    baseUri.toString(),
  );
  await _deleteIfPresent(result.imagePath);

  expect(requests, hasLength(1));
  return requests.single;
}

Future<void> _deleteIfPresent(String? path) async {
  if (path == null) return;
  final file = File(path);
  if (await file.exists()) await file.delete();
}

void _expectUnpositionedV5Characters(
  _CapturedRequest request,
  _V5CharacterContract contract,
) {
  final body = _body(request);
  if (contract.isOfficial) {
    expect(request.path, ApiConstants.officialGenerateImage);
    expect(body['model'], contract.model);
    expect(body['action'], 'generate');

    final parameters = _asMap(body['parameters']);
    final positive = _asMap(parameters['v4_prompt']);
    final positiveCaption = _asMap(positive['caption']);
    final placeholderCenters = [
      {'x': 0.5, 'y': 0.5},
    ];
    expect(parameters['use_coords'], false);
    expect(positive['use_coords'], false);
    expect(positiveCaption['char_captions'], [
      {'char_caption': 'red hair', 'centers': placeholderCenters},
      {'char_caption': 'black hair', 'centers': placeholderCenters},
    ]);
    final negative = _asMap(parameters['v4_negative_prompt']);
    final negativeCaption = _asMap(negative['caption']);
    expect(negative['use_coords'], false);
    expect(negativeCaption['char_captions'], [
      {'char_caption': '', 'centers': placeholderCenters},
      {'char_caption': '', 'centers': placeholderCenters},
    ]);
    return;
  }

  expect(request.path, ApiConstants.imageGenerations);
  expect(body['model'], contract.model);
  if (contract.isIkun || contract.isMedium) {
    expect(body['use_coords'], false);
    expect(body['characterPrompts'], [
      {'prompt': 'red hair'},
      {'prompt': 'black hair'},
    ]);
    expect(body, isNot(contains('params')));
    return;
  }

  final parameters = _asMap(body['params']);
  expect(parameters['use_coords'], false);
  expect(parameters['characters'], [
    {'prompt': 'red hair', 'uc': ''},
    {'prompt': 'black hair', 'uc': ''},
  ]);
}

void _expectPositionedV5Characters(
  _CapturedRequest request,
  _V5CharacterContract contract,
) {
  final body = _body(request);
  if (contract.isOfficial) {
    final parameters = _asMap(body['parameters']);
    final positive = _asMap(parameters['v4_prompt']);
    final positiveCaption = _asMap(positive['caption']);
    expect(parameters['use_coords'], true);
    expect(positive['use_coords'], true);
    expect(positiveCaption['char_captions'], [
      {
        'char_caption': 'red hair',
        'centers': [
          {'x': 0.23, 'y': 0.37},
        ],
      },
      {
        'char_caption': 'black hair',
        'centers': [
          {'x': 0.77, 'y': 0.69},
        ],
      },
    ]);
    return;
  }

  if (contract.isIkun || contract.isMedium) {
    expect(body['use_coords'], true);
    expect(body['characterPrompts'], [
      {
        'prompt': 'red hair',
        'center': {'x': 0.23, 'y': 0.37},
      },
      {
        'prompt': 'black hair',
        'center': {'x': 0.77, 'y': 0.69},
      },
    ]);
    return;
  }

  final parameters = _asMap(body['params']);
  expect(parameters['use_coords'], true);
  expect(parameters['characters'], [
    {
      'prompt': 'red hair',
      'uc': '',
      'center': {'x': 0.23, 'y': 0.37},
    },
    {
      'prompt': 'black hair',
      'uc': '',
      'center': {'x': 0.77, 'y': 0.69},
    },
  ]);
}

Map<String, dynamic> _asMap(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

const List<_V5CharacterContract> _v5CharacterContracts = [
  _V5CharacterContract(
    '官方 V5 High',
    'nai-diffusion-5-full',
    AppConstants.novelAiOfficialProtocol,
    isOfficial: true,
  ),
  _V5CharacterContract(
    'IKUN V5 High',
    'nai-diffusion-5-full',
    AppConstants.novelAiImageGenerationsProtocol,
    isIkun: true,
  ),
  _V5CharacterContract(
    'IKUN V5 Medium',
    'nai-diffusion-5-full-medium',
    AppConstants.novelAiImageGenerationsProtocol,
    isIkun: true,
  ),
  _V5CharacterContract(
    '7877 V5 High',
    'nai-diffusion-5-full',
    AppConstants.novelAiChatCompletionsProtocol,
  ),
  _V5CharacterContract(
    '7877 V5 Medium',
    'nai-diffusion-5-full-medium',
    AppConstants.novelAiChatCompletionsProtocol,
  ),
];

class _V5CharacterContract {
  final String name;
  final String model;
  final String protocol;
  final bool isOfficial;
  final bool isIkun;

  const _V5CharacterContract(
    this.name,
    this.model,
    this.protocol, {
    this.isOfficial = false,
    this.isIkun = false,
  });

  bool get isMedium => model.contains('medium');
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

void _expectV5MediumFields(
  Map<String, dynamic> body, {
  required String model,
  String? operation,
}) {
  expect(body['model'], model);
  if (operation != null) {
    expect(body['novelai_operation'], operation);
  } else {
    expect(body, isNot(contains('novelai_operation')));
  }
  expect(body['steps'], 14);
  expect(body['sampler'], 'k_euler_ancestral');
  expect(body['n'], 1);
  expect(body['ucPreset'], 0);
  expect(body['tag_hint_uc_preset'], 2);
  expect(body, isNot(contains('params')));
  expect(body, isNot(contains('cfg_rescale')));
  expect(body, isNot(contains('negative_prompt')));
  expect(body, isNot(contains('v4_negative_prompt')));
}

GenerationTask _task({
  String model = 'nai-v4.5-full',
  String protocol = AppConstants.novelAiChatCompletionsProtocol,
  String sampler = 'k_dpm_2',
  String? img2imgSourceImagePath,
  double? img2imgStrength,
  String? sourceImagePath,
  String? maskImagePath,
  bool disabledOriginalImage = false,
  bool colorCorrect = true,
  List<CharacterReferenceImage> vibeReferences = const [],
  List<PreciseReferenceImage> preciseReferences = const [],
  List<CharacterSpec>? characters,
  bool useCoords = true,
  String? endpointId,
  String noiseSchedule = 'polyexponential',
  String? responseFormat,
  int width = 832,
  int height = 1216,
  String? negativePrompt,
}) =>
    GenerationTask(
      taskId: 'task',
      model: model,
      protocol: protocol,
      endpointId: endpointId,
      prompt: '1girl',
      width: width,
      height: height,
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
      negativePrompt: negativePrompt,
      sourceImagePath: sourceImagePath,
      maskImagePath: maskImagePath,
      disabledOriginalImage: disabledOriginalImage,
      colorCorrect: colorCorrect,
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
