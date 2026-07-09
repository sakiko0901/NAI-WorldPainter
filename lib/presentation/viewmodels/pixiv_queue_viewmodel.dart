import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:nai_huishi/core/services/pixiv_upload_queue_service.dart';
import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';

class PixivQueueViewModel extends ChangeNotifier {
  final PixivUploadQueueService _queue;
  late final StreamSubscription _sub;

  PixivQueueViewModel(this._queue) {
    _sub = _queue.stream.listen((_) {
      notifyListeners();
    });
  }

  List<PixivUploadTask> get tasks => _queue.tasks;
  bool get isPaused => _queue.isPaused;
  Duration? get cooldownRemaining => _queue.cooldownRemaining;

  void pause() => _queue.pause();
  void resume() => _queue.resume();
  void cancel(String id) => _queue.cancel(id);
  void remove(String id) => _queue.remove(id);
  void clearFinished() => _queue.clearFinished();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
