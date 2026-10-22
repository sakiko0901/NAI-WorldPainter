import 'package:equatable/equatable.dart';

/// 提示词领域记忆和通用事实。标准穿搭保留自然语言细节，不按 tag 清洗。
enum PromptMemoryType {
  characterName,
  characterFeature,
  characterOutfit,
  style,
  other,
  fact,
  preference,
  observation,
  decision,
}

/// 来源。pendingLlmCandidate 为待用户确认的 LLM 候选，不参与检索。
enum PromptMemorySource {
  manual,
  userInstruction,
  llmCandidate,
  pendingLlmCandidate,
}

/// 作用域。user=跨 agent 共享；project=当前项目；agent=特定 agent 私有。
/// 当前仅使用 user，其他为 agent 化预留。
enum PromptMemoryScope {
  user,
  project,
  agent,
}

class PromptMemory extends Equatable {
  final int? id;
  final String trigger;
  final String content;
  final PromptMemoryType type;
  final PromptMemorySource source;
  final PromptMemoryScope scope;
  final int hitCount;
  final DateTime? lastHitAt;
  final double weight;
  final int? supersededBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PromptMemory({
    this.id,
    required this.trigger,
    required this.content,
    required this.type,
    required this.source,
    this.scope = PromptMemoryScope.user,
    this.hitCount = 0,
    this.lastHitAt,
    this.weight = 1.0,
    this.supersededBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 是否参与检索。pending 候选和已被覆盖的记忆不参与。
  bool get isRetrievable =>
      source != PromptMemorySource.pendingLlmCandidate && supersededBy == null;

  PromptMemory copyWith({
    int? id,
    String? trigger,
    String? content,
    PromptMemoryType? type,
    PromptMemorySource? source,
    PromptMemoryScope? scope,
    int? hitCount,
    DateTime? lastHitAt,
    double? weight,
    int? supersededBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PromptMemory(
      id: id ?? this.id,
      trigger: trigger ?? this.trigger,
      content: content ?? this.content,
      type: type ?? this.type,
      source: source ?? this.source,
      scope: scope ?? this.scope,
      hitCount: hitCount ?? this.hitCount,
      lastHitAt: lastHitAt ?? this.lastHitAt,
      weight: weight ?? this.weight,
      supersededBy: supersededBy ?? this.supersededBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        trigger,
        content,
        type,
        source,
        scope,
        hitCount,
        lastHitAt,
        weight,
        supersededBy,
        createdAt,
        updatedAt,
      ];
}
