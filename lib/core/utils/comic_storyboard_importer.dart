import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';

class ComicStoryboardImporter {
  static const _uuid = Uuid();

  static List<ComicPanel> parse(String source) {
    final trimmed = source.replaceFirst('\uFEFF', '').trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _fromJson(jsonDecode(trimmed));
    }
    if (_looksLikeCsv(trimmed)) return _fromCsv(trimmed);
    return trimmed
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((entry) => _panel(
              index: entry.key + 1,
              title: '分镜 ${entry.key + 1}',
              prompt: entry.value,
            ))
        .toList();
  }

  static bool _looksLikeCsv(String source) {
    final firstLine = source.split(RegExp(r'\r?\n')).first.toLowerCase();
    return firstLine.contains(',') &&
        (firstLine.contains('prompt') ||
            firstLine.contains('tag') ||
            firstLine.contains('提示词'));
  }

  static List<ComicPanel> _fromJson(dynamic source) {
    final values = source is List
        ? source
        : source is Map && source['panels'] is List
            ? source['panels'] as List
            : throw const FormatException('漫画 JSON 缺少 panels 数组');
    return values
        .whereType<Map>()
        .toList()
        .asMap()
        .entries
        .map((entry) {
          final item = Map<String, dynamic>.from(entry.value);
          final dialogues = (item['dialogues'] as List? ?? const [])
              .whereType<Map>()
              .map((raw) {
                final value = Map<String, dynamic>.from(raw);
                return ComicDialogue(
                  id: value['id'] as String? ?? _uuid.v4(),
                  speaker: value['speaker'] as String? ?? '',
                  text: value['text'] as String? ?? '',
                  generateText: value['generateText'] as bool? ?? true,
                );
              })
              .where((dialogue) => dialogue.text.trim().isNotEmpty)
              .toList();
          final rawRect = item['rect'] as Map?;
          return _panel(
            index: entry.key + 1,
            title: item['title'] as String? ?? '分镜 ${entry.key + 1}',
            prompt: (item['prompt'] ?? item['tags'] ?? '').toString(),
            dialogues: dialogues,
            rect: rawRect == null
                ? _defaultRect(entry.key)
                : ComicRect.fromJson(Map<String, dynamic>.from(rawRect)),
          );
        })
        .where((panel) => panel.prompt.trim().isNotEmpty)
        .toList();
  }

  static List<ComicPanel> _fromCsv(String source) {
    final rows = source
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .map(_csvRow)
        .toList();
    if (rows.isEmpty) return const [];
    final headers =
        rows.first.map((item) => item.trim().toLowerCase()).toList();
    final titleIndex = headers.indexWhere((value) =>
        value == 'title' ||
        value == 'name' ||
        value == '分镜标题' ||
        value == '标题');
    final promptIndex = headers.indexWhere((value) =>
        value == 'prompt' ||
        value == 'tags' ||
        value == 'tag' ||
        value == '提示词' ||
        value == '正面提示词');
    final dialogueIndex =
        headers.indexWhere((value) => value == 'dialogue' || value == '台词');
    final start = promptIndex >= 0 ? 1 : 0;
    return rows
        .skip(start)
        .toList()
        .asMap()
        .entries
        .map((entry) {
          final row = entry.value;
          final index = entry.key + 1;
          final prompt =
              row[_boundedIndex(promptIndex >= 0 ? promptIndex : 0, row)]
                  .trim();
          final dialogue = dialogueIndex < 0
              ? ''
              : row[_boundedIndex(dialogueIndex, row)].trim();
          return _panel(
            index: index,
            title: titleIndex < 0
                ? '分镜 $index'
                : row[_boundedIndex(titleIndex, row)].trim(),
            prompt: prompt,
            dialogues: dialogue.isEmpty
                ? const []
                : [ComicDialogue(id: _uuid.v4(), text: dialogue)],
          );
        })
        .where((panel) => panel.prompt.isNotEmpty)
        .toList();
  }

  static int _boundedIndex(int index, List<String> values) =>
      index >= 0 && index < values.length ? index : 0;

  static List<String> _csvRow(String line) {
    final values = <String>[];
    var value = '';
    var quoted = false;
    for (var index = 0; index < line.length; index++) {
      final char = line[index];
      if (char == '"') {
        if (quoted && index + 1 < line.length && line[index + 1] == '"') {
          value += char;
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(value);
        value = '';
      } else {
        value += char;
      }
    }
    values.add(value);
    return values;
  }

  static ComicPanel _panel({
    required int index,
    required String title,
    required String prompt,
    List<ComicDialogue> dialogues = const [],
    ComicRect? rect,
  }) =>
      ComicPanel(
        id: _uuid.v4(),
        index: index,
        title: title.trim().isEmpty ? '分镜 $index' : title.trim(),
        prompt: prompt.trim(),
        rect: rect ?? _defaultRect(index - 1),
        dialogues: dialogues,
      );

  static ComicRect _defaultRect(int index) {
    const columns = 2;
    const gap = 0.03;
    const width = (1 - gap * 3) / columns;
    final column = index % columns;
    final row = index ~/ columns;
    return ComicRect(
      x: gap + column * (width + gap),
      y: gap + row * (0.42 + gap),
      width: width,
      height: 0.42,
    );
  }
}
