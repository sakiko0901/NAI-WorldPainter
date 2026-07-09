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
    final rows = await _db.query(_table, orderBy: 'updated_at DESC');
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
    // 降级：LIKE 检索
    final like = '%$q%';
    final rows = await _db.rawQuery(
      'SELECT * FROM $_table WHERE "trigger" LIKE ? OR content LIKE ? ORDER BY updated_at DESC LIMIT 200',
      [like, like],
    );
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
        return rows.map(PromptMemoryModel.fromDb).toList();
      } catch (_) {
        _ftsAvailable = false;
      }
    }
    // 降级：LIKE 检索，按 weight ASC, updated_at DESC
    final like = '%$q%';
    final rows = await _db.rawQuery('''
      SELECT * FROM $_table
      WHERE ("trigger" LIKE ? OR content LIKE ?)
        AND source != ?
        AND superseded_by IS NULL
      ORDER BY weight ASC, updated_at DESC
      LIMIT 5
    ''', [like, like, PromptMemorySource.pendingLlmCandidate.name]);
    return rows.map(PromptMemoryModel.fromDb).toList();
  }

  /// 把普通查询字符串转为 FTS5 MATCH 语法。
  /// 策略：分词后每个 token 加前缀通配 *（支持中文/英文前缀匹配），空格分隔为 AND。
  String _ftsQuery(String input) {
    final tokens = input
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().isNotEmpty)
        .map((t) => '"${t.replaceAll('"', ' ')}"*')
        .toList();
    if (tokens.isEmpty) return '""';
    return tokens.join(' ');
  }

  @override
  Future<PromptMemory> save(PromptMemory memory) async {
    final now = DateTime.now();
    final normalized = memory.copyWith(
      trigger: memory.trigger.trim(),
      content: memory.content.trim(),
      updatedAt: now,
    );

    if (normalized.id != null) {
      await _db.update(
        _table,
        PromptMemoryModel.toDb(normalized),
        where: 'id = ?',
        whereArgs: [normalized.id],
      );
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
      {'superseded_by': newId, 'updated_at': DateTime.now().millisecondsSinceEpoch},
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
    final mergedContent = '${newMemory.content.trim()}\n---\n${oldMemory.content.trim()}';
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
  Future<List<PromptMemory>> listStale({Duration olderThan = const Duration(days: 90)}) async {
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

  /// 把 pending 候选晋升为正式记忆（参与检索）。
  Future<void> promotePending(int id, {String? newContent, String? newTrigger}) async {
    final updates = <String, Object?>{
      'source': PromptMemorySource.llmCandidate.name,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (newContent != null && newContent.trim().isNotEmpty) {
      updates['content'] = newContent.trim();
    }
    if (newTrigger != null && newTrigger.trim().isNotEmpty) {
      updates['trigger'] = newTrigger.trim();
    }
    await _db.update(_table, updates, where: 'id = ?', whereArgs: [id]);
  }
}
