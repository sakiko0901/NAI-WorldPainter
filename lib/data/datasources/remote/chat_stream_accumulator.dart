import 'dart:convert';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';

/// Parses complete SSE data events; transport decoding handles split UTF-8 bytes.
class ChatStreamAccumulator {
  final _text = StringBuffer();
  final _calls = <int, Map<String, String>>{};
  String? _finish;
  bool done = false;
  int? promptTokens;
  int? completionTokens;
  String get text => _text.toString();
  void add(String event) {
    if (event.trim() == '[DONE]') {
      done = true;
      return;
    }
    final data = jsonDecode(event) as Map<String, dynamic>;
    if (data['error'] != null)
      throw FormatException('模型流返回错误：${data['error']}');
    final usage = data['usage'];
    if (usage is Map) {
      promptTokens = (usage['prompt_tokens'] as num?)?.toInt();
      completionTokens = (usage['completion_tokens'] as num?)?.toInt();
    }
    for (final choice in (data['choices'] as List? ?? const [])) {
      if (choice is! Map || (choice['index'] ?? 0) != 0) continue;
      if (choice['finish_reason'] != null)
        _finish = choice['finish_reason'].toString();
      final delta = choice['delta'] ?? choice['message'];
      if (delta is! Map) continue;
      if (delta['content'] is String) _text.write(delta['content']);
      for (final raw in (delta['tool_calls'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final index = (raw['index'] as num?)?.toInt() ?? _calls.length;
        final call = _calls.putIfAbsent(
            index, () => {'id': '', 'name': '', 'arguments': ''});
        if (raw['id'] is String) call['id'] = call['id']! + raw['id'];
        final fn = raw['function'];
        if (fn is Map) {
          for (final key in ['name', 'arguments']) {
            if (fn[key] is String) call[key] = call[key]! + fn[key];
          }
        }
        if (call['arguments']!.length > 1000000)
          throw const FormatException('工具参数过大');
      }
    }
  }

  LlmResponse finish() {
    if (!done && _finish == null) throw const FormatException('回复流意外中断，请重试');
    if (_finish == 'length' && _calls.isNotEmpty)
      throw const FormatException('工具参数被截断，未执行');
    final calls = <ToolCall>[];
    for (final index in _calls.keys.toList()..sort()) {
      final call = _calls[index]!;
      if (call['id']!.isEmpty || call['name']!.isEmpty)
        throw const FormatException('工具调用缺少标识');
      final args =
          jsonDecode(call['arguments']!.isEmpty ? '{}' : call['arguments']!);
      if (args is! Map<String, dynamic>)
        throw const FormatException('工具参数格式错误');
      calls
          .add(ToolCall(id: call['id']!, name: call['name']!, arguments: args));
    }
    return LlmResponse(
        content: text,
        toolCalls: calls,
        finishReason: _finish ?? 'stop',
        promptTokens: promptTokens,
        completionTokens: completionTokens);
  }
}
