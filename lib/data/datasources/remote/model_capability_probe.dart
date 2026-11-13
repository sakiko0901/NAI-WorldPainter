import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'llm_api_service.dart';

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
      required String model}) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final response = await client.get(
        '${base.endsWith('/v1') ? base : '$base/v1'}/models',
        options: Options(
            headers: {'Authorization': 'Bearer $apiKey'},
            receiveTimeout: const Duration(seconds: 20)));
    final data = response.data;
    if (data is! Map || data['data'] is! List) return null;
    for (final item in data['data']) {
      if (item is! Map || item['id'] != model) continue;
      for (final key in [
        'context_length',
        'context_window',
        'max_context_tokens'
      ]) {
        final value = item[key];
        if (value is num && value >= 2048) return value.toInt();
      }
    }
    return null;
  }
}
