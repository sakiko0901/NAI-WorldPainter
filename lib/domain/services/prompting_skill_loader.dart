enum PromptingReference {
  ideation,
  writing,
}

abstract interface class PromptingSkillLoader {
  Future<String> loadSkill();
  Future<String> loadReference(PromptingReference reference);
}
