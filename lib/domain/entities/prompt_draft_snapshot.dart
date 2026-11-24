import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

class PromptDraftSnapshot {
  final String positive, negative, inpaintPositive, inpaintNegative;
  final List<CharacterSpec> characters;
  final bool inpainting;
  final int version;
  PromptDraftSnapshot(
      {required this.positive,
      required this.negative,
      required this.inpaintPositive,
      required this.inpaintNegative,
      required List<CharacterSpec> characters,
      required this.inpainting,
      required this.version})
      : characters = List.unmodifiable(characters);

  bool sameContents(PromptDraftSnapshot other) =>
      positive == other.positive &&
      negative == other.negative &&
      inpaintPositive == other.inpaintPositive &&
      inpaintNegative == other.inpaintNegative &&
      inpainting == other.inpainting &&
      listEquals(characters, other.characters);

  Map<String, Object> toJson() => {
        'positive': positive,
        'negative': negative,
        'inpaintPositive': inpaintPositive,
        'inpaintNegative': inpaintNegative,
        'characters':
            characters.map((character) => character.toJson()).toList(),
        'inpainting': inpainting,
      };

  factory PromptDraftSnapshot.fromJson(Map<String, dynamic> json) =>
      PromptDraftSnapshot(
        positive: json['positive'] as String,
        negative: json['negative'] as String,
        inpaintPositive: json['inpaintPositive'] as String,
        inpaintNegative: json['inpaintNegative'] as String,
        characters: (json['characters'] as List)
            .cast<Map<String, dynamic>>()
            .map(CharacterSpec.fromJson)
            .toList(),
        inpainting: json['inpainting'] as bool,
        version: 0,
      );
}

class PromptDraftChange {
  const PromptDraftChange({
    required this.before,
    required this.after,
    this.changedAt,
  });

  final PromptDraftSnapshot before;
  final PromptDraftSnapshot after;
  final DateTime? changedAt;

  // Preserve the existing tool history column and legacy list format.
  static PromptDraftChange? fromAgentHistory(String? history) {
    if (history == null || !history.startsWith('{')) return null;
    try {
      final data = (jsonDecode(history) as Map)['promptDraftChange'] as Map;
      final changedAt = data['changedAt'] as int?;
      return PromptDraftChange(
        before: PromptDraftSnapshot.fromJson(data['before']),
        after: PromptDraftSnapshot.fromJson(data['after']),
        changedAt: changedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(changedAt),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, Object> toJson() => {
        'before': before.toJson(),
        'after': after.toJson(),
        if (changedAt case final time?)
          'changedAt': time.millisecondsSinceEpoch,
      };
}
