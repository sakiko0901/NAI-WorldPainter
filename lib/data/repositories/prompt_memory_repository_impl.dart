import 'package:sqflite/sqflite.dart';
import 'package:nai_huishi/data/models/prompt_memory_model.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/repositories/prompt_memory_repository.dart';
import 'package:nai_huishi/domain/services/prompt_memory_context.dart';

class PromptMemoryRepositoryImpl implements PromptMemoryRepository {
  final Database _db;
  static const String _table = 'prompt_memories';
  static const String _ftsTable = 'prompt_memories_fts';
  static const int _maxQueryLength = 2048;
  static const int _maxQueryTokens = 32;
  static const int _maxOutfitTriggerLength = 512;
  static const int _maxOutfitContentLength = 6000;

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
    final q = _boundedQuery(query);
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
    final q = _boundedQuery(text);
    if (q.isEmpty || _queryTokens(q).isEmpty) return const [];
    final triggerQuery = _boundedTriggerQuery(q);

    // 先按明确触发词检索。穿搭记忆只能由角色名/别名触发，不允许
    // 仅因正文中出现相同的衣物标签而串到其他角色。
    final directMatches = await _matchTriggerMemories(triggerQuery);
    final results = directMatches.take(5).toList();
    if (results.length == 5) return results;

    final usedIds = results.map((memory) => memory.id).whereType<int>().toSet();
    final remaining = 5 - results.length;
    if (await _isFtsAvailable()) {
      try {
        final rows = await _db.rawQuery('''
          SELECT m.* FROM $_table m
          JOIN $_ftsTable f ON m.id = f.rowid
          WHERE $_ftsTable MATCH ?
            AND m.source != ?
            AND m.superseded_by IS NULL
            AND m.scope = ?
            AND m.type != ?
          ORDER BY bm25($_ftsTable) * m.weight ASC
          LIMIT ?
        ''', [
          _ftsQuery(q),
          PromptMemorySource.pendingLlmCandidate.name,
          PromptMemoryScope.user.name,
          PromptMemoryType.characterOutfit.name,
          remaining,
        ]);
        if (rows.isNotEmpty) {
          for (final row in rows) {
            final memory = PromptMemoryModel.fromDb(row);
            if (memory.id == null || usedIds.add(memory.id!)) {
              results.add(memory);
            }
          }
          return results.take(5).toList();
        }
      } catch (_) {
        _ftsAvailable = false;
      }
    }
    final rows = await _likeSearch(
      q,
      limit: remaining,
      retrievableOnly: true,
      userScopeOnly: true,
      excludeOutfits: true,
    );
    for (final row in rows) {
      final memory = PromptMemoryModel.fromDb(row);
      if (memory.id == null || usedIds.add(memory.id!)) results.add(memory);
    }
    return results.take(5).toList();
  }

  String _boundedQuery(String input) =>
      String.fromCharCodes(input.trim().runes.take(_maxQueryLength)).trim();

  String _boundedTriggerQuery(String input) {
    final bounded = _boundedQuery(input);
    final tokenPattern = RegExp(
      r'[a-zA-Z0-9\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]+',
    );
    final matches =
        tokenPattern.allMatches(bounded).take(_maxQueryTokens + 1).toList();
    if (matches.isEmpty) return '';
    if (matches.length <= _maxQueryTokens) return bounded;
    // 在第 33 个词元之前截断并保留其前的原始标点，避免切断
    // firefly_(honkai:_star_rail) 这类 canonical tag/name。
    return bounded.substring(0, matches[_maxQueryTokens].start).trimRight();
  }

  List<String> _queryTokens(String input) {
    final bounded = String.fromCharCodes(input.runes.take(_maxQueryLength));
    final normalized = bounded
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
        .take(_maxQueryTokens)
        .toSet()
        .toList();
    return tokens;
  }

  Future<List<PromptMemory>> _matchTriggerMemories(String query) async {
    final rows = await _db.query(
      _table,
      where: 'source != ? AND superseded_by IS NULL AND scope = ?',
      whereArgs: [
        PromptMemorySource.pendingLlmCandidate.name,
        PromptMemoryScope.user.name,
      ],
    );
    final matches = rows
        .map(PromptMemoryModel.fromDb)
        .where((memory) => PromptMemoryTriggers.matches(memory.trigger, query))
        .toList();
    matches.sort((a, b) {
      final specificity = _matchedAliasLength(b, query)
          .compareTo(_matchedAliasLength(a, query));
      if (specificity != 0) return specificity;
      final aOutfit = a.type == PromptMemoryType.characterOutfit;
      final bOutfit = b.type == PromptMemoryType.characterOutfit;
      if (aOutfit != bOutfit) return bOutfit ? 1 : -1;
      final weight = b.weight.compareTo(a.weight);
      if (weight != 0) return weight;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return matches;
  }

  int _matchedAliasLength(PromptMemory memory, String query) {
    var longest = 0;
    for (final alias in PromptMemoryTriggers.parse(memory.trigger)) {
      if (PromptMemoryTriggers.matches(alias, query)) {
        final length = alias.runes.length;
        if (length > longest) longest = length;
      }
    }
    return longest;
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
    bool userScopeOnly = false,
    bool excludeOutfits = false,
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
    final filters = <String>[];
    if (retrievableOnly) {
      filters.add('source != ? AND superseded_by IS NULL');
      args.add(PromptMemorySource.pendingLlmCandidate.name);
    }
    if (userScopeOnly) {
      filters.add('scope = ?');
      args.add(PromptMemoryScope.user.name);
    }
    if (excludeOutfits) {
      filters.add('type != ?');
      args.add(PromptMemoryType.characterOutfit.name);
    }
    args.add(limit);
    return _db.rawQuery('''
      SELECT * FROM $_table
      WHERE ($tokenClauses)
        ${filters.map((filter) => 'AND $filter').join(' ')}
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
    final isOutfit = memory.type == PromptMemoryType.characterOutfit;
    final tagContent = _isTagMemory(memory.type)
        ? _normalizeTagContent(memory.content)
        : memory.content.trim();
    if (_isTagMemory(memory.type) && tagContent.isEmpty) {
      throw ArgumentError('提示词记忆 content 必须是英文 Danbooru tag');
    }
    var normalized = memory.copyWith(
      trigger: memory.trigger.trim(),
      content: tagContent,
      updatedAt: now,
    );

    if (isOutfit) _validateOutfit(normalized.trigger, normalized.content);

    if (!isOutfit) {
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

    return _db.transaction((txn) async {
      var wasActive = normalized.id == null &&
          normalized.source != PromptMemorySource.pendingLlmCandidate &&
          normalized.supersededBy == null;
      if (normalized.id != null) {
        final existingRows = await txn.query(
          _table,
          columns: ['source', 'superseded_by', 'trigger'],
          where: 'id = ?',
          whereArgs: [normalized.id],
          limit: 1,
        );
        if (existingRows.isEmpty) {
          throw StateError('记忆 ${normalized.id} 不存在，无法更新');
        }
        final existing = existingRows.single;
        final wasSuperseded = existing['superseded_by'] != null;
        if (wasSuperseded) {
          // 即使调用方持有旧快照，也不能把已归档版本复活或让它覆盖现行版本。
          normalized = normalized.copyWith(
            supersededBy: existing['superseded_by'] as int,
          );
        }
        wasActive = !wasSuperseded &&
            normalized.source != PromptMemorySource.pendingLlmCandidate &&
            normalized.supersededBy == null;
        if (wasActive) {
          normalized = await _carryForwardOutfitAliases(
            txn,
            normalized,
          );
        }
      } else if (wasActive) {
        normalized = await _carryForwardOutfitAliases(txn, normalized);
      }

      _validateOutfit(normalized.trigger, normalized.content);
      final persisted = await _saveWithExecutor(txn, normalized, now);
      if (wasActive && persisted.id != null) {
        await _supersedeOverlappingOutfits(txn, persisted);
      }
      return persisted;
    });
  }

  void _validateOutfit(String trigger, String content) {
    if (trigger.isEmpty ||
        PromptMemoryTriggers.parse(trigger).isEmpty ||
        content.isEmpty) {
      throw ArgumentError('角色穿搭记忆的触发词和内容不能为空');
    }
    if (trigger.runes.length > _maxOutfitTriggerLength) {
      throw ArgumentError('角色穿搭记忆的触发词不能超过 $_maxOutfitTriggerLength 个字符');
    }
    if (content.runes.length > _maxOutfitContentLength) {
      throw ArgumentError('角色穿搭记忆的内容不能超过 $_maxOutfitContentLength 个字符');
    }
  }

  Future<PromptMemory> _saveWithExecutor(
    DatabaseExecutor executor,
    PromptMemory memory,
    DateTime now,
  ) async {
    if (memory.id != null) {
      final affected = await executor.update(
        _table,
        PromptMemoryModel.toDb(memory),
        where: 'id = ?',
        whereArgs: [memory.id],
      );
      if (affected == 0) {
        throw StateError('记忆 ${memory.id} 不存在，无法更新');
      }
      return memory;
    }

    final created = memory.copyWith(createdAt: now, updatedAt: now);
    final id = await executor.insert(_table, PromptMemoryModel.toDb(created));
    return created.copyWith(id: id);
  }

  Future<void> _supersedeOverlappingOutfits(
    DatabaseExecutor executor,
    PromptMemory newMemory,
  ) async {
    if (newMemory.id == null ||
        newMemory.type != PromptMemoryType.characterOutfit ||
        newMemory.source == PromptMemorySource.pendingLlmCandidate ||
        newMemory.supersededBy != null) {
      return;
    }
    final rows = await executor.query(
      _table,
      where:
          'type = ? AND scope = ? AND source != ? AND superseded_by IS NULL AND id != ?',
      whereArgs: [
        PromptMemoryType.characterOutfit.name,
        newMemory.scope.name,
        PromptMemorySource.pendingLlmCandidate.name,
        newMemory.id,
      ],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      final old = PromptMemoryModel.fromDb(row);
      if (!PromptMemoryTriggers.overlap(old.trigger, newMemory.trigger)) {
        continue;
      }
      await executor.update(
        _table,
        {'superseded_by': newMemory.id, 'updated_at': now},
        where: 'id = ? AND superseded_by IS NULL AND source != ?',
        whereArgs: [old.id, PromptMemorySource.pendingLlmCandidate.name],
      );
    }
  }

  Future<PromptMemory> _carryForwardOutfitAliases(
    DatabaseExecutor executor,
    PromptMemory newMemory,
  ) async {
    if (newMemory.type != PromptMemoryType.characterOutfit ||
        newMemory.source == PromptMemorySource.pendingLlmCandidate ||
        newMemory.supersededBy != null) {
      return newMemory;
    }
    final rows = await executor.query(
      _table,
      where: 'type = ? AND scope = ? AND source != ? AND superseded_by IS NULL',
      whereArgs: [
        PromptMemoryType.characterOutfit.name,
        newMemory.scope.name,
        PromptMemorySource.pendingLlmCandidate.name,
      ],
    );
    final overlappingTriggers = <String>[];
    for (final row in rows) {
      final old = PromptMemoryModel.fromDb(row);
      // 手动编辑同一行时允许删除错误别名；新版本继承被替换的其他行的别名。
      if (old.id != newMemory.id &&
          PromptMemoryTriggers.overlap(old.trigger, newMemory.trigger)) {
        overlappingTriggers.add(old.trigger);
      }
    }

    final aliases = <String>[];
    for (final trigger in [
      newMemory.trigger,
      ...overlappingTriggers,
    ]) {
      for (final alias in PromptMemoryTriggers.parse(trigger)) {
        if (!aliases.any(
          (existing) => PromptMemoryTriggers.overlap(existing, alias),
        )) {
          aliases.add(alias);
        }
      }
    }
    return newMemory.copyWith(trigger: aliases.join(' | '));
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
  }) async =>
      _db.transaction((txn) async {
        final rows = await txn.query(
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
        var trigger = (newTrigger ?? pending.trigger).trim();
        final rawContent = (newContent ?? pending.content).trim();
        final content =
            _isTagMemory(type) ? _normalizeTagContent(rawContent) : rawContent;
        if (type == PromptMemoryType.characterOutfit) {
          final aliasMerged = await _carryForwardOutfitAliases(
            txn,
            pending.copyWith(
              trigger: trigger,
              content: content,
              type: type,
              source: PromptMemorySource.llmCandidate,
            ),
          );
          trigger = aliasMerged.trigger;
          _validateOutfit(trigger, content);
        } else if (trigger.isEmpty || content.isEmpty) {
          if (_isTagMemory(type)) {
            throw ArgumentError('请编辑为英文 Danbooru tag 后再确认');
          }
          throw ArgumentError('触发词和内容不能为空');
        }

        final updatedAt = DateTime.now();
        final affected = await txn.update(
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

        final promoted = pending.copyWith(
          trigger: trigger,
          content: content,
          type: type,
          source: PromptMemorySource.llmCandidate,
          updatedAt: updatedAt,
        );
        if (type == PromptMemoryType.characterOutfit) {
          await _supersedeOverlappingOutfits(txn, promoted);
        }
        return promoted;
      });
}
