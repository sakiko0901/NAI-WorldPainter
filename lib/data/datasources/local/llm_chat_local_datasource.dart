import 'package:sqflite/sqflite.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';

class LlmChatLocalDatasource {
  final Database _db;

  LlmChatLocalDatasource(this._db);

  /// 删除本地图片文件（若存在），失败不阻塞。
  Future<void> _deleteImageFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await ImageUtils.deleteImage(path);
    } catch (_) {
      // 忽略文件删除失败
    }
  }

  /// 查询指定会话内某些消息的 image_path 列表。
  Future<List<String>> _listImagePaths(String sessionId,
      {String? whereClause, List<Object?>? whereArgs}) async {
    final sql = StringBuffer(
        'SELECT image_path FROM llm_messages WHERE session_id = ?');
    final args = <Object?>[sessionId];
    if (whereClause != null && whereClause.isNotEmpty) {
      sql.write(' AND $whereClause');
      if (whereArgs != null) args.addAll(whereArgs);
    }
    final rows = await _db.rawQuery(sql.toString(), args);
    return rows
        .map((r) => r['image_path'] as String?)
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>()
        .toList();
  }

  Future<List<LlmSession>> listSessions() async {
    final rows = await _db.query(
      'llm_sessions',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_sessionFromRow).toList();
  }

  Future<LlmSession?> getSession(String id) async {
    final rows = await _db.query(
      'llm_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  Future<LlmSession?> findSessionByContextKey(String contextKey) async {
    final rows = await _db.query(
      'llm_sessions',
      where: 'context_key = ?',
      whereArgs: [contextKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  Future<void> insertSession(LlmSession session) async {
    await _db.insert('llm_sessions', {
      'id': session.id,
      'title': session.title,
      'scope': session.scope,
      'context_key': session.contextKey,
      'prompt_version': session.promptVersion.value,
      'created_at': session.createdAt.millisecondsSinceEpoch,
      'updated_at': session.updatedAt.millisecondsSinceEpoch,
    });
  }

  Future<void> updateSession(LlmSession session) async {
    await _db.update(
      'llm_sessions',
      {
        'title': session.title,
        'scope': session.scope,
        'context_key': session.contextKey,
        'prompt_version': session.promptVersion.value,
        'updated_at': session.updatedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> touchSession(String id, DateTime when) async {
    await _db.update(
      'llm_sessions',
      {'updated_at': when.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSession(String id) async {
    final paths = await _listImagePaths(id);
    await _db.delete('llm_messages', where: 'session_id = ?', whereArgs: [id]);
    await _db.delete('llm_sessions', where: 'id = ?', whereArgs: [id]);
    for (final p in paths) {
      await _deleteImageFile(p);
    }
  }

  Future<void> deleteAllSessions() async {
    final rows = await _db.query('llm_messages', columns: ['image_path']);
    final paths = rows
        .map((r) => r['image_path'] as String?)
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>()
        .toList();
    await _db.delete('llm_messages');
    await _db.delete('llm_sessions');
    for (final p in paths) {
      await _deleteImageFile(p);
    }
  }

  Future<List<LlmMessage>> listMessages(String sessionId) async {
    final rows = await _db.query(
      'llm_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(_messageFromRow).toList();
  }

  Future<int> insertMessage(LlmMessage message) async {
    final toolCallsJson = message.toolCallsJson ??
        (message.agentTimeline != null && message.agentTimeline!.isNotEmpty
            ? AgentEvent.toJsonList(message.agentTimeline!)
            : null);
    return _db.insert('llm_messages', {
      'session_id': message.sessionId,
      'role': message.roleString,
      'content': message.content,
      'image_path': message.imagePath,
      'tool_calls': toolCallsJson,
      'interaction_json': message.interaction?.toJsonString(),
      'created_at': message.createdAt.millisecondsSinceEpoch,
    });
  }

  Future<void> deleteMessage(int id) async {
    final rows = await _db.query('llm_messages',
        columns: ['image_path'], where: 'id = ?', whereArgs: [id]);
    final path = rows.isNotEmpty ? rows.first['image_path'] as String? : null;
    await _db.delete('llm_messages', where: 'id = ?', whereArgs: [id]);
    await _deleteImageFile(path);
  }

  Future<LlmMessage?> answerInteraction({
    required String sessionId,
    required int messageId,
    required String interactionId,
    String? optionId,
    String? customAnswer,
  }) async {
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'llm_messages',
        where: 'id = ? AND session_id = ? AND role = ?',
        whereArgs: [messageId, sessionId, 'assistant'],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final current = _messageFromRow(rows.first);
      final interaction = current.interaction;
      if (interaction == null ||
          interaction.id != interactionId ||
          interaction.isAnswered) {
        return null;
      }

      final next = optionId != null
          ? interaction.answerOption(optionId)
          : interaction.answerCustom(customAnswer ?? '');
      final answer = next.answerText;
      if (!next.isAnswered || answer == null) return null;

      await txn.update(
        'llm_messages',
        {'interaction_json': next.toJsonString()},
        where: 'id = ?',
        whereArgs: [messageId],
      );
      final now = DateTime.now();
      final content = '针对“${interaction.question}”，我选择：$answer。';
      final userId = await txn.insert('llm_messages', {
        'session_id': sessionId,
        'role': 'user',
        'content': content,
        'created_at': now.millisecondsSinceEpoch,
      });
      await txn.update(
        'llm_sessions',
        {'updated_at': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      return LlmMessage(
        id: userId,
        sessionId: sessionId,
        role: LlmMessageRole.user,
        content: content,
        createdAt: now,
      );
    });
  }

  /// 删除指定消息及之后的所有消息（按 id >= messageId 条件）
  Future<int> deleteMessagesFrom(int messageId, String sessionId) async {
    final paths = await _listImagePaths(sessionId,
        whereClause: 'id >= ?', whereArgs: [messageId]);
    final count = await _db.delete(
      'llm_messages',
      where: 'session_id = ? AND id >= ?',
      whereArgs: [sessionId, messageId],
    );
    for (final p in paths) {
      await _deleteImageFile(p);
    }
    return count;
  }

  LlmSession _sessionFromRow(Map<String, Object?> row) {
    return LlmSession(
      id: row['id'] as String,
      title: row['title'] as String,
      scope: row['scope'] as String? ?? 'general',
      contextKey: row['context_key'] as String?,
      promptVersion:
          NaiPromptVersion.fromValue(row['prompt_version'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  LlmMessage _messageFromRow(Map<String, Object?> row) {
    final toolCallsJson = row['tool_calls'] as String?;
    final interaction = LlmInteraction.fromJsonString(
      row['interaction_json'] as String?,
    );
    return LlmMessage(
      id: row['id'] as int?,
      sessionId: row['session_id'] as String,
      role: LlmMessage.roleFromString(row['role'] as String),
      content: row['content'] as String,
      imagePath: row['image_path'] as String?,
      toolCallsJson: toolCallsJson,
      agentTimeline: AgentEvent.fromJsonList(toolCallsJson),
      interaction: interaction,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }
}
