import 'package:sqflite/sqflite.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/data/models/generation_task_model.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final Database _db;

  HistoryRepositoryImpl(this._db);

  static const String _table = 'generation_history';

  @override
  Future<GenerationTask> saveTask(GenerationTask task) async {
    final model = GenerationTaskModel.fromEntity(task);
    final id = await _db.insert(_table, model.toDb());
    await trimHistory();
    return task.copyWith(id: id);
  }

  @override
  Future<GenerationTask> updateTask(GenerationTask task) async {
    final model = GenerationTaskModel.fromEntity(task);
    await _db.update(
      _table,
      model.toDb(),
      where: 'task_id = ?',
      whereArgs: [task.taskId],
    );
    return task;
  }

  @override
  Future<List<GenerationTask>> getHistory(
      {int page = 0, int pageSize = 20}) async {
    final offset = page * pageSize;
    final rows = await _db.query(
      _table,
      orderBy: 'created_at DESC',
      limit: pageSize,
      offset: offset,
    );
    return rows.map((r) => GenerationTaskModel.fromDb(r).toEntity()).toList();
  }

  @override
  Future<void> trimHistory({int keep = 200}) async {
    final overflowRows = await _db.query(
      _table,
      columns: ['task_id'],
      orderBy: 'created_at DESC',
      limit: -1,
      offset: keep,
    );

    for (final row in overflowRows) {
      final taskId = row['task_id'] as String?;
      if (taskId != null && taskId.isNotEmpty) {
        await deleteTask(taskId);
      }
    }
  }

  @override
  Future<GenerationTask?> getTask(String taskId) async {
    final rows = await _db.query(
      _table,
      where: 'task_id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GenerationTaskModel.fromDb(rows.first).toEntity();
  }

  @override
  Future<void> deleteTask(String taskId) async {
    // 只查 image_path 列，避免历史行中其它大字段（如过长的 error_message、
    // characters JSON）撑爆 Android CursorWindow（默认 1~2MB）。
    final rows = await _db.query(
      _table,
      columns: ['image_path'],
      where: 'task_id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    final imagePath = rows.isEmpty ? null : rows.first['image_path'] as String?;
    if (imagePath != null && imagePath.isNotEmpty) {
      await ImageUtils.deleteImage(imagePath);
    }
    await _db.delete(_table, where: 'task_id = ?', whereArgs: [taskId]);
  }

  @override
  Future<void> clearHistory() async {
    await _db.delete(_table);
  }

  @override
  Future<int> getTaskCount() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as count FROM $_table');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<List<GenerationTask>> getTasksByStatus(String status) async {
    final rows = await _db.query(
      _table,
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => GenerationTaskModel.fromDb(r).toEntity()).toList();
  }

  @override
  Future<GenerationTask> toggleFavorite(String taskId) async {
    final task = await getTask(taskId);
    if (task == null) throw Exception('任务不存在');

    final model = GenerationTaskModel.fromEntity(task);
    final newFav = !model.isFavorite;
    await _db.update(
      _table,
      {'is_favorite': newFav ? 1 : 0},
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    return task; // 返回旧状态，前端自行翻转
  }

  @override
  Future<List<GenerationTask>> getFavorites() async {
    final rows = await _db.query(
      _table,
      where: 'is_favorite = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => GenerationTaskModel.fromDb(r).toEntity()).toList();
  }
}
