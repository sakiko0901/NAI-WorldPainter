import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'llm_api_service.dart';
import 'llm_native_protocol.dart';

class ModelCapabilityProbe {
  final LlmApiService api;
  ModelCapabilityProbe(this.api);
  Future<bool> image(
      {required String apiKey,
      required String baseUrl,
      required String model}) async {
    final code = List.generate(
            4,
            (_) =>
                '23456789ABCDEFGHJKMNPQRSTUVWXYZ'[Random.secure().nextInt(30)])
        .join();
    final picture = img.Image(width: 260, height: 100);
    img.fill(picture, color: img.ColorRgb8(255, 255, 255));
    img.drawString(picture, code,
        font: img.arial48, x: 15, y: 20, color: img.ColorRgb8(0, 0, 0));
    final response = await api.chatCompletions(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        messages: [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    'Read the four characters in this image. Reply only those characters.'
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url':
                      'data:image/png;base64,${base64Encode(img.encodePng(picture))}'
                }
              },
            ]
          },
        ]);
    return response.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '') ==
        code;
  }

  Future<bool> tools(
      {required String apiKey,
      required String baseUrl,
      required String model}) async {
    final nonce = Random.secure().nextInt(10000000).toString();
    final response = await api.chatCompletionsWithTools(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        messages: [
          {
            'role': 'user',
            'content': 'Call capability_probe with code "$nonce".'
          }
        ],
        toolChoice: 'required',
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'capability_probe',
              'description': 'Return the supplied code.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'code': {'type': 'string'}
                },
                'required': ['code']
              }
            }
          }
        ]);
    return response.toolCalls.any((call) =>
        call.name == 'capability_probe' && call.arguments['code'] == nonce);
  }

  static Future<int?> contextWindow(Dio client,
      {required String apiKey,
      required String baseUrl,
      required String model,
      LlmApiProtocol protocol = LlmApiProtocol.openAiCompatible}) async {
    final path = switch (protocol) {
      LlmApiProtocol.gemini =>
        'models/${Uri.encodeComponent(geminiModelId(model))}',
      LlmApiProtocol.anthropic => 'models/${Uri.encodeComponent(model)}',
      _ => 'models',
    };
    final response = await client.get(llmEndpoint(protocol, baseUrl, path),
        options: Options(
            headers: llmAuthHeaders(protocol, apiKey),
            followRedirects: protocol != LlmApiProtocol.gemini,
            receiveTimeout: const Duration(seconds: 20)));
    final data = response.data;
    if (data is! Map) return null;
    final models = data['data'];
    final item = switch (protocol) {
      LlmApiProtocol.gemini || LlmApiProtocol.anthropic => data,
      _ => models is List
          ? models
              .whereType<Map>()
              .where((item) => item['id'] == model)
              .firstOrNull
          : null,
    };
    for (final key in [
      'inputTokenLimit',
      'max_input_tokens',
      'context_length',
      'context_window',
      'max_context_tokens',
    ]) {
      final value = item?[key];
      if (value is num && value >= 2048) return value.toInt();
    }
    return null;
  }
}
