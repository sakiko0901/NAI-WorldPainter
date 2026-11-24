import 'package:nai_huishi/domain/entities/llm_provider.dart';

/// Keep the picker and request encoder on the same model capabilities.
class LlmThinking {
  static const _standard = [
    LlmThinkingLevel.low,
    LlmThinkingLevel.medium,
    LlmThinkingLevel.high,
  ];
  static const _extended = [
    ..._standard,
    LlmThinkingLevel.xhigh,
    LlmThinkingLevel.max,
  ];
  static final _modelPrefix = RegExp(r'^(?:models|openai|google|anthropic)/');

  static String _modelId(String model) {
    final id = model.trim().toLowerCase().replaceFirst(_modelPrefix, '');
    return id.startsWith('claude-') ? id.replaceAll('.', '-') : id;
  }

  static bool _isGpt62(String id) =>
      id == 'gpt-6.2' || id.startsWith('gpt-6.2-');

  static String label(String model, LlmThinkingLevel level) {
    if (level == LlmThinkingLevel.max) {
      final id = _modelId(model);
      if (_isGpt62(id)) return 'Ultra';
      if (id.startsWith('claude-')) return 'Max';
    }
    return level.label;
  }

  static bool isDeepSeek(String baseUrl, String model) {
    final id = _modelId(model);
    return Uri.tryParse(baseUrl.trim())?.host == 'api.deepseek.com' &&
        (id == 'deepseek-flash' || id.startsWith('deepseek-v4'));
  }

  static List<LlmThinkingLevel> levels(
      LlmApiProtocol protocol, String baseUrl, String model) {
    final id = _modelId(model);
    if (id.isEmpty) return const [LlmThinkingLevel.automatic];
    final supported = switch (protocol) {
      LlmApiProtocol.gemini => _gemini(id),
      LlmApiProtocol.anthropic => _claude(id),
      LlmApiProtocol.openAi => _openAi(id),
      LlmApiProtocol.openAiCompatible => _compatible(baseUrl, id),
    };
    return [LlmThinkingLevel.automatic, ...?supported];
  }

  static List<LlmThinkingLevel> _compatible(String baseUrl, String id) {
    if (isDeepSeek(baseUrl, id)) {
      return const [
        LlmThinkingLevel.off,
        LlmThinkingLevel.low,
        LlmThinkingLevel.high,
        LlmThinkingLevel.max,
      ];
    }
    if (id.startsWith('gemini-')) return _gemini(id);
    if (id.startsWith('claude-')) return _claude(id);
    return _openAi(id) ?? _standard;
  }

  static List<LlmThinkingLevel> _gemini(String id) {
    if (id.startsWith('gemini-2.5-flash-image')) return const [];
    if (id.startsWith('gemini-3.1-flash-lite-image') ||
        id.startsWith('gemini-3.1-flash-image')) {
      return const [LlmThinkingLevel.minimal, LlmThinkingLevel.high];
    }
    if (id.startsWith('gemini-2.5-flash')) {
      return const [LlmThinkingLevel.off, ..._standard];
    }
    if (id.startsWith('gemini-2.5-pro')) return _standard;
    if (id.startsWith('gemini-4-neon') || id.startsWith('gemini-4-hydrogen')) {
      return const [..._standard, LlmThinkingLevel.xhigh];
    }
    if (id.startsWith('gemini-3.8-flash') ||
        id.startsWith('gemini-4-carbon') ||
        id.startsWith('gemini-4-argon') ||
        id.startsWith('gemini-3.1-pro')) {
      return _standard;
    }
    if (id.startsWith('gemini-3-pro')) {
      return const [LlmThinkingLevel.low, LlmThinkingLevel.high];
    }
    if (id.startsWith('gemini-3.6-flash') ||
        id.startsWith('gemini-3.5-flash-lite') ||
        id.startsWith('gemini-3.1-flash-lite') ||
        id.startsWith('gemini-3-flash') ||
        id.startsWith('gemini-robotics-er-2')) {
      return const [LlmThinkingLevel.minimal, ..._standard];
    }
    return const [];
  }

  static List<LlmThinkingLevel> _claude(String id) {
    if (RegExp(r'^claude-(?:opus|sonnet|haiku|fable|mythos)-5(?:-|$)')
            .hasMatch(id) ||
        id.startsWith('claude-opus-4-7') ||
        id.startsWith('claude-opus-4-8')) {
      return _extended;
    }
    if (id.startsWith('claude-sonnet-4-6') ||
        id.startsWith('claude-opus-4-6') ||
        id.startsWith('claude-mythos-preview')) {
      return const [..._standard, LlmThinkingLevel.max];
    }
    if (id.startsWith('claude-opus-4-5')) return _standard;
    return const [];
  }

  // null means an unrecognized model. An explicitly non-reasoning model
  // returns an empty list even over a compatible endpoint.
  static List<LlmThinkingLevel>? _openAi(String id) {
    if (_isGpt62(id) ||
        id.startsWith('gpt-6-astra') ||
        id.startsWith('gpt-6.1-sol')) {
      return _extended;
    }
    if (id.startsWith('gpt-6-') ||
        id.startsWith('gpt-6.1-') ||
        RegExp(r'^gpt-5\.6(?:-|$)').hasMatch(id)) {
      return const [LlmThinkingLevel.off, ..._extended];
    }
    if (id.startsWith('gpt-5-pro')) return const [LlmThinkingLevel.high];
    if (RegExp(r'^gpt-5\.[245]-pro(?:-|$)').hasMatch(id)) {
      return const [
        LlmThinkingLevel.medium,
        LlmThinkingLevel.high,
        LlmThinkingLevel.xhigh,
      ];
    }
    if (RegExp(r'^gpt-5\.[245](?:-|$)').hasMatch(id)) {
      return const [
        LlmThinkingLevel.off,
        ..._standard,
        LlmThinkingLevel.xhigh,
      ];
    }
    if (RegExp(r'^gpt-5(?:-(?:mini|nano|\d{4})|$)').hasMatch(id)) {
      return const [LlmThinkingLevel.minimal, ..._standard];
    }
    if (id.startsWith('gpt-5.1')) {
      return const [LlmThinkingLevel.off, ..._standard];
    }
    if (RegExp(r'^o[134](?:-|$)').hasMatch(id)) return _standard;
    if (id.startsWith('gpt-4') || id.startsWith('gpt-3.5')) return const [];
    return null;
  }

  static Map<String, dynamic> requestFields(
    LlmApiProtocol protocol,
    String baseUrl,
    String model,
    LlmThinkingLevel level, {
    required bool hasTools,
  }) {
    final selected = levels(protocol, baseUrl, model).contains(level)
        ? level
        : LlmThinkingLevel.automatic;
    if (protocol == LlmApiProtocol.openAiCompatible &&
        isDeepSeek(baseUrl, model)) {
      if (selected == LlmThinkingLevel.automatic && !hasTools) return const {};
      final enabled = selected != LlmThinkingLevel.automatic &&
          selected != LlmThinkingLevel.off;
      return {
        'thinking': {'type': enabled ? 'enabled' : 'disabled'},
        if (enabled) 'reasoning_effort': selected.name,
      };
    }
    if (selected == LlmThinkingLevel.automatic) return const {};
    final effort = selected == LlmThinkingLevel.off ? 'none' : selected.name;
    return switch (protocol) {
      LlmApiProtocol.openAi => {
          'reasoning': {'effort': effort}
        },
      LlmApiProtocol.openAiCompatible => switch (
            Uri.tryParse(baseUrl.trim())?.host) {
          'openrouter.ai' || 'eu.openrouter.ai' => {
              'reasoning': {'effort': effort}
            },
          _ => {'reasoning_effort': effort},
        },
      LlmApiProtocol.anthropic => {
          'output_config': {'effort': effort},
          if (selected == LlmThinkingLevel.xhigh ||
              selected == LlmThinkingLevel.max)
            'max_tokens': 32768,
        },
      LlmApiProtocol.gemini => {
          'generationConfig': {
            'thinkingConfig': model.toLowerCase().contains('gemini-2.5-')
                ? {
                    'thinkingBudget': switch (selected) {
                      LlmThinkingLevel.off => 0,
                      LlmThinkingLevel.low => 1024,
                      LlmThinkingLevel.medium => 4096,
                      _ => 8192,
                    }
                  }
                : {'thinkingLevel': selected.name.toUpperCase()},
          },
        },
    };
  }
}
