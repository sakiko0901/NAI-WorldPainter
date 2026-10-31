import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';

import 'package:nai_huishi/data/datasources/local/pixiv_image_cloaker.dart';
import 'package:nai_huishi/data/datasources/local/pixiv_settings_local_datasource.dart';
import 'package:nai_huishi/data/datasources/remote/pixiv_api_service.dart';
import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';

/// Pixiv 上传队列单例：
/// - 顺序处理任务
/// - 上传成功后按 settings.cooldownMinutes ±5 min 随机等待
/// - 冷却 / 鉴权失败抛对应异常 → 标记失败
/// - 不持久化（进程退出清空）
class PixivUploadQueueService {
  final PixivApiService _api;
  final PixivSettingsLocalDatasource _settings;
  final PixivImageCloaker _cloaker;
  final AppUpdateInstallGuard? _updateGuard;

  final List<PixivUploadTask> _tasks = [];
  final StreamController<List<PixivUploadTask>> _ctrl =
      StreamController.broadcast();
  final Random _random = Random();

  bool _processing = false;
  bool _paused = false;
  Timer? _cooldownTimer;
  Duration? _cooldownRemaining;
  Timer? _cooldownTick;

  PixivUploadQueueService(this._api, this._settings, this._cloaker,
      {AppUpdateInstallGuard? updateGuard})
      : _updateGuard = updateGuard {
    _updateGuard?.register(
        this,
        () => _processing ||
                _tasks.any((task) =>
                    task.status == PixivUploadStatus.pending ||
                    task.status == PixivUploadStatus.uploading)
            ? 'Pixiv 上传任务尚未完成'
            : null);
  }

  Stream<List<PixivUploadTask>> get stream => _ctrl.stream;
  List<PixivUploadTask> get tasks => List.unmodifiable(_tasks);
  bool get isPaused => _paused;
  Duration? get cooldownRemaining => _cooldownRemaining;

  void enqueue(PixivUploadTask task) {
    if (_updateGuard?.isInstalling ?? false) {
      throw StateError('正在安装更新，请稍后上传');
    }
    _tasks.add(task);
    _emit();
    _maybeStart();
  }

  void cancel(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final cur = _tasks[i];
    if (cur.status == PixivUploadStatus.pending) {
      _tasks[i] = cur.copyWith(status: PixivUploadStatus.canceled);
      _emit();
    } else if (cur.status == PixivUploadStatus.completed ||
        cur.status == PixivUploadStatus.failed ||
        cur.status == PixivUploadStatus.canceled) {
      _tasks.removeAt(i);
      _emit();
    }
  }

  void remove(String id) {
    _tasks.removeWhere((t) => t.id == id);
    _emit();
  }

  void clearFinished() {
    _tasks.removeWhere((t) =>
        t.status == PixivUploadStatus.completed ||
        t.status == PixivUploadStatus.canceled ||
        t.status == PixivUploadStatus.failed);
    _emit();
  }

  void pause() {
    _paused = true;
    _emit();
  }

  void resume() {
    _paused = false;
    _emit();
    _maybeStart();
  }

  // ── 内部 ──
  void _emit() {
    if (!_ctrl.isClosed) _ctrl.add(List.unmodifiable(_tasks));
  }

  void _maybeStart() {
    if (_processing || _paused) return;
    final next = _tasks.firstWhere(
      (t) => t.status == PixivUploadStatus.pending,
      orElse: () => _empty,
    );
    if (identical(next, _empty)) return;
    _processing = true;
    _runOne(next.id).whenComplete(() {
      _processing = false;
      _maybeStart();
    });
  }

  Future<void> _runOne(String id) async {
    final settings = _settings.load();

    // mark uploading
    _update(
        id,
        (t) =>
            t.copyWith(status: PixivUploadStatus.uploading, clearError: true));

    PixivUploadTask? current = _findById(id);
    if (current == null) return;

    // 1. 隐写擦除
    var imagesToUpload = current.imagePaths;
    if (current.stripMetadata) {
      try {
        final cloaked = <String>[];
        for (final path in current.imagePaths) {
          final out = await _cloaker.cloak(path, junkText: settings.junkText);
          cloaked.add(out);
        }
        imagesToUpload = cloaked;
      } catch (e) {
        debugPrint('[PixivQueue] 隐写失败: $e');
        _update(
            id,
            (t) => t.copyWith(
                status: PixivUploadStatus.failed, error: '隐写擦除失败: $e'));
        return;
      }
    }

    // 2. 上传
    try {
      final replaced = current.copyWith();
      final illustId = await _api.uploadIllustration(
        settings: settings,
        task: PixivUploadTask(
          id: replaced.id,
          imagePaths: imagesToUpload,
          title: replaced.title,
          caption: replaced.caption,
          tags: replaced.tags,
          isR18: replaced.isR18,
          allowTagEdit: replaced.allowTagEdit,
          stripMetadata: replaced.stripMetadata,
          createdAt: replaced.createdAt,
        ),
      );
      _update(
          id,
          (t) => t.copyWith(
              status: PixivUploadStatus.cooldown,
              illustId: illustId,
              completedAt: DateTime.now(),
              clearError: true));
      await _doCooldown(id, settings.cooldownMinutes);
      _update(
          id,
          (t) => t.copyWith(
              status: PixivUploadStatus.completed, clearCooldown: true));
    } on PixivCooldownException catch (e) {
      _update(
          id,
          (t) => t.copyWith(
              status: PixivUploadStatus.failed, error: '投稿冷却：${e.message}'));
    } on PixivAuthException catch (e) {
      _update(
          id,
          (t) => t.copyWith(
              status: PixivUploadStatus.failed, error: '鉴权失败：${e.message}'));
    } on PixivUploadException catch (e) {
      _update(
          id,
          (t) =>
              t.copyWith(status: PixivUploadStatus.failed, error: e.message));
    } catch (e) {
      _update(
          id,
          (t) =>
              t.copyWith(status: PixivUploadStatus.failed, error: '上传异常: $e'));
    }
  }

  Future<void> _doCooldown(String id, int minutes) async {
    final base = minutes.clamp(1, 999);
    final low = (base - 5).clamp(1, 999);
    final high = (base + 5).clamp(low + 1, 999 * 2);
    final seconds = (low * 60) + _random.nextInt((high - low) * 60 + 1);
    final until = DateTime.now().add(Duration(seconds: seconds));
    _update(id, (t) => t.copyWith(cooldownUntil: until));

    _cooldownRemaining = Duration(seconds: seconds);
    _cooldownTick?.cancel();
    _cooldownTick = Timer.periodic(const Duration(seconds: 1), (_) {
      final remain = until.difference(DateTime.now());
      if (remain.isNegative) {
        _cooldownRemaining = null;
        _cooldownTick?.cancel();
      } else {
        _cooldownRemaining = remain;
      }
      _emit();
    });

    final completer = Completer<void>();
    _cooldownTimer = Timer(Duration(seconds: seconds), () {
      _cooldownTick?.cancel();
      _cooldownRemaining = null;
      completer.complete();
    });
    await completer.future;
  }

  PixivUploadTask? _findById(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    return i < 0 ? null : _tasks[i];
  }

  void _update(String id, PixivUploadTask Function(PixivUploadTask) f) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _tasks[i] = f(_tasks[i]);
    _emit();
  }

  // sentinel
  static final _empty = PixivUploadTask(
    id: '__empty__',
    imagePaths: const [],
    title: '',
    caption: '',
    tags: const [],
    isR18: false,
    allowTagEdit: false,
    stripMetadata: false,
    createdAt: DateTime(0),
  );

  void dispose() {
    _updateGuard?.unregister(this);
    _cooldownTimer?.cancel();
    _cooldownTick?.cancel();
    _ctrl.close();
  }
}
