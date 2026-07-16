import 'package:sqflite/sqflite.dart';
import 'package:nai_huishi/data/models/prompt_memory_model.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/repositories/prompt_memory_repository.dart';

class PromptMemoryRepositoryImpl implements PromptMemoryRepository {
  final Database _db;
  static const String _table = 'prompt_memories';
  static const String _ftsTable = 'prompt_memories_fts';

  PromptMemoryRepositoryImpl(this._db);

  /// FTS5 是否可用（首次访问时探测，结果缓存）。
  bool? _ftsAvailable;
  Future<bool> _isFtsAvailable() async {
    if (_ftsAvailable != null) return _ftsAvailable!;
    try {
      await _db.rawQuery('SELECT COUNT(*) FROM $_ftsTable');
      _ftsAvailable = true;
    } catch (_) {
      _ftsAvailable = false;
    }
    return _ftsAvailable!;
  }

  @override
  Future<List<PromptMemory>> getAll() async {
    final rows = await _db.query(
      _table,
      where: 'source != ?',
      whereArgs: [PromptMemorySource.pendingLlmCandidate.name],
      orderBy: 'updated_at DESC',
    );
    return rows.map(PromptMemoryModel.fromDb).toList();
  }

  @override
  Future<List<PromptMemory>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return getAll();
    if (await _isFtsAvailable()) {
      try {
        final rows = await _db.rawQuery('''
          SELECT m.* FROM $_table m
          JOIN $_ftsTable f ON m.id = f.rowid
          WHERE $_ftsTable MATCH ?
          ORDER BY bm25($_ftsTable), m.updated_at DESC
          LIMIT 200
        ''', [_ftsQuery(q)]);
        return rows.map(PromptMemoryModel.fromDb).toList();
      } catch (_) {
        _ftsAvailable = false;
      }
    }
    final rows = await _likeSearch(q, limit: 200, retrievableOnly: false);
    return rows.map(PromptMemoryModel.fromDb).toList();
  }

  /// FTS5 BM25 检索。只返回可参与注入的记忆（排除 pending 候选和被覆盖的旧记忆）。
  /// 返回 top-k，按 BM25 相关度 × weight 排序。
  /// FTS 不可用时降级为 LIKE，按 weight → updated_at 排序。
  @override
  Future<List<PromptMemory>> matchText(String text) async {
    final q = text.trim();
    if (q.isEmpty) return const [];
    if (await _isFtsAvailable()) {
      try {
        final rows = await _db.rawQuery('''
          SELECT m.* FROM $_table m
          JOIN $_ftsTable f ON m.id = f.rowid
          WHERE $_ftsTable MATCH ?
            AND m.source != ?
            AND m.superseded_by IS NULL
          ORDER BY bm25($_ftsTable) * m.weight ASC
          LIMIT 5
        ''', [_ftsQuery(q), PromptMemorySource.pendingLlmCandidate.name]);
        if (rows.isNotEmpty) {
          return rows.map(PromptMemoryModel.fromDb).toList();
        }
      } catch (_) {
        _ftsAvailable = false;
      }
    }
    final rows = await _likeSearch(q, limit: 5, retrievableOnly: true);
    return rows.map(PromptMemoryModel.fromDb).toList();
  }

  List<String> _queryTokens(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'[,，;；|/\\]+'), ' ')
        .replaceAll(
            RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af\s]+'),
            ' ');
    final tokens = normalized
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toSet()
        .toList();
    return tokens;
  }

  /// FTS5 使用 OR 前缀查询：自然语言中只要命中别名或关键 tag 即可召回，
  /// BM25 仍会把命中更多 token 的结果排在前面。
  String _ftsQuery(String input) {
    final tokens = _queryTokens(input)
        .map((token) => '"${token.replaceAll('"', ' ')}"*')
        .toList();
    if (tokens.isEmpty) return '""';
    return tokens.join(' OR ');
  }

  Future<List<Map<String, Object?>>> _likeSearch(
    String input, {
    required int limit,
    required bool retrievableOnly,
  }) async {
    final tokens = _queryTokens(input);
    if (tokens.isEmpty) return const [];
    final tokenClauses = List.filled(
      tokens.length,
      '(LOWER("trigger") LIKE ? OR LOWER(content) LIKE ? OR LOWER(REPLACE("trigger", \'_\', \' \')) LIKE ? OR LOWER(REPLACE(content, \'_\', \' \')) LIKE ?)',
    ).join(' OR ');
    final args = <Object?>[];
    for (final token in tokens) {
      final like = '%$token%';
      args.addAll([like, like, like, like]);
    }
    final filters =
        retrievableOnly ? 'AND source != ? AND superseded_by IS NULL' : '';
    if (retrievableOnly) {
      args.add(PromptMemorySource.pendingLlmCandidate.name);
    }
    args.add(limit);
    return _db.rawQuery('''
      SELECT * FROM $_table
      WHERE ($tokenClauses)
        $filters
      ORDER BY ${retrievableOnly ? 'weight ASC, ' : ''}updated_at DESC
      LIMIT ?
    ''', args);
  }

  String _normalizeTagContent(String input) {
    final tags = input
        .replaceAll('，', ',')
        .split(RegExp(r'[,\n]+'))
        .map((tag) => tag.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_'))
        .where((tag) =>
            tag.isNotEmpty && RegExp(r'^[a-z0-9_():.+\-]+$').hasMatch(tag))
        .toSet();
    return tags.join(', ');
  }

  bool _isTagMemory(PromptMemoryType type) =>
      type == PromptMemoryType.characterName ||
      type == PromptMemoryType.characterFeature ||
      type == PromptMemoryType.style;

  @override
  Future<PromptMemory> save(PromptMemory memory) async {
    final now = DateTime.now();
    final tagContent = _isTagMemory(memory.type)
        ? _normalizeTagContent(memory.content)
        : memory.content.trim();
    if (_isTagMemory(memory.type) && tagContent.isEmpty) {
      throw ArgumentError('提示词记忆 content 必须是英文 Danbooru tag');
    }
    final normalized = memory.copyWith(
      trigger: memory.trigger.trim(),
      content: tagContent,
      updatedAt: now,
    );

    if (normalized.id != null) {
      final affected = await _db.update(
        _table,
        PromptMemoryModel.toDb(normalized),
        where: 'id = ?',
        whereArgs: [normalized.id],
      );
      if (affected == 0) {
        throw StateError('记忆 ${normalized.id} 不存在，无法更新');
      }
      return normalized;
    }

    final created = normalized.copyWith(createdAt: now, updatedAt: now);
    final id = await _db.insert(_table, PromptMemoryModel.toDb(created));
    return created.copyWith(id: id);
  }

  /// 显式覆盖：把旧记忆 superseded_by 指向新记忆 id。
  /// 调用方应先 save 新记忆拿到 id，再调用此方法标记旧记忆被覆盖。
  Future<void> markSuperseded(int oldId, int newId) async {
    await _db.update(
      _table,
      {
        'superseded_by': newId,
        'updated_at': DateTime.now().millisecondsSinceEpoch
      },
      where: 'id = ?',
      whereArgs: [oldId],
    );
  }

  /// 合并：把旧记忆 content 追加到新记忆 content 后，旧记忆 superseded_by。
  Future<PromptMemory> mergeAndSupersede({
    required PromptMemory oldMemory,
    required PromptMemory newMemory,
  }) async {
    final now = DateTime.now();
    final mergedContent =
        '${newMemory.content.trim()}\n---\n${oldMemory.content.trim()}';
    final merged = newMemory.copyWith(content: mergedContent, updatedAt: now);
    final saved = await save(merged);
    if (saved.id != null) {
      await markSuperseded(oldMemory.id!, saved.id!);
    }
    return saved;
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> incrementHit(int id) async {
    await _db.rawQuery('''
      UPDATE $_table
      SET hit_count = hit_count + 1,
          last_hit_at = ?,
          updated_at = ?
      WHERE id = ?
    ''', [
      DateTime.now().millisecondsSinceEpoch,
      DateTime.now().millisecondsSinceEpoch,
      id,
    ]);
  }

  /// 查找同 trigger 的旧记忆（用于冲突检测）。包括所有 source，但排除已被覆盖的。
  @override
  Future<List<PromptMemory>> findConflicts(String trigger) async {
    final t = trigger.trim();
    if (t.isEmpty) return const [];
    final rows = await _db.query(
      _table,
      where: '"trigger" = ? AND superseded_by IS NULL',
      whereArgs: [t],
      orderBy: 'updated_at DESC',
    );
    return rows.map(PromptMemoryModel.fromDb).toList();
  }

  @override
  Future<List<PromptMemory>> listPending() async {
    final rows = await _db.query(
      _table,
      where: 'source = ?',
      whereArgs: [PromptMemorySource.pendingLlmCandidate.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(PromptMemoryModel.fromDb).toList();
  }

  @override
  Future<List<PromptMemory>> listStale(
      {Duration olderThan = const Duration(days: 90)}) async {
    final threshold = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    final rows = await _db.rawQuery('''
      SELECT * FROM $_table
      WHERE superseded_by IS NULL
        AND source != ?
        AND (last_hit_at IS NULL OR last_hit_at < ?)
        AND hit_count = 0
      ORDER BY created_at ASC
    ''', [PromptMemorySource.pendingLlmCandidate.name, threshold]);
    return rows.map(PromptMemoryModel.fromDb).toList();
  }

  /// 把 pending 候选原地晋升为正式记忆（参与检索）。
  @override
  Future<PromptMemory> promotePending(
    int id, {
    String? newContent,
    String? newTrigger,
    PromptMemoryType? newType,
  }) async {
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('候选记忆 $id 不存在');

    final pending = PromptMemoryModel.fromDb(rows.single);
    if (pending.source != PromptMemorySource.pendingLlmCandidate) {
      throw StateError('记忆 $id 已不在待确认列表中');
    }

    final type = newType ?? pending.type;
    final trigger = (newTrigger ?? pending.trigger).trim();
    final rawContent = (newContent ?? pending.content).trim();
    final content =
        _isTagMemory(type) ? _normalizeTagContent(rawContent) : rawContent;
    if (trigger.isEmpty || content.isEmpty) {
      if (_isTagMemory(type)) {
        throw ArgumentError('请编辑为英文 Danbooru tag 后再确认');
      }
      throw ArgumentError('触发词和内容不能为空');
    }

    final updatedAt = DateTime.now();
    final affected = await _db.update(
      _table,
      {
        'trigger': trigger,
        'content': content,
        'type': type.name,
        'source': PromptMemorySource.llmCandidate.name,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      },
      where: 'id = ? AND source = ?',
      whereArgs: [id, PromptMemorySource.pendingLlmCandidate.name],
    );
    if (affected != 1) throw StateError('候选记忆 $id 晋升失败');

    return pending.copyWith(
      trigger: trigger,
      content: content,
      type: type,
      source: PromptMemorySource.llmCandidate,
      updatedAt: updatedAt,
    );
  }
}
