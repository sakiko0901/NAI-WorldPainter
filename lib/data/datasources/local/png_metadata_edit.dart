import 'dart:convert';

import 'png_metadata_service.dart';

/// Field conversion and duplicated NAI prompt locations share one export path.
class PngMetadataEdit {
  static const labels = <String, String>{
    'prompt': '正向提示词',
    'uc': '负向提示词',
    'Title': '标题',
    'Software': '生成软件',
    'Source': '来源',
    'steps': '迭代步数',
    'sampler': '采样器',
    'scale': '引导比例',
    'cfg_rescale': '引导重缩放',
    'noise_schedule': '噪声调度',
    'seed': '随机种子',
    'width': '图像宽度（数据）',
    'height': '图像高度（数据）',
  };
  static const _topKeys = {'Title', 'Software', 'Source'};
  static const _integerKeys = {'steps', 'seed', 'width', 'height'};
  static const numericKeys = {..._integerKeys, 'scale', 'cfg_rescale'};

  static String _baseCaption(Map<String, dynamic> comment, String key) {
    final data = comment[key];
    final caption = data is Map ? data['caption'] : null;
    return caption is Map ? caption['base_caption']?.toString() ?? '' : '';
  }

  static Map<String, String> values(PngMetadataDocument document) {
    final comment = document.comment;
    final text = document.text;
    return {
      for (final key in labels.keys)
        key: (_topKeys.contains(key) ? text[key] : comment[key] ?? text[key])
                ?.toString() ??
            '',
      'prompt': comment['prompt']?.toString() ??
          text['Description'] ??
          text['prompt'] ??
          _baseCaption(comment, 'v4_prompt'),
      'uc': (comment['uc'] ??
                  comment['negative_prompt'] ??
                  text['uc'] ??
                  text['negative_prompt'])
              ?.toString() ??
          _baseCaption(comment, 'v4_negative_prompt'),
    };
  }

  static Map<String, dynamic> extraComment(PngMetadataDocument document) => {
        for (final entry in document.comment.entries)
          if ((!labels.containsKey(entry.key) ||
                  _topKeys.contains(entry.key)) &&
              entry.key != 'negative_prompt')
            entry.key: entry.value,
      };

  static String? validateValue(String key, String value) {
    if (!numericKeys.contains(key) || value.trim().isEmpty) return null;
    if (_integerKeys.contains(key)) {
      final number = int.tryParse(value.trim());
      if (number == null) return '请输入整数或留空移除此参数';
      if (key != 'seed' && number <= 0) return '请输入大于 0 的整数或留空';
    } else {
      final number = num.tryParse(value.trim());
      if (number == null || !number.isFinite) return '请输入有效数字或留空移除此参数';
    }
    return null;
  }

  static String? validateExtraJson(String? value) {
    try {
      if (jsonDecode(value ?? '') is Map<String, dynamic>) return null;
    } catch (_) {}
    return '请输入 JSON 对象，例如 {}';
  }

  static Map<String, String> build(
    PngMetadataDocument original,
    Map<String, String> fields, {
    required String extraJson,
  }) {
    final jsonError = validateExtraJson(extraJson);
    if (jsonError != null) throw FormatException(jsonError);
    final comment = jsonDecode(extraJson) as Map<String, dynamic>;
    final text = {...original.text};
    for (final key in labels.keys) {
      final value = fields[key] ?? '';
      final error = validateValue(key, value);
      if (error != null) throw FormatException('${labels[key]}：$error');
      if (_topKeys.contains(key)) {
        if (value.isEmpty) {
          text.remove(key);
        } else {
          text[key] = value;
        }
      } else {
        final dynamic typedValue = numericKeys.contains(key)
            ? (_integerKeys.contains(key)
                ? int.tryParse(value.trim())
                : num.tryParse(value.trim()))
            : value;
        if ((numericKeys.contains(key)
                ? value.trim().isEmpty
                : value.isEmpty) &&
            key != 'prompt' &&
            key != 'uc') {
          comment.remove(key);
          text.remove(key);
        } else {
          comment[key] = typedValue;
          if (text.containsKey(key)) text[key] = value;
        }
      }
    }
    final prompt = fields['prompt'] ?? '';
    final negative = fields['uc'] ?? '';
    text['Description'] = prompt;
    if (original.comment.containsKey('negative_prompt') ||
        comment.containsKey('negative_prompt')) {
      comment['negative_prompt'] = negative;
    }
    if (text.containsKey('negative_prompt')) text['negative_prompt'] = negative;
    for (final entry in {
      'v4_prompt': prompt,
      'v4_negative_prompt': negative,
    }.entries) {
      final data = comment[entry.key];
      if (data is Map<String, dynamic>) {
        final caption = data['caption'];
        if (caption is Map<String, dynamic>) {
          caption['base_caption'] = entry.value;
        }
      }
    }
    text['Comment'] = jsonEncode(comment);
    return text;
  }
}
