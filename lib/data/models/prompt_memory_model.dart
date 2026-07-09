import 'package:nai_huishi/domain/entities/prompt_memory.dart';

class PromptMemoryModel {
  static Map<String, dynamic> toDb(PromptMemory memory) => {
        'id': memory.id,
        'trigger': memory.trigger,
        'content': memory.content,
        'type': memory.type.name,
        'source': memory.source.name,
        'scope': memory.scope.name,
        'hit_count': memory.hitCount,
        'last_hit_at': memory.lastHitAt?.millisecondsSinceEpoch,
        'weight': memory.weight,
        'superseded_by': memory.supersededBy,
        'created_at': memory.createdAt.millisecondsSinceEpoch,
        'updated_at': memory.updatedAt.millisecondsSinceEpoch,
      };

  static PromptMemory fromDb(Map<String, dynamic> row) => PromptMemory(
        id: row['id'] as int?,
        trigger: row['trigger'] as String,
        content: row['content'] as String,
        type: PromptMemoryType.values.firstWhere(
          (e) => e.name == row['type'],
          orElse: () => PromptMemoryType.other,
        ),
        source: PromptMemorySource.values.firstWhere(
          (e) => e.name == row['source'],
          orElse: () => PromptMemorySource.manual,
        ),
        scope: PromptMemoryScope.values.firstWhere(
          (e) => e.name == (row['scope'] as String? ?? 'user'),
          orElse: () => PromptMemoryScope.user,
        ),
        hitCount: (row['hit_count'] as int?) ?? 0,
        lastHitAt: row['last_hit_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['last_hit_at'] as int),
        weight: (row['weight'] as num?)?.toDouble() ?? 1.0,
        supersededBy: row['superseded_by'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );
}
