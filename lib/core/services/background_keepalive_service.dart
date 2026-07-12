import 'dart:async';

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

  /// 获取一次保活引用。第一次调用时启动前台服务并持有 wakelock。
  Future<void> acquire({String? notificationText}) async {
    if (!_initialized) {
      await init();
    }
    _refCount++;
    if (_refCount == 1) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
      try {
        // Android 13+ 需要 POST_NOTIFICATIONS 运行时权限，否则前台服务起不来。
        final notif = await FlutterForegroundTask.checkNotificationPermission();
        if (notif != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
      } catch (_) {}
      try {
        final isRunning = await FlutterForegroundTask.isRunningService;
        if (!isRunning) {
          await FlutterForegroundTask.startService(
            serviceId: 5210,
            notificationTitle: 'NAI 绘世',
            notificationText: notificationText ?? '正在生成图像…',
          );
          // 等待服务真的就绪，避免 acquire 返回时前台服务还没起来导致后台立刻被杀。
          for (int i = 0; i < 20; i++) {
            if (await FlutterForegroundTask.isRunningService) break;
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } else if (notificationText != null) {
          await FlutterForegroundTask.updateService(
              notificationText: notificationText);
        }
      } catch (_) {
        // 前台服务启动失败不阻塞生成流程。
      }
    } else if (notificationText != null) {
      try {
        await FlutterForegroundTask.updateService(
            notificationText: notificationText);
      } catch (_) {}
    }
  }

  /// 更新前台服务通知文案（不影响引用计数）。
  Future<void> updateNotification(String text) async {
    if (_refCount <= 0) return;
    try {
      await FlutterForegroundTask.updateService(notificationText: text);
    } catch (_) {}
  }

  /// 释放一次引用。当引用归零时关闭前台服务并解除 wakelock。
  Future<void> release() async {
    if (_refCount <= 0) return;
    _refCount--;
    if (_refCount == 0) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }
}
