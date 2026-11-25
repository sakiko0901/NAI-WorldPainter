import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';

class ToolExecutionTimeline extends StatelessWidget {
  final List<AgentEvent> timeline;
  final Listenable? updates;
  final List<AgentEvent>? Function()? readTimeline;

  const ToolExecutionTimeline({
    super.key,
    required this.timeline,
    this.updates,
    this.readTimeline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);
    final events = _latestEvents(timeline);
    if (events.isEmpty) return const SizedBox.shrink();

    AgentEvent? running;
    for (final event in events.reversed) {
      if (event.status == 'running') {
        running = event;
        break;
      }
    }
    final latest = running ?? events.last;
    final latestTitle = _operationTitle(latest.toolName);
    final summary = running != null
        ? '正在$latestTitle…（共 ${events.length} 项）'
        : '操作过程 · ${events.length} 项 · $latestTitle';

    return InkWell(
      key: const ValueKey('chat-operations-summary'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showDetails(context, selected: latest),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (running != null)
                SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: muted,
                  ),
                )
              else
                Icon(Icons.schedule_rounded, size: 15, color: muted),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: muted,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 16, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context, {AgentEvent? selected}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (context) => _OperationDetailsSheet(
          key: const ValueKey('chat-operations-sheet'),
          initialTimeline: timeline,
          updates: updates,
          readTimeline: readTimeline,
          selected: selected,
        ),
      );
}

class _OperationDetailsSheet extends StatefulWidget {
  final List<AgentEvent> initialTimeline;
  final Listenable? updates;
  final List<AgentEvent>? Function()? readTimeline;
  final AgentEvent? selected;

  const _OperationDetailsSheet({
    super.key,
    required this.initialTimeline,
    required this.updates,
    required this.readTimeline,
    required this.selected,
  });

  @override
  State<_OperationDetailsSheet> createState() => _OperationDetailsSheetState();
}

class _OperationDetailsSheetState extends State<_OperationDetailsSheet> {
  final _selectedKey = GlobalKey();
  late List<AgentEvent> _timeline;

  @override
  void initState() {
    super.initState();
    _timeline = widget.readTimeline?.call() ?? widget.initialTimeline;
    widget.updates?.addListener(_updateTimeline);
    if (widget.selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _selectedKey.currentContext;
        if (target != null) Scrollable.ensureVisible(target, alignment: .12);
      });
    }
  }

  @override
  void dispose() {
    widget.updates?.removeListener(_updateTimeline);
    super.dispose();
  }

  void _updateTimeline() {
    final timeline = widget.readTimeline?.call();
    if (timeline != null && !identical(timeline, _timeline)) {
      setState(() => _timeline = timeline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = _latestEvents(_timeline);
    final selected = widget.selected;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      '操作过程',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭操作过程',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SelectionArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 18, 24, 24),
                  child: Column(
                    children: [
                      for (final (index, event) in events.indexed)
                        _TimelineEntry(
                          key: selected != null && _sameCall(selected, event)
                              ? _selectedKey
                              : null,
                          event: event,
                          first: index == 0,
                          last: index == events.length - 1,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final AgentEvent event;
  final bool first;
  final bool last;

  const _TimelineEntry({
    super.key,
    required this.event,
    required this.first,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = _statusColor(event.status, colors);
    final result = event.result?.displayText.trim() ?? '';
    return Stack(
      children: [
        if (!first || !last)
          PositionedDirectional(
            start: 4.5,
            top: first ? 10 : 0,
            bottom: last ? null : 0,
            width: 1,
            height: last ? 10 : null,
            child: ColoredBox(color: colors.outlineVariant),
          ),
        PositionedDirectional(
          start: 1,
          top: 6,
          child: DecoratedBox(
            decoration:
                BoxDecoration(color: statusColor, shape: BoxShape.circle),
            child: const SizedBox.square(dimension: 8),
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(start: 23, bottom: last ? 0 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _operationTitle(event.toolName),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_statusLabel(event.status),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: statusColor)),
                ],
              ),
              if (result.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(result, style: theme.textTheme.bodyMedium),
                ),
              if (event.arguments.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 3),
                  child: Text('输入', style: theme.textTheme.labelMedium),
                ),
                Text(
                  const JsonEncoder.withIndent('  ').convert(event.arguments),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

List<AgentEvent> _latestEvents(List<AgentEvent> timeline) {
  final calls = <Object, (DateTime, int, AgentEvent)>{};
  for (final (index, event) in timeline.indexed) {
    final key = event.toolCallId.isEmpty ? index : _callKey(event);
    final first = calls[key];
    calls[key] = (first?.$1 ?? event.createdAt, first?.$2 ?? index, event);
  }
  final sorted = calls.values.toList()
    ..sort((a, b) {
      final dateOrder = a.$1.compareTo(b.$1);
      return dateOrder != 0 ? dateOrder : a.$2.compareTo(b.$2);
    });
  return [for (final (_, _, event) in sorted) event];
}

(String, int) _callKey(AgentEvent event) =>
    (event.toolCallId, event.createdAt.millisecondsSinceEpoch);

bool _sameCall(AgentEvent a, AgentEvent b) =>
    identical(a, b) || (a.toolCallId.isNotEmpty && _callKey(a) == _callKey(b));

String _operationTitle(String name) => switch (name) {
      'read_current_prompts' => '读取提示词框',
      'write_prompt' => '写入提示词',
      'remove_character' => '移除角色',
      'clear_characters' => '清空角色',
      'search_danbooru' => '搜索标签',
      'read_comic_panel_prompt' => '读取漫画分镜提示词',
      'write_comic_panel_prompt' => '写入漫画分镜提示词',
      'generate_image' => '生成图片',
      'upscale_image' => '放大图片',
      'save_image' => '保存图片',
      'upload_to_pixiv' => '上传到 Pixiv',
      'get_memories' => '读取记忆',
      'save_memory' => '保存记忆',
      'ask_user' => '询问用户',
      '' => '工具操作',
      _ => name,
    };

String _statusLabel(String status) => switch (status) {
      'pending' => '等待',
      'running' => '执行中',
      'done' => '完成',
      'error' => '失败',
      'cancelled' => '已取消',
      'awaiting_confirm' => '待确认',
      'awaiting_user' => '等待回答',
      _ => status,
    };

Color _statusColor(String status, ColorScheme colors) => switch (status) {
      'running' => colors.primary,
      'error' => colors.error,
      'awaiting_confirm' || 'awaiting_user' => colors.secondary,
      _ => colors.onSurfaceVariant,
    };
