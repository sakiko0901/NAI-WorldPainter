import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 后台保活：在生成图像期间维持 wakelock + Android 前台服务通知，
/// 避免系统在锁屏或后台时杀掉应用导致任务中断。
///
/// 使用方式：在 [GenerationViewModel.generate] 开始处调用 [acquire]，
/// 全部任务完成（成功/失败/异常）后在 finally 中调用 [release]。
/// 内部维护引用计数，多次 acquire 可叠加；只有最后一次 release 才会真正停止。
class BackgroundKeepAliveService {
  BackgroundKeepAliveService._();
  static final BackgroundKeepAliveService instance =
      BackgroundKeepAliveService._();

  int _refCount = 0;
  bool _initialized = false;
  Future<void> _platformWork = Future.value();

  /// 初始化前台任务通道。app 启动时调用一次即可。
  Future<void> init() async {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'nai_huishi_generation',
        channelName: '图像生成',
        channelDescription: '后台执行图像生成任务',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  /// 立即登记保活引用，系统权限和服务启动在后台串行执行。
  void acquire({String? notificationText}) {
    _refCount++;
    if (_refCount == 1) {
      _schedule(() => _start(notificationText));
    } else if (notificationText != null) {
      updateNotification(notificationText);
    }
  }

  Future<void> _start(String? notificationText) async {
    if (_refCount == 0) return;
    await init();
    try {
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted && _refCount > 0) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}
    if (_refCount == 0) return;
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    if (_refCount == 0) return;
    if (await FlutterForegroundTask.isRunningService) {
      if (notificationText != null) {
        await FlutterForegroundTask.updateService(
            notificationText: notificationText);
      }
    } else if (_refCount > 0) {
      await FlutterForegroundTask.startService(
        serviceId: 5210,
        notificationTitle: 'NAI 绘世',
        notificationText: notificationText ?? '正在生成图像…',
      );
    }
  }

  void _schedule(Future<void> Function() operation) {
    _platformWork = _platformWork.then((_) async {
      try {
        await operation();
      } catch (_) {
        // 保活失败后继续处理后续的启动和释放。
      }
    });
  }

  /// 更新前台服务通知文案。
  void updateNotification(String text) {
    if (_refCount == 0) return;
    _schedule(() async {
      if (_refCount > 0) {
        await FlutterForegroundTask.updateService(notificationText: text);
      }
    });
  }

  /// 释放一次引用。引用归零后异步停止服务并解除 wakelock。
  void release() {
    if (_refCount == 0) return;
    _refCount--;
    if (_refCount != 0) return;
    _schedule(() async {
      if (_refCount != 0) return;
      try {
        await FlutterForegroundTask.stopService();
      } finally {
        await WakelockPlus.disable();
      }
    });
  }
}
