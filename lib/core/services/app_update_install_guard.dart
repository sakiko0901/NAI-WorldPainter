import 'package:flutter/foundation.dart';

/// Coordinates the short period in which Android may replace this process.
/// Checks are evaluated immediately before installation, never cached from UI.
class AppUpdateInstallGuard extends ChangeNotifier {
  final Map<Object, String? Function()> _checks = {};
  final Map<Object, String? Function()> _unsavedChecks = {};
  final Map<Object, String> _activities = {};
  bool _isInstalling = false;

  bool get isInstalling => _isInstalling;

  void register(Object owner, String? Function() check) {
    _checks[owner] = check;
  }

  void unregister(Object owner) => _checks.remove(owner);

  void registerUnsaved(Object owner, String? Function() check) {
    _unsavedChecks[owner] = check;
  }

  void unregisterUnsaved(Object owner) => _unsavedChecks.remove(owner);

  String? get unsavedWarning {
    final messages = <String>{};
    for (final check in _unsavedChecks.values) {
      try {
        final message = check();
        if (message != null && message.isNotEmpty) messages.add(message);
      } catch (_) {
        messages.add('部分临时工作区的保存状态无法确认');
      }
    }
    return messages.isEmpty ? null : messages.join('；');
  }

  /// The returned callback releases this task even if its page is disposed.
  VoidCallback beginActivity(String description) {
    if (_isInstalling) throw StateError('正在安装更新，请稍后重试');
    final token = Object();
    _activities[token] = description;
    return () => _activities.remove(token);
  }

  String? get blockReason {
    if (_isInstalling) return '正在准备安装更新，请稍候';
    final reasons = <String>{..._activities.values};
    for (final check in _checks.values) {
      try {
        final reason = check();
        if (reason != null && reason.isNotEmpty) reasons.add(reason);
      } catch (_) {
        reasons.add('暂时无法确认当前任务状态，请稍后重试');
      }
    }
    return reasons.isEmpty ? null : reasons.join('；');
  }

  /// Synchronous acquisition closes the gap between checking and launching.
  bool tryBeginInstall({bool allowDiscardUnsaved = false}) {
    if (blockReason != null ||
        (!allowDiscardUnsaved && unsavedWarning != null)) {
      return false;
    }
    _isInstalling = true;
    notifyListeners();
    return true;
  }

  void endInstall() {
    if (!_isInstalling) return;
    _isInstalling = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _checks.clear();
    _unsavedChecks.clear();
    _activities.clear();
    super.dispose();
  }
}
