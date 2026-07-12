import 'dart:async';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';

/// 生成任务队列
/// NovelAI Gateway 同一时间只处理 1 个图像请求
/// 此队列保证串行执行，并提供状态流
class GenerationQueue {
  final GenerationRepository _generationRepo;
  final HistoryRepository _historyRepo;

  final List<GenerationTask> _queue = [];
  GenerationTask? _currentTask;
  bool _isProcessing = false;

  final _queueController = StreamController<QueueState>.broadcast();
  final _taskController = StreamController<GenerationTask>.broadcast();

  GenerationQueue(this._generationRepo, this._historyRepo);

  Stream<QueueState> get queueStream => _queueController.stream;
  Stream<GenerationTask> get taskStream => _taskController.stream;
  int get length => _queue.length;
  bool get isProcessing => _isProcessing;
  GenerationTask? get currentTask => _currentTask;

  /// 入队
  Future<void> enqueue(GenerationTask task) async {
    _queue.add(task);
    _notifyState();
    _processNext();
  }

  /// 批量入队
  Future<void> enqueueAll(List<GenerationTask> tasks) async {
    _queue.addAll(tasks);
    _notifyState();
    _processNext();
  }

  /// 取消排队中的任务（不能取消正在执行的）
  bool cancel(String taskId) {
    final index = _queue.indexWhere((t) => t.taskId == taskId);
    if (index >= 0) {
      _queue.removeAt(index);
      _notifyState();
      return true;
    }
    return false;
  }

  /// 清空队列
  void clear() {
    _queue.clear();
    _notifyState();
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    _currentTask = _queue.removeAt(0);
    _notifyState();

    try {
      final generatingTask = _currentTask!.copyWith(status: 'generating');
      await _historyRepo.updateTask(generatingTask);
      _taskController.add(generatingTask);

      final completedTask =
          await _generationRepo.submitGeneration(generatingTask);
      await _historyRepo.updateTask(completedTask);
      _taskController.add(completedTask);
    } on ApiException catch (e) {
      final failedTask = _currentTask!.copyWith(
        status: 'failed',
        errorMessage: e.message,
        completedAt: DateTime.now(),
      );
      await _publishFailedTask(failedTask);
    } catch (e) {
      final failedTask = _currentTask!.copyWith(
        status: 'failed',
        errorMessage: e.toString(),
        completedAt: DateTime.now(),
      );
      await _publishFailedTask(failedTask);
    } finally {
      _currentTask = null;
      _isProcessing = false;
      _notifyState();
      _processNext();
    }
  }

  Future<void> _publishFailedTask(GenerationTask failedTask) async {
    try {
      await _historyRepo.updateTask(failedTask);
    } catch (_) {
      // 持久化失败不能阻止 UI 收到任务终态，否则生成页会一直等待。
    }
    _taskController.add(failedTask);
  }

  void _notifyState() {
    _queueController.add(QueueState(
      isProcessing: _isProcessing,
      currentTask: _currentTask,
      pendingCount: _queue.length,
      pendingTasks: List.unmodifiable(_queue),
    ));
  }

  void dispose() {
    _queueController.close();
    _taskController.close();
  }
}

class QueueState {
  final bool isProcessing;
  final GenerationTask? currentTask;
  final int pendingCount;
  final List<GenerationTask> pendingTasks;

  const QueueState({
    required this.isProcessing,
    this.currentTask,
    required this.pendingCount,
    required this.pendingTasks,
  });
}
