import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';
import 'package:nai_huishi/presentation/viewmodels/pixiv_queue_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class PixivQueuePage extends StatefulWidget {
  const PixivQueuePage({super.key});

  @override
  State<PixivQueuePage> createState() => _PixivQueuePageState();
}

class _PixivQueuePageState extends State<PixivQueuePage> {
  late final PixivQueueViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = sl<PixivQueueViewModel>();
    _vm.addListener(_onChange);
  }

  @override
  void dispose() {
    _vm.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tasks = _vm.tasks;
    final cd = _vm.cooldownRemaining;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pixiv 上传队列'),
        actions: [
          IconButton(
            icon: Icon(_vm.isPaused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill),
            tooltip: _vm.isPaused ? '继续' : '暂停',
            onPressed: () {
              if (_vm.isPaused) {
                _vm.resume();
                showFloatingToast(context, '队列已继续', icon: CupertinoIcons.play_fill);
              } else {
                _vm.pause();
                showFloatingToast(context, '队列已暂停', icon: CupertinoIcons.pause_fill);
              }
            },
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.clear_circled),
            tooltip: '清除已完成 / 失败 / 取消',
            onPressed: () {
              _vm.clearFinished();
              showFloatingToast(context, '已清理完成项', icon: CupertinoIcons.checkmark_circle);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (cd != null)
            _CooldownBar(isDark: isDark, remaining: cd),
          if (_vm.isPaused)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: const Color(0xFFFFB020).withValues(alpha: 0.18),
              child: const Text(
                '队列已暂停',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: tasks.isEmpty
                ? _EmptyHint(isDark: isDark)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    itemBuilder: (_, i) => _TaskCard(
                      task: tasks[i],
                      isDark: isDark,
                      onCancel: () => _vm.cancel(tasks[i].id),
                      onRemove: () => _vm.remove(tasks[i].id),
                    ),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: tasks.length,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CooldownBar extends StatelessWidget {
  final bool isDark;
  final Duration remaining;
  const _CooldownBar({required this.isDark, required this.remaining});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours.toString().padLeft(2, '0')}:$m:$s'
        : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: primary.withValues(alpha: isDark ? 0.16 : 0.1),
      child: Row(
        children: [
          Icon(CupertinoIcons.time, size: 16, color: primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('正在冷却中，剩余 ${_fmt(remaining)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final bool isDark;
  const _EmptyHint({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.tray, size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text('队列为空',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('在「上传到 Pixiv」页点击「加入队列」即可批量任务',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final PixivUploadTask task;
  final bool isDark;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  const _TaskCard({
    required this.task,
    required this.isDark,
    required this.onCancel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final canCancel = task.status == PixivUploadStatus.pending;
    final finished = task.status == PixivUploadStatus.completed ||
        task.status == PixivUploadStatus.failed ||
        task.status == PixivUploadStatus.canceled;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C21) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: isDark ? 0.06 : 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title.isEmpty ? '(无标题)' : task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                ),
              ),
              const SizedBox(width: 6),
              _StatusBadge(status: task.status),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(CupertinoIcons.photo_on_rectangle,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('${task.imagePaths.length} 张',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 10),
              Icon(CupertinoIcons.tag,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('${task.tags.length} 标签',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (task.isR18) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('R18',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700)),
                ),
              ],
              if (task.stripMetadata) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('LSB',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.amber,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          if (task.status == PixivUploadStatus.completed && task.illustId != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(CupertinoIcons.checkmark_seal_fill,
                    size: 13,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text('PID: ${task.illustId}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ],
          if (task.status == PixivUploadStatus.cooldown) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(CupertinoIcons.time,
                    size: 13, color: Color(0xFFFFB020)),
                const SizedBox(width: 4),
                const Text('上传成功，正在冷却…',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFB020))),
              ],
            ),
          ],
          if (task.error != null && task.error!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text(_formatTime(task.createdAt),
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
              const Spacer(),
              if (canCancel)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onCancel,
                  icon: const Icon(CupertinoIcons.xmark, size: 14),
                  label: const Text('取消', style: TextStyle(fontSize: 12)),
                ),
              if (finished)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onRemove,
                  icon: const Icon(CupertinoIcons.trash, size: 14),
                  label: const Text('移除', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    return '$mm-$dd $hh:$mi';
  }
}

class _StatusBadge extends StatelessWidget {
  final PixivUploadStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      PixivUploadStatus.pending => ('等待', Colors.blueGrey, CupertinoIcons.hourglass),
      PixivUploadStatus.uploading => ('上传中', Colors.blueAccent, CupertinoIcons.cloud_upload),
      PixivUploadStatus.cooldown => ('冷却中', const Color(0xFFFFB020), CupertinoIcons.time),
      PixivUploadStatus.completed => ('完成', Colors.green, CupertinoIcons.checkmark_circle_fill),
      PixivUploadStatus.failed => ('失败', Colors.redAccent, CupertinoIcons.exclamationmark_circle),
      PixivUploadStatus.canceled => ('已取消', Colors.grey, CupertinoIcons.xmark_circle),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
