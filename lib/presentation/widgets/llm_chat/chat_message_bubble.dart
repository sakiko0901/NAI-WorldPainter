import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart' show showFloatingToast;
import 'package:nai_huishi/presentation/widgets/fullscreen_image_preview.dart';

class ChatMessageBubble extends StatefulWidget {
  final LlmMessage message;
  final int messageIndex;
  final VoidCallback? onRetry;
  final void Function(String newText)? onEditAndResend;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.messageIndex,
    this.onRetry,
    this.onEditAndResend,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  bool _menuVisible = false;

  LlmMessage get message => widget.message;
  bool get isUser => message.role == LlmMessageRole.user;

  String get _textForCopy =>
      message.content.replaceAll(RegExp(r'\n\[图片\]$'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasImage = message.imageBase64 != null ||
        (message.imagePath != null && File(message.imagePath!).existsSync());
    final hasText = message.content.trim().isNotEmpty;
    final hasTimeline = !isUser &&
        message.agentTimeline != null &&
        message.agentTimeline!.isNotEmpty;
    final isPlaceholder = !isUser && !hasText && !hasTimeline && !hasImage;

    Widget bubble = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? theme.colorScheme.primary
                          .withValues(alpha: isDark ? 0.18 : 0.14)
                      : isDark
                          ? const Color(0xFF1C1C21).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasImage)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () {
                            final path = (message.imagePath != null &&
                                    File(message.imagePath!).existsSync())
                                ? message.imagePath
                                : null;
                            showFullscreenImagePreview(context,
                                imagePath: path);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: message.imagePath != null &&
                                    File(message.imagePath!).existsSync()
                                ? Image.file(
                                    File(message.imagePath!),
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  )
                                : Image.memory(
                                    base64Decode(message.imageBase64!),
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                          ),
                        ),
                      ),
                    if (hasTimeline)
                      Padding(
                        padding: EdgeInsets.only(bottom: hasText ? 8 : 0),
                        child: ToolExecutionTimeline(
                            timeline: message.agentTimeline!),
                      ),
                    if (hasText)
                      isUser
                          ? _TapDetector(
                              onTap: () => setState(
                                  () => _menuVisible = !_menuVisible),
                              child: SelectableText(
                                message.content.trim(),
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: theme.colorScheme.onSurface,
                                ),
                                contextMenuBuilder: (context,
                                    editableTextState) {
                                  return AdaptiveTextSelectionToolbar
                                      .editableText(
                                    editableTextState: editableTextState,
                                  );
                                },
                              ),
                            )
                          : SelectableText(
                              message.content.trim(),
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                    if (isPlaceholder)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Agent 思考中…',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!(isUser &&
        (widget.onRetry != null || widget.onEditAndResend != null))) {
      return bubble;
    }

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        if (_menuVisible) ...[
          const SizedBox(height: 4),
          _buildMenuButtons(context),
        ],
      ],
    );
  }

  Widget _buildMenuButtons(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onEditAndResend != null) ...[
          _MenuIconButton(
            icon: CupertinoIcons.pencil,
            tooltip: '编辑',
            color: theme.colorScheme.primary,
            onTap: () {
              setState(() => _menuVisible = false);
              _showEditDialog(context);
            },
          ),
          const SizedBox(width: 4),
        ],
        if (widget.onRetry != null) ...[
          _MenuIconButton(
            icon: CupertinoIcons.arrow_clockwise,
            tooltip: '重试',
            color: theme.colorScheme.primary,
            onTap: () {
              setState(() => _menuVisible = false);
              widget.onRetry!();
            },
          ),
          const SizedBox(width: 4),
        ],
        _MenuIconButton(
          icon: CupertinoIcons.doc_on_doc,
          tooltip: '整段复制',
          color: theme.colorScheme.primary,
          onTap: () {
            setState(() => _menuVisible = false);
            Clipboard.setData(ClipboardData(text: _textForCopy));
            showFloatingToast(context, '已复制');
          },
        ),
      ],
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: _textForCopy);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          minLines: 1,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '修改消息内容…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onEditAndResend?.call(controller.text.trim());
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }
}

/// 用 Listener 监听原始指针的"短按单击"——不参与手势竞技场，
/// 永远不会被 SelectableText 击败。长按（>300ms）时主动退让，
/// 让 SelectableText 的长按选区识别器接管。
class _TapDetector extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TapDetector({required this.onTap, required this.child});

  @override
  State<_TapDetector> createState() => _TapDetectorState();
}

class _TapDetectorState extends State<_TapDetector> {
  Offset? _downPosition;
  DateTime? _downTime;
  bool _longPressed = false;

  static const Duration _longPressThreshold = Duration(milliseconds: 300);
  static const double _maxDragDistance = 20.0;

  void _onPointerDown(PointerDownEvent event) {
    _downPosition = event.position;
    _downTime = DateTime.now();
    _longPressed = false;
  }

  void _onPointerUp(PointerUpEvent event) {
    final downPos = _downPosition;
    final downT = _downTime;
    _downPosition = null;
    _downTime = null;
    if (downPos == null || downT == null) return;
    if (_longPressed) {
      _longPressed = false;
      return; // 长按已发生，让 SelectableText 处理选区，不当单击
    }
    final distance = (event.position - downPos).distance;
    final elapsed = DateTime.now().difference(downT);
    if (distance < _maxDragDistance &&
        elapsed < _longPressThreshold) {
      widget.onTap(); // 短按 = 单击 = 弹菜单
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final downPos = _downPosition;
    if (downPos == null) return;
    final distance = (event.position - downPos).distance;
    if (distance >= _maxDragDistance) {
      // 拖动超过阈值，可能是选区拖动，放弃单击判定
      _downPosition = null;
      _downTime = null;
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _downPosition = null;
    _downTime = null;
    _longPressed = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerMove: _onPointerMove,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}

/// 图标按钮（无文字），半透明圆形背景。
class _MenuIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _MenuIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

/// Agent 工具调用时间线：按轮次分组渲染 List<AgentEvent>。
/// 每轮用可折叠的 _RoundBlock 包裹，单工具轮默认展开，多工具轮默认折叠。
class ToolExecutionTimeline extends StatelessWidget {
  final List<AgentEvent> timeline;
  const ToolExecutionTimeline({super.key, required this.timeline});

  /// 按"轮次"分组：每个 status='pending' 事件开启新一轮。
  /// 同一轮 LLM 可能并行发出多个 tool_calls，所以同一轮可有多个 pending + 对应 running/done。
  static List<List<AgentEvent>> _groupByRound(List<AgentEvent> events) {
    final rounds = <List<AgentEvent>>[];
    List<AgentEvent>? current;
    for (final e in events) {
      if (e.status == 'pending' && current != null && current.isNotEmpty) {
        rounds.add(current);
        current = null;
      }
      current ??= <AgentEvent>[];
      current.add(e);
    }
    if (current != null && current.isNotEmpty) rounds.add(current);
    return rounds;
  }

  @override
  Widget build(BuildContext context) {
    final rounds = _groupByRound(timeline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < rounds.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _RoundBlock(
              roundIndex: i + 1,
              events: rounds[i],
            ),
          ),
      ],
    );
  }
}

/// 单轮工具调用块：标题"第 N 轮 · X 个工具 · 状态摘要"，可折叠。
class _RoundBlock extends StatefulWidget {
  final int roundIndex;
  final List<AgentEvent> events;
  const _RoundBlock({required this.roundIndex, required this.events});

  @override
  State<_RoundBlock> createState() => _RoundBlockState();
}

class _RoundBlockState extends State<_RoundBlock> {
  late bool _expanded = widget.events.length <= 1;

  String _statusSummary() {
    final hasError = widget.events.any((e) => e.status == 'error');
    if (hasError) return '失败';
    final hasRunning = widget.events.any((e) =>
        e.status == 'running' || e.status == 'pending' || e.status == 'awaiting_confirm');
    if (hasRunning) return '执行中';
    final allDone = widget.events.every((e) =>
        e.status == 'done' || e.status == 'cancelled');
    if (allDone) return '已完成';
    return '执行中';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final summary = _statusSummary();
    final summaryColor = summary == '失败'
        ? Colors.redAccent
        : summary == '已完成'
            ? Colors.greenAccent.shade400
            : const Color(0xFF7AB8F5);

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.25)
            : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? CupertinoIcons.chevron_down
                        : CupertinoIcons.chevron_right,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '第 ${widget.roundIndex} 轮',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· ${widget.events.length} 个工具',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: summaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      summary,
                      style: TextStyle(
                        fontSize: 10,
                        color: summaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _expanded ? '收起' : '展开',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final event in widget.events) _EventRow(event: event),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final AgentEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final (icon, color, label) = _statusVisual(context);

    final argsJson = event.arguments.isEmpty
        ? ''
        : const JsonEncoder.withIndent('  ').convert(event.arguments);
    final resultText = event.result?.displayText ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.3)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon,
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        event.toolName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  if (argsJson.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        argsJson,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (resultText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        resultText,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Widget, Color, String) _statusVisual(BuildContext context) {
    switch (event.status) {
      case 'pending':
        return (
          Icon(CupertinoIcons.clock, size: 12, color: Colors.grey),
          Colors.grey,
          '等待',
        );
      case 'running':
        return (
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.4,
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFF7AB8F5),
              ),
            ),
          ),
          const Color(0xFF7AB8F5),
          '执行中',
        );
      case 'done':
        return (
          Icon(CupertinoIcons.checkmark_seal_fill,
              size: 12, color: Colors.greenAccent.shade400),
          Colors.greenAccent.shade400,
          '完成',
        );
      case 'error':
        return (
          Icon(CupertinoIcons.xmark_octagon_fill,
              size: 12, color: Colors.redAccent),
          Colors.redAccent,
          '失败',
        );
      case 'cancelled':
        return (
          Icon(CupertinoIcons.minus_circle_fill,
              size: 12, color: Colors.orangeAccent),
          Colors.orangeAccent,
          '已取消',
        );
      case 'awaiting_confirm':
        return (
          Icon(CupertinoIcons.question_circle_fill,
              size: 12, color: Colors.amber),
          Colors.amber,
          '待确认',
        );
      default:
        return (
          Icon(CupertinoIcons.circle, size: 12, color: Colors.grey),
          Colors.grey,
          event.status,
        );
    }
  }
}
