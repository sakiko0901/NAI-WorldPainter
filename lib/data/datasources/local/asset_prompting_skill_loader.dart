import 'package:flutter/services.dart' show rootBundle;
import 'package:nai_huishi/domain/services/prompting_skill_loader.dart';

class AssetPromptingSkillLoader implements PromptingSkillLoader {
  static const _skillPath = 'assets/nai5-prompting/SKILL.md';
  static const _ideationPath = 'assets/nai5-prompting/references/通用构思.md';
  static const _writingPath = 'assets/nai5-prompting/references/通用写法.md';

  String? _skill;
  final _references = <PromptingReference, String>{};

  @override
  Future<String> loadSkill() => _loadCached(
        value: _skill,
        path: _skillPath,
        save: (value) => _skill = value,
      );

  @override
  Future<String> loadReference(PromptingReference reference) {
    final path = switch (reference) {
      PromptingReference.ideation => _ideationPath,
      PromptingReference.writing => _writingPath,
    };
    return _loadCached(
      value: _references[reference],
      path: path,
      save: (value) => _references[reference] = value,
    );
  }

  Future<String> _loadCached({
    required String? value,
    required String path,
    required void Function(String value) save,
  }) async {
    if (value != null) return value;
    final content = (await rootBundle.loadString(path)).trim();
    if (content.isEmpty) throw StateError('V5 提示词 Skill 资源为空：$path');
    save(content);
    return content;
  }
}
