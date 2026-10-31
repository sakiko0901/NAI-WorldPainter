import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/services/app_update_service.dart';
import 'package:nai_huishi/domain/entities/app_update.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';

/// The application owns the updater so downloads continue after this page closes.
class AppUpdatePage extends StatefulWidget {
  final AppUpdateService? service;

  const AppUpdatePage({super.key, this.service});

  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  late final AppUpdateService _service;
  bool _installFlowActive = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? sl<AppUpdateService>();
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作未能完成，请重试。')),
      );
    }
  }

  void _later() => Navigator.of(context).maybePop();

  Future<void> _installUpdate() async {
    if (_installFlowActive) return;
    _installFlowActive = true;
    try {
      await _service.installUpdate();
      if (!mounted || !_service.requiresUnsavedConfirmation) return;
      final unsavedWarning = _service.message?.trim();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('安装前保存工作区'),
          content: Text(
            [
              if (unsavedWarning?.isNotEmpty == true) unsavedWarning!,
              '请先保存重要图片、未发送的消息和附件。安装更新会关闭应用，'
                  '并清空临时遮罩、图层和撤销记录等未保存的内存编辑。'
                  '确认已保存后再继续安装。',
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              key: const ValueKey('app-update-save-first'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('返回保存'),
            ),
            FilledButton(
              key: const ValueKey('app-update-discard-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('已保存，继续安装'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed == true) {
        await _service.installUpdate(allowDiscardUnsaved: true);
      } else if (confirmed == false) {
        _later();
      }
    } finally {
      _installFlowActive = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('软件更新'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: _later,
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: StudioBackground()),
          SafeArea(
            top: false,
            child: BackdropGroup(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    key: const ValueKey('app-update-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _UpdateSelector(
                        service: _service,
                        select: () => (
                          _service.phase,
                          _service.message,
                          _service.manifest?.versionCode,
                          _service.installed?.versionCode,
                          _service.canCheckForUpdates,
                        ),
                        builder: (context, _) => _buildStatus(context),
                      ),
                      const SizedBox(height: 18),
                      _UpdateSelector(
                        service: _service,
                        // Native polling restores new model instances. Compare
                        // the visible values rather than their object identity.
                        select: () => (
                          _service.installed?.versionName,
                          _service.installed?.versionCode,
                          _service.manifest?.versionName,
                          _service.manifest?.versionCode,
                          _service.manifest?.publishedAt,
                          _service.manifest?.apk.sizeBytes,
                          _service.manifest?.releaseNotes,
                        ),
                        builder: (context, _) => _buildVersionDetails(context),
                      ),
                      const SizedBox(height: 18),
                      _UpdateSelector(
                        service: _service,
                        select: () => (
                          _service.autoCheckEnabled,
                          _service.lastCheckedAt,
                          _service.phase == UpdatePhase.unsupported,
                          _service.canCheckForUpdates,
                        ),
                        builder: (context, _) => _buildPreferences(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final phase = _service.phase;
    final ignored = phase == UpdatePhase.upToDate &&
        _service.manifest != null &&
        _service.installed != null &&
        _service.manifest!.versionCode > _service.installed!.versionCode;
    final title = switch (phase) {
      UpdatePhase.idle => '检查应用更新',
      UpdatePhase.checking => '正在检查更新',
      UpdatePhase.upToDate => ignored ? '已忽略此版本' : '已是最新版本',
      UpdatePhase.available => '发现新版本',
      UpdatePhase.downloading => '正在下载更新',
      UpdatePhase.verifying => '正在校验更新',
      UpdatePhase.ready => '更新已准备好',
      UpdatePhase.permissionRequired => '需要允许安装应用',
      UpdatePhase.awaitingInstall => '等待系统安装',
      UpdatePhase.failed => '更新未完成',
      UpdatePhase.unsupported =>
        _service.canCheckForUpdates ? '此更新不兼容当前设备' : '暂不支持应用内更新',
    };
    final description = switch (phase) {
      UpdatePhase.idle => '查看是否有可用的新版本。',
      UpdatePhase.checking => '正在获取最新版本信息，请稍候。',
      UpdatePhase.upToDate => ignored ? '此版本已忽略，仍可查看更新说明和发布页。' : '当前应用已是最新版本。',
      UpdatePhase.available => '下载完成后会校验安装包，由你确认安装。',
      UpdatePhase.downloading => '离开此页面后仍会继续下载。',
      UpdatePhase.verifying => '正在检查安装包的完整性，请稍候。',
      UpdatePhase.ready => '安装时应用可能会关闭，请先保存正在编辑的内容。',
      UpdatePhase.permissionRequired => '在系统设置中允许安装后，请返回本页，再次点击“立即安装”。',
      UpdatePhase.awaitingInstall => '请在系统安装界面完成操作。返回应用后会核对安装结果。',
      UpdatePhase.failed => '本次更新未能完成，请重试或前往发布页。',
      UpdatePhase.unsupported => _service.canCheckForUpdates
          ? '可重新检查其他兼容版本，或前往发布页查看。'
          : '当前平台或预览包暂不支持应用内更新，可前往发布页查看正式版本。',
    };
    final icon = switch (phase) {
      UpdatePhase.upToDate => CupertinoIcons.checkmark_shield,
      UpdatePhase.available => CupertinoIcons.arrow_down_circle,
      UpdatePhase.downloading => CupertinoIcons.arrow_down_to_line,
      UpdatePhase.verifying => CupertinoIcons.shield,
      UpdatePhase.ready => CupertinoIcons.checkmark_circle,
      UpdatePhase.permissionRequired => CupertinoIcons.lock_shield,
      UpdatePhase.awaitingInstall => CupertinoIcons.square_arrow_down,
      UpdatePhase.failed => CupertinoIcons.exclamationmark_circle,
      UpdatePhase.unsupported => CupertinoIcons.info_circle,
      _ => CupertinoIcons.arrow_2_circlepath,
    };
    return FrostedSurface(
      key: const ValueKey('app-update-status'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon,
                    size: 28,
                    color: phase == UpdatePhase.failed
                        ? colors.error
                        : colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(description, style: TextStyle(color: colors.onSurfaceVariant)),
          if (_service.message?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              _service.message!,
              key: const ValueKey('app-update-message'),
              style: TextStyle(
                color: phase == UpdatePhase.failed
                    ? colors.error
                    : colors.onSurfaceVariant,
              ),
            ),
          ],
          if (phase == UpdatePhase.downloading) ...[
            const SizedBox(height: 16),
            // Only this small region rebuilds for download byte notifications.
            RepaintBoundary(
              child: ListenableBuilder(
                listenable: _service,
                builder: (context, _) => _DownloadProgress(
                  download: _service.download,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          ..._buildActions(phase),
        ],
      ),
    );
  }

  List<Widget> _buildActions(UpdatePhase phase) {
    Widget primary(String label, String key, Future<void> Function() action) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: ValueKey(key),
          onPressed: () => _perform(action),
          child: Text(label, textAlign: TextAlign.center),
        ),
      );
    }

    Widget secondary(String label, String key, VoidCallback action) {
      return SizedBox(
        width: double.infinity,
        child: TextButton(
          key: ValueKey(key),
          onPressed: action,
          child: Text(label, textAlign: TextAlign.center),
        ),
      );
    }

    final actions = switch (phase) {
      UpdatePhase.idle || UpdatePhase.upToDate => [
          primary('检查更新', 'app-update-check', () => _service.checkForUpdates()),
        ],
      UpdatePhase.checking => <Widget>[
          const SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: null, child: Text('正在检查…')),
          ),
        ],
      UpdatePhase.available => [
          primary('下载更新', 'app-update-download', _service.startDownload),
          secondary('忽略此版本', 'app-update-ignore',
              () => _perform(_service.ignoreVersion)),
        ],
      UpdatePhase.downloading => [
          secondary('取消下载', 'app-update-cancel',
              () => _perform(_service.cancelDownload)),
        ],
      UpdatePhase.verifying => <Widget>[],
      UpdatePhase.ready => [
          primary('立即安装', 'app-update-install', _installUpdate),
          secondary('稍后', 'app-update-later', _later),
        ],
      UpdatePhase.permissionRequired => [
          primary('允许安装', 'app-update-permission', _installUpdate),
          secondary('稍后', 'app-update-later', _later),
        ],
      UpdatePhase.awaitingInstall => [
          primary('核对安装结果', 'app-update-refresh', _service.refresh),
        ],
      UpdatePhase.failed => [
          primary('重试', 'app-update-retry', () => _service.checkForUpdates()),
        ],
      UpdatePhase.unsupported => _service.canCheckForUpdates
          ? [
              primary('重新检查', 'app-update-recheck',
                  () => _service.checkForUpdates()),
            ]
          : <Widget>[],
    };
    if (phase == UpdatePhase.failed || phase == UpdatePhase.unsupported) {
      actions.add(secondary('打开发布页', 'app-update-release-fallback',
          () => _perform(_service.openReleasePage)));
    }
    return actions;
  }

  Widget _buildVersionDetails(BuildContext context) {
    final installed = _service.installed;
    final manifest = _service.manifest;
    return FrostedSurface(
      key: const ValueKey('app-update-details'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Detail(
            label: '当前版本',
            value: installed == null
                ? '暂不可用'
                : '${installed.versionName}（${installed.versionCode}）',
          ),
          if (manifest != null) ...[
            const Divider(height: 28),
            _Detail(
              label: '目标版本',
              value: '${manifest.versionName}（${manifest.versionCode}）',
            ),
            const SizedBox(height: 16),
            _Detail(label: '发布时间', value: _formatDate(manifest.publishedAt)),
            const SizedBox(height: 16),
            _Detail(
                label: '安装包大小', value: _formatBytes(manifest.apk.sizeBytes)),
            const Divider(height: 28),
            Text('更新说明', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            // Release notes are untrusted content. Display plain text only.
            SelectableText(
              manifest.releaseNotes.trim().isEmpty
                  ? '此版本未提供更新说明。'
                  : manifest.releaseNotes,
              key: const ValueKey('app-update-release-notes'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              key: const ValueKey('app-update-release'),
              onPressed: () => _perform(_service.openReleasePage),
              icon: const Icon(CupertinoIcons.arrow_up_right_square, size: 18),
              label: const Text('打开发布页'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreferences(BuildContext context) {
    return FrostedSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('app-update-auto-check'),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            title: const Text('自动检查更新'),
            subtitle: const Text('每天使用应用时静默检查，在工具页提示新版本'),
            value: _service.autoCheckEnabled,
            onChanged: _service.phase == UpdatePhase.unsupported &&
                    !_service.canCheckForUpdates
                ? null
                : (enabled) =>
                    _perform(() => _service.setAutoCheckEnabled(enabled)),
          ),
          if (_service.lastCheckedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Text(
                '上次检查：${_formatDate(_service.lastCheckedAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;

  const _Detail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  final AppUpdateDownload? download;

  const _DownloadProgress({required this.download});

  @override
  Widget build(BuildContext context) {
    final received = download?.downloadedBytes ?? 0;
    final total = download?.totalBytes ?? 0;
    final progress = download?.progress ?? 0;
    final percent = (progress.clamp(0.0, 1.0) * 100).floor();
    return Semantics(
      label: '更新下载进度',
      value: '$percent%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            key: const ValueKey('app-update-progress'),
            value: progress.clamp(0.0, 1.0),
            minHeight: 5,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 10),
          Text(total > 0
              ? '$percent% · ${_formatBytes(received)} / ${_formatBytes(total)}'
              : '${_formatBytes(received)} · 等待下载进度'),
        ],
      ),
    );
  }
}

/// Filters progress ticks so the surrounding glass surfaces stay unchanged.
class _UpdateSelector<T> extends StatefulWidget {
  final AppUpdateService service;
  final T Function() select;
  final Widget Function(BuildContext, T) builder;

  const _UpdateSelector({
    required this.service,
    required this.select,
    required this.builder,
  });

  @override
  State<_UpdateSelector<T>> createState() => _UpdateSelectorState<T>();
}

class _UpdateSelectorState<T> extends State<_UpdateSelector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select();
    widget.service.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _UpdateSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_onChanged);
      widget.service.addListener(_onChanged);
    }
    _value = widget.select();
  }

  void _onChanged() {
    final value = widget.select();
    if (value != _value) setState(() => _value = value);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDate(DateTime value) {
  final date = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}
