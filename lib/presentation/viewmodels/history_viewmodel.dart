import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/usecases/get_history.dart';

/// 历史记录 ViewModel
class HistoryViewModel extends ChangeNotifier {
  final GetHistoryUseCase _getHistory;
  final GenerationQueue _queue;

  StreamSubscription<GenerationTask>? _taskSub;
  StreamSubscription<QueueState>? _queueSub;

  HistoryViewModel(this._getHistory, this._queue) {
    // 入队时立即刷新（让 pending 行可见）
    _queueSub = _queue.queueStream.listen((_) {
      loadHistory(refresh: true);
    });
    // 任务状态变化时刷新（generating / success / failed + imagePath）
    _taskSub = _queue.taskStream.listen((_) {
      loadHistory(refresh: true);
    });
  }

  List<GenerationTask> _history = [];
  List<GenerationTask> _favorites = [];
  bool _isLoading = false;
  int _currentPage = 0;
  bool _hasMore = true;
  String? errorMessage;

  List<GenerationTask> get history => _history;
  List<GenerationTask> get favorites => _favorites;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  /// 加载历史记录
  Future<void> loadHistory({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _currentPage = 0;
      _history = [];
      _hasMore = true;
    }

    if (!_hasMore) return;

    _isLoading = true;
    notifyListeners();

    try {
      final items = await _getHistory.execute(page: _currentPage, pageSize: 20);
      if (refresh) {
        _history = items;
      } else {
        _history.addAll(items);
      }
      _hasMore = items.length >= 20;
      _currentPage++;
    } catch (e) {
      errorMessage = '加载历史失败: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 加载收藏
  Future<void> loadFavorites() async {
    try {
      _favorites = await _getHistory.getFavorites();
      notifyListeners();
    } catch (e) {
      errorMessage = '加载收藏失败: $e';
      notifyListeners();
    }
  }

  /// 切换收藏
  Future<void> toggleFavorite(String taskId) async {
    try {
      await _getHistory.toggleFavorite(taskId);
      // 刷新本地状态
      final index = _history.indexWhere((t) => t.taskId == taskId);
      if (index >= 0) {
        await loadHistory(refresh: true);
      }
      await loadFavorites();
    } catch (e) {
      errorMessage = '操作失败: $e';
      notifyListeners();
    }
  }

  /// 清空历史记录。
  Future<void> clearHistory() async {
    try {
      await _getHistory.clearHistory();
      _history = [];
      _favorites = [];
      _currentPage = 0;
      _hasMore = true;
      notifyListeners();
    } catch (e) {
      errorMessage = '清空历史失败: $e';
      notifyListeners();
    }
  }

  /// 删除记录
  Future<void> deleteTask(String taskId) async {
    try {
      await _getHistory.deleteTask(taskId);
      _history.removeWhere((t) => t.taskId == taskId);
      notifyListeners();
    } catch (e) {
      errorMessage = '删除失败: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _taskSub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }
}
