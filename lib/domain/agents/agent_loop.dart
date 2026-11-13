import 'dart:async';
import 'dart:convert';
import 'agent_run_control.dart';
import 'package:nai_huishi/domain/services/chat_token_budget.dart';
import 'package:nai_huishi/domain/entities/llm_response.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/agents/agent_result.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/entities/tool_call.dart';

/// Agent 主循环。负责反复调用 LLM 并执行工具，直到 LLM 给出 stop。
class AgentLoop {
  static const int maxIterations = 16;

  final LlmApiService _api;
  final ToolRegistry _registry;

  /// 副作用工具的确认回调（可以为 null，表示自动同意）
  final ToolConfirmationCallback? onRequireConfirmation;

  /// 事件回调，每次工具状态变更时触发（用于 UI 时间线）
  final void Function(AgentEvent event)? onEvent;
  final void Function(String text)? onText;
  final void Function(LlmResponse response)? onUsage;
  final AgentRunControl? control;
  final int? maxInputTokens;
  final void Function(int)? onEstimate;
  final Future<String> Function()? requestContext;
  final Future<bool> Function(AgentTool, Map<String, dynamic>)? beforeTool;
  final void Function(AgentTool, ToolResult)? afterTool;

  AgentLoop({
    required LlmApiService api,
    required ToolRegistry registry,
    this.onRequireConfirmation,
    this.onEvent,
    this.onText,
    this.onUsage,
    this.control,
    this.maxInputTokens,
    this.onEstimate,
    this.requestContext,
    this.beforeTool,
    this.afterTool,
  })  : _api = api,
        _registry = registry;

  /// 跑一次完整的 agent 循环。
  ///
  /// [initialMessages] 是 system + 用户消息序列（不含 assistant 回复）。
  /// 返回最终的 [AgentResult]。
  Future<AgentResult> run({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> initialMessages,
  }) async {
    if (_registry.isEmpty) {
      return AgentResult.failure('工具表为空，无法启动 Agent', const []);
    }

    final messages = List<Map<String, dynamic>>.from(initialMessages);
    final timeline = <AgentEvent>[];
    final failCounts = <String, int>{};

    try {
      for (int iter = 0; iter < maxIterations; iter++) {
        control?.check();
        final requestMessages = List<Map<String, dynamic>>.of(messages);
        if (requestContext != null) {
          final context = await requestContext!();
          control?.check();
          requestMessages.insert(
            requestMessages.isNotEmpty &&
                    requestMessages.first['role'] == 'system'
                ? 1
                : 0,
            {'role': 'system', 'content': context},
          );
        }
        final estimate = ChatTokenBudget.messages(requestMessages) +
            ChatTokenBudget.text(jsonEncode(_registry.toOpenAiTools()));
        onEstimate?.call(estimate);
        if (maxInputTokens != null && estimate > maxInputTokens!) {
          return AgentResult.failure(
              '本轮工具结果已达到模型上下文容量，请分步处理或使用更大容量模型。', timeline);
        }
        final request = onText == null
            ? _api.chatCompletionsWithTools(
                apiKey: apiKey,
                baseUrl: baseUrl,
                model: model,
                messages: requestMessages,
                tools: _registry.toOpenAiTools(),
                cancelToken: control?.cancelToken)
            : _api.chatCompletionsStreamWithTools(
                apiKey: apiKey,
                baseUrl: baseUrl,
                model: model,
                messages: requestMessages,
                tools: _registry.toOpenAiTools(),
                onText: onText!,
                cancelToken: control?.cancelToken);
        final resp =
            control == null ? await request : await control!.wait(request);
        control?.check();
        onUsage?.call(resp);

        // 把 assistant 消息（含可能的 tool_calls）落回 messages
        final assistantMsg = <String, dynamic>{
          'role': 'assistant',
        };
        if (resp.content.isNotEmpty) {
          assistantMsg['content'] = resp.content;
        }
        if (resp.hasToolCalls) {
          final tcList = resp.toolCalls.map((tc) {
            return <String, dynamic>{
              'id': tc.id,
              'type': 'function',
              'function': {
                'name': tc.name,
                'arguments': _encodeArgs(tc.arguments),
              },
            };
          }).toList();
          assistantMsg['tool_calls'] = tcList;
        }
        messages.add(assistantMsg);

        if (!resp.hasToolCalls) {
          // LLM 给出最终回复，结束循环
          return AgentResult.success(resp.content, timeline);
        }

        // 执行所有 tool_calls
        for (final call in resp.toolCalls) {
          control?.check();
          final event = AgentEvent.fromToolCall(call);
          timeline.add(event);
          onEvent?.call(event);

          final tool = _registry.find(call.name);
          if (tool == null) {
            final updated = event.copyWith(
              status: 'error',
              result: ToolResult.failure('工具 ${call.name} 不存在'),
            );
            _replaceLast(timeline, updated);
            onEvent?.call(updated);
            // 仍要把错误结果回灌给 LLM
            messages.add(
              _toolMessage(call, '失败：工具 ${call.name} 不存在'),
            );
            continue;
          }

          // 副作用工具要确认
          if (tool.requireConfirmation) {
            final confirmed =
                onRequireConfirmation?.call(tool, call.arguments) ??
                    Future.value(true);
            final ok = control == null
                ? await confirmed
                : await control!.wait(confirmed);
            control?.check();
            if (!ok) {
              final updated = event.copyWith(
                status: 'cancelled',
                result: ToolResult.failure('用户取消了 ${tool.name} 执行'),
              );
              _replaceLast(timeline, updated);
              onEvent?.call(updated);
              messages.add(
                _toolMessage(call, '失败：用户取消了执行'),
              );
              continue;
            }
          }

          if (beforeTool != null) {
            final review = beforeTool!(tool, call.arguments);
            final approved =
                control == null ? await review : await control!.wait(review);
            control?.check();
            if (!approved) {
              final cancelled = event.copyWith(
                  status: 'cancelled',
                  result: ToolResult.failure('当前提示词已改变，未执行本次写入'));
              _replaceLast(timeline, cancelled);
              onEvent?.call(cancelled);
              messages.add(_toolMessage(
                  call, '当前提示词已改变或执行条件未满足；请根据下一次请求中的最新提示词重新编排，不要重复提交旧内容。'));
              continue;
            }
          }
          control?.check();
          // 真正执行
          final running = event.copyWith(status: 'running');
          _replaceLast(timeline, running);
          onEvent?.call(running);

          try {
            final result = await tool.call(call.arguments);
            afterTool?.call(tool, result);
            final done = running.copyWith(
                status: result.interaction != null
                    ? 'awaiting_user'
                    : result.success
                        ? 'done'
                        : 'error',
                result: result);
            _replaceLast(timeline, done);
            onEvent?.call(done);
            control?.check();

            if (result.interaction != null) {
              return AgentResult.awaitingUser(result.interaction!, timeline);
            }

            if (!result.success) {
              failCounts[call.name] = (failCounts[call.name] ?? 0) + 1;
              if (failCounts[call.name]! >= 2) {
                // 同一工具失败两次，放弃整个 agent
                return AgentResult.failure(
                  '工具 ${call.name} 连续失败两次，已放弃',
                  timeline,
                );
              }
            } else {
              failCounts.remove(call.name);
            }

            messages.add(_toolMessage(call, result.text));
          } catch (e) {
            control?.check();
            failCounts[call.name] = (failCounts[call.name] ?? 0) + 1;
            final errEvent = running.copyWith(
              status: 'error',
              result: ToolResult.failure(e.toString()),
            );
            _replaceLast(timeline, errEvent);
            onEvent?.call(errEvent);
            messages.add(_toolMessage(call, '失败：$e'));
          }
        }
      }

      // 达到迭代上限
      return AgentResult.maxIterations(
        '达到迭代上限，Agent 已停止。最近一次部分回复已展示。',
        timeline,
      );
    } catch (e) {
      return AgentResult.failure(
          e.toString().replaceFirst('AppException(null): ', ''), timeline);
    }
  }

  Map<String, dynamic> _toolMessage(ToolCall call, String content) => {
        'role': 'tool',
        'tool_call_id': call.id,
        'name': call.name,
        'content': content,
      };

  void _replaceLast(List<AgentEvent> list, AgentEvent next) {
    if (list.isEmpty) return;
    list[list.length - 1] = next;
  }

  String _encodeArgs(Map<String, dynamic> args) {
    if (args.isEmpty) return '{}';
    try {
      return jsonEncode(args);
    } catch (_) {
      return '{}';
    }
  }
}
