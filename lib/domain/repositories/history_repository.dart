import 'package:nai_huishi/domain/entities/generation_task.dart';

abstract class HistoryRepository {
  /// 保存生成记录
  Future<GenerationTask> saveTask(GenerationTask task);

  /// 更新任务状态
  Future<GenerationTask> updateTask(GenerationTask task);

  /// 获取所有历史记录（分页）
  Future<List<GenerationTask>> getHistory({int page = 0, int pageSize = 20});

  /// 裁剪历史记录数量
  Future<void> trimHistory({int keep = 30});

  /// 获取单个任务
  Future<GenerationTask?> getTask(String taskId);

  /// 删除任务
  Future<void> deleteTask(String taskId);

  /// 清空历史记录。应用内未引用的副本由定期清理回收。
  Future<void> clearHistory();

  /// 获取任务数量
  Future<int> getTaskCount();

  /// 按状态筛选
  Future<List<GenerationTask>> getTasksByStatus(String status);

  /// 收藏/取消收藏
  Future<GenerationTask> toggleFavorite(String taskId);

  /// 获取收藏列表
  Future<List<GenerationTask>> getFavorites();
}
