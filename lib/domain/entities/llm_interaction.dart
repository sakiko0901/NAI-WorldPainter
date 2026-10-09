import 'dart:convert';

import 'package:equatable/equatable.dart';

class LlmInteractionOption extends Equatable {
  final String id;
  final String label;
  final String? value;

  const LlmInteractionOption({
    required this.id,
    required this.label,
    this.value,
  });

  String get answer => value?.trim().isNotEmpty == true ? value!.trim() : label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (value != null) 'value': value,
      };

  static LlmInteractionOption? fromJson(dynamic value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    final label = value['label']?.toString().trim() ?? '';
    if (id.isEmpty || label.isEmpty) return null;
    return LlmInteractionOption(
      id: id,
      label: label,
      value: value['value']?.toString(),
    );
  }

  @override
  List<Object?> get props => [id, label, value];
}

class LlmInteraction extends Equatable {
  static const protocolVersion = 1;

  final String id;
  final String question;
  final List<LlmInteractionOption> options;
  final bool allowCustom;
  final String? customPlaceholder;
  final String? selectedOptionId;
  final String? customAnswer;
  final DateTime createdAt;
  final DateTime? answeredAt;

  const LlmInteraction({
    required this.id,
    required this.question,
    required this.options,
    this.allowCustom = true,
    this.customPlaceholder,
    this.selectedOptionId,
    this.customAnswer,
    required this.createdAt,
    this.answeredAt,
  });

  bool get isAnswered => selectedOptionId != null || customAnswer != null;

  LlmInteractionOption? get selectedOption {
    final selected = selectedOptionId;
    if (selected == null) return null;
    for (final option in options) {
      if (option.id == selected) return option;
    }
    return null;
  }

  String? get answerText {
    if (customAnswer?.trim().isNotEmpty == true) return customAnswer!.trim();
    return selectedOption?.answer;
  }

  LlmInteraction answerOption(String optionId) {
    if (isAnswered) return this;
    if (!options.any((option) => option.id == optionId)) return this;
    return copyWith(
      selectedOptionId: optionId,
      answeredAt: DateTime.now(),
    );
  }

  LlmInteraction answerCustom(String answer) {
    if (isAnswered || !allowCustom || answer.trim().isEmpty) return this;
    return copyWith(customAnswer: answer.trim(), answeredAt: DateTime.now());
  }

  LlmInteraction copyWith({
    String? selectedOptionId,
    String? customAnswer,
    DateTime? answeredAt,
  }) {
    return LlmInteraction(
      id: id,
      question: question,
      options: options,
      allowCustom: allowCustom,
      customPlaceholder: customPlaceholder,
      selectedOptionId: selectedOptionId ?? this.selectedOptionId,
      customAnswer: customAnswer ?? this.customAnswer,
      createdAt: createdAt,
      answeredAt: answeredAt ?? this.answeredAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': protocolVersion,
        'id': id,
        'question': question,
        'options': options.map((option) => option.toJson()).toList(),
        'allowCustom': allowCustom,
        if (customPlaceholder != null) 'customPlaceholder': customPlaceholder,
        if (selectedOptionId != null) 'selectedOptionId': selectedOptionId,
        if (customAnswer != null) 'customAnswer': customAnswer,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (answeredAt != null)
          'answeredAt': answeredAt!.millisecondsSinceEpoch,
      };

  String toJsonString() => jsonEncode(toJson());

  static LlmInteraction? fromJsonString(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final question = decoded['question']?.toString().trim() ?? '';
      final id = decoded['id']?.toString().trim() ?? '';
      final rawOptions = decoded['options'];
      if (id.isEmpty || question.isEmpty || rawOptions is! List) return null;
      final options = rawOptions
          .map(LlmInteractionOption.fromJson)
          .whereType<LlmInteractionOption>()
          .toList();
      if (options.isEmpty || options.length != rawOptions.length) return null;
      final ids = options.map((option) => option.id).toSet();
      if (ids.length != options.length) return null;
      final createdAt = DateTime.fromMillisecondsSinceEpoch(
        (decoded['createdAt'] as num?)?.toInt() ?? 0,
      );
      final answeredAtValue = decoded['answeredAt'];
      return LlmInteraction(
        id: id,
        question: question,
        options: List.unmodifiable(options),
        allowCustom: decoded['allowCustom'] as bool? ?? true,
        customPlaceholder: decoded['customPlaceholder']?.toString(),
        selectedOptionId: decoded['selectedOptionId']?.toString(),
        customAnswer: decoded['customAnswer']?.toString(),
        createdAt: createdAt,
        answeredAt: answeredAtValue is num
            ? DateTime.fromMillisecondsSinceEpoch(answeredAtValue.toInt())
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [
        id,
        question,
        options,
        allowCustom,
        customPlaceholder,
        selectedOptionId,
        customAnswer,
        createdAt,
        answeredAt,
      ];
}
