import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';

void main() {
  final interaction = LlmInteraction(
    id: 'question-1',
    question: '请选择光线',
    options: const [
      LlmInteractionOption(id: 'day', label: '白天', value: 'daylight'),
      LlmInteractionOption(id: 'night', label: '夜晚'),
    ],
    createdAt: DateTime(2026, 8, 26),
  );

  test('round-trips a pending interaction', () {
    final restored = LlmInteraction.fromJsonString(interaction.toJsonString());

    expect(restored, interaction);
    expect(restored?.isAnswered, isFalse);
  });

  test('records a valid selected option once', () {
    final answered = interaction.answerOption('day');

    expect(answered.isAnswered, isTrue);
    expect(answered.answerText, 'daylight');
    expect(answered.answerOption('night'), answered);
  });

  test('rejects malformed interaction data', () {
    expect(LlmInteraction.fromJsonString('{"id":"x"}'), isNull);
    expect(
      LlmInteraction.fromJsonString(
        '{"id":"x","question":"q","options":[{"id":"a","label":"A"},{"id":"a","label":"B"}]}',
      ),
      isNull,
    );
  });
}
