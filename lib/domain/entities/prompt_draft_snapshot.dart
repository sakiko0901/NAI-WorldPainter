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
}
