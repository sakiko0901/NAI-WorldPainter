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

  final List<_QueuedTask> _queue = [];
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
    _queue.add(_QueuedTask(task, persistHistory: true));
    _notifyState();
    _processNext();
  }

  /// 入队但不写入历史，供分块重绘等内部编排任务使用。
  Future<void> enqueueTransient(GenerationTask task) async {
    _queue.add(_QueuedTask(task, persistHistory: false));
    _notifyState();
    _processNext();
  }

  /// 入队内部任务并等待终态，供漫画等项目级编排安全关联候选结果。
  Future<GenerationTask> enqueueTransientAndWait(GenerationTask task) {
    final completion = Completer<GenerationTask>();
    _queue.add(_QueuedTask(
      task,
      persistHistory: false,
      completion: completion,
    ));
    _notifyState();
    _processNext();
    return completion.future;
  }

  /// 批量入队
  Future<void> enqueueAll(List<GenerationTask> tasks) async {
    _queue.addAll(tasks.map((task) => _QueuedTask(task, persistHistory: true)));
    _notifyState();
    _processNext();
  }

  /// 取消排队中的任务（不能取消正在执行的）
  bool cancel(String taskId) {
    final index = _queue.indexWhere((entry) => entry.task.taskId == taskId);
    if (index >= 0) {
      final removed = _queue.removeAt(index);
      removed.completion?.complete(removed.task.copyWith(
        status: 'failed',
        errorMessage: '任务已取消',
        completedAt: DateTime.now(),
      ));
      _notifyState();
      return true;
    }
    return false;
  }

  /// 清空队列
  void clear() {
    for (final queuedTask in _queue) {
      queuedTask.completion?.complete(queuedTask.task.copyWith(
        status: 'failed',
        errorMessage: '任务已取消',
        completedAt: DateTime.now(),
      ));
    }
    _queue.clear();
    _notifyState();
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    final queuedTask = _queue.removeAt(0);
    _currentTask = queuedTask.task;
    _notifyState();

    try {
      final generatingTask = _currentTask!.copyWith(status: 'generating');
      if (queuedTask.persistHistory) {
        await _historyRepo.updateTask(generatingTask);
      }
      _taskController.add(generatingTask);

      final completedTask =
          await _generationRepo.submitGeneration(generatingTask);
      if (queuedTask.persistHistory) {
        await _historyRepo.updateTask(completedTask);
      }
      _taskController.add(completedTask);
      queuedTask.completion?.complete(completedTask);
    } on ApiException catch (e) {
      final failedTask = _currentTask!.copyWith(
        status: 'failed',
        errorMessage: e.message,
        completedAt: DateTime.now(),
      );
      await _publishFailedTask(failedTask, queuedTask.persistHistory);
      queuedTask.completion?.complete(failedTask);
    } catch (e) {
      final failedTask = _currentTask!.copyWith(
        status: 'failed',
        errorMessage: e.toString(),
        completedAt: DateTime.now(),
      );
      await _publishFailedTask(failedTask, queuedTask.persistHistory);
      queuedTask.completion?.complete(failedTask);
    } finally {
      _currentTask = null;
      _isProcessing = false;
      _notifyState();
      _processNext();
    }
  }

  Future<void> _publishFailedTask(
    GenerationTask failedTask,
    bool persistHistory,
  ) async {
    try {
      if (persistHistory) {
        await _historyRepo.updateTask(failedTask);
      }
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
      pendingTasks: List.unmodifiable(_queue.map((entry) => entry.task)),
    ));
  }

  void dispose() {
    _queueController.close();
    _taskController.close();
  }
}

class _QueuedTask {
  final GenerationTask task;
  final bool persistHistory;
  final Completer<GenerationTask>? completion;

  const _QueuedTask(
    this.task, {
    required this.persistHistory,
    this.completion,
  });
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
