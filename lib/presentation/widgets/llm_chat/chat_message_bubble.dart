import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/domain/agents/agent_event.dart';
import 'package:nai_huishi/domain/entities/llm_interaction.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart'
    show showFloatingToast;
import 'package:nai_huishi/presentation/widgets/fullscreen_image_preview.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_markdown_text.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_operation_timeline.dart';

class ChatMessageBubble extends StatefulWidget {
  final LlmMessage message;
  final int messageIndex;
  final VoidCallback? onRetry;
  final VoidCallback? onBranch;
  final Listenable? operationUpdates;
  final List<AgentEvent>? Function()? readOperations;
  final VoidCallback? onUndoPrompt;
  final VoidCallback? onReturnToParent;
  final void Function(String newText)? onEditAndResend;
  final void Function(String? optionId, String? customAnswer)?
      onAnswerInteraction;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.messageIndex,
    this.onRetry,
    this.onBranch,
    this.operationUpdates,
    this.readOperations,
    this.onUndoPrompt,
    this.onReturnToParent,
    this.onEditAndResend,
    this.onAnswerInteraction,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  bool _menuVisible = false;
  List<String> _imageSources = const [];
  final Map<int, Uint8List> _decodedImages = {};

  @override
  void initState() {
    super.initState();
    _imageSources = message.allImageBase64s;
  }

  @override
  void didUpdateWidget(covariant ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sources = message.allImageBase64s;
    if (message.allImagePaths.isNotEmpty ||
        !listEquals(_imageSources, sources)) {
      _decodedImages.clear();
    }
    _imageSources = sources;
  }

  LlmMessage get message => widget.message;
  bool get isUser => message.role == LlmMessageRole.user;

  String get _textForCopy =>
      message.content.replaceAll(RegExp(r'\n\[图片\]$'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glass = FrostedTheme.of(context);
    final isCoffeePaper = glass.appearanceMode == AppearanceMode.coffeePaper;
    final userBubble = isCoffeePaper
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.14);

    final paths = message.allImagePaths;
    final images = message.allImageBase64s;
    final hasImage = paths.isNotEmpty || images.isNotEmpty;
    final hasText = message.content.trim().isNotEmpty;
    final hasTimeline = !isUser &&
        message.agentTimeline != null &&
        message.agentTimeline!.isNotEmpty;
    final isPlaceholder = !isUser &&
        !hasText &&
        !hasImage &&
        (!hasTimeline || message.id == null);

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
                maxWidth: isUser
                    ? MediaQuery.sizeOf(context).width * 0.78
                    : double.infinity,
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: isUser ? (isCoffeePaper ? 15 : 12) : 0,
                    vertical: 10),
                decoration: !isUser
                    ? null
                    : BoxDecoration(
                        color: userBubble,
                        borderRadius: isCoffeePaper
                            ? BorderRadius.circular(20)
                            : const BorderRadius.only(
                                topLeft: Radius.circular(18),
                                topRight: Radius.circular(18),
                                bottomLeft: Radius.circular(18),
                                bottomRight: Radius.circular(4),
                              ),
                        border: isCoffeePaper
                            ? null
                            : Border.all(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.08),
                              ),
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasImage)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Wrap(spacing: 6, runSpacing: 6, children: [
                            for (var i = 0;
                                i <
                                    (paths.isNotEmpty
                                        ? paths.length
                                        : images.length);
                                i++)
                              Builder(builder: (context) {
                                final path = paths.isNotEmpty ? paths[i] : null;
                                final bytes = path == null
                                    ? _decodedImages.putIfAbsent(
                                        i, () => base64Decode(images[i]))
                                    : null;
                                return Semantics(
                                    label: '查看图片 ${i + 1}',
                                    button: true,
                                    child: GestureDetector(
                                      onTap: () => showFullscreenImagePreview(
                                          context,
                                          imagePath: path,
                                          imageBytes: bytes,
                                          allowSave: true),
                                      onLongPress: isUser
                                          ? () => setState(() =>
                                              _menuVisible = !_menuVisible)
                                          : null,
                                      child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: SizedBox(
                                            width: (paths.length +
                                                        images.length) ==
                                                    1
                                                ? 220
                                                : 100,
                                            height: (paths.length +
                                                        images.length) ==
                                                    1
                                                ? 220
                                                : 100,
                                            child: path != null
                                                ? Image.file(File(path),
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 660,
                                                    errorBuilder: (_, __,
                                                            ___) =>
                                                        const Icon(Icons
                                                            .broken_image_outlined))
                                                : Image.memory(bytes!,
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 660),
                                          )),
                                    ));
                              }),
                          ])),
                    if (hasTimeline)
                      Padding(
                        padding: EdgeInsets.only(bottom: hasText ? 8 : 0),
                        child: ToolExecutionTimeline(
                          timeline: message.agentTimeline!,
                          updates: widget.operationUpdates,
                          readTimeline: widget.readOperations,
                        ),
                      ),
                    if (hasText)
                      isUser
                          ? _TapDetector(
                              onTap: () =>
                                  setState(() => _menuVisible = !_menuVisible),
                              child: SelectableText(
                                message.content.trim(),
                                style: TextStyle(
                                  fontSize: isCoffeePaper ? 14.5 : 14,
                                  height: 1.5,
                                  color: theme.colorScheme.onSurface,
                                ),
                                contextMenuBuilder:
                                    (context, editableTextState) {
                                  return AdaptiveTextSelectionToolbar
                                      .editableText(
                                    editableTextState: editableTextState,
                                  );
                                },
                              ),
                            )
                          : ChatMarkdownText(
                              text: message.content.trim(),
                              editorialSerif: isCoffeePaper,
                              baseStyle: TextStyle(
                                fontSize: isCoffeePaper ? 15.5 : 15,
                                height: isCoffeePaper ? 1.68 : 1.65,
                                letterSpacing: isCoffeePaper ? 0.1 : 0,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                    if (!isUser && message.interaction != null)
                      Padding(
                        padding: EdgeInsets.only(top: hasText ? 10 : 0),
                        child: _InteractionOptions(
                          interaction: message.interaction!,
                          onAnswer: widget.onAnswerInteraction,
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
                            '助手处理中…',
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

    if (!isUser) {
      if (isPlaceholder ||
          (message.id == null && widget.onUndoPrompt == null)) {
        return bubble;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bubble,
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildMenuButtons(context),
          ),
        ],
      );
    }

    if (isPlaceholder ||
        (isUser && widget.onRetry == null && widget.onEditAndResend == null)) {
      return bubble;
    }

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        TweenAnimationBuilder<double>(
          tween: Tween(end: _menuVisible ? 1 : 0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Duration(milliseconds: _menuVisible ? 300 : 210),
          curve: Curves.easeInOutCubicEmphasized,
          builder: (context, progress, child) => ClipRect(
            key: const ValueKey('message-actions-reveal'),
            child: Align(
              alignment: isUser ? Alignment.topRight : Alignment.topLeft,
              heightFactor: progress,
              child: Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(0, -10 * (1 - progress)),
                  child: child,
                ),
              ),
            ),
          ),
          child: IgnorePointer(
            ignoring: !_menuVisible,
            child: ExcludeSemantics(
              excluding: !_menuVisible,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: _buildMenuButtons(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuButtons(BuildContext context) {
    final theme = Theme.of(context);
    if (!isUser) {
      final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.78);
      Widget action({
        required String tooltip,
        required IconData icon,
        required VoidCallback onPressed,
      }) =>
          SizedBox(
            width: 38,
            height: 38,
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(icon, size: 17),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              style: IconButton.styleFrom(
                minimumSize: const Size(38, 38),
                maximumSize: const Size(38, 38),
                padding: EdgeInsets.zero,
                foregroundColor: color,
              ),
            ),
          );

      return Wrap(
        spacing: 2,
        children: [
          if (_textForCopy.trim().isNotEmpty)
            action(
              tooltip: '整段复制',
              icon: CupertinoIcons.doc_on_doc,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _textForCopy));
                showFloatingToast(context, '已复制');
              },
            ),
          if (widget.onBranch != null)
            action(
              tooltip: '从这里创建分支',
              icon: Icons.call_split,
              onPressed: widget.onBranch!,
            ),
          if (widget.onRetry != null)
            action(
              tooltip: '重试',
              icon: CupertinoIcons.arrow_clockwise,
              onPressed: widget.onRetry!,
            ),
          if (widget.onUndoPrompt != null)
            action(
              tooltip: '恢复上一版提示词',
              icon: Icons.undo,
              onPressed: widget.onUndoPrompt!,
            ),
          if (widget.onReturnToParent != null)
            action(
              tooltip: '返回原会话',
              icon: Icons.reply,
              onPressed: widget.onReturnToParent!,
            ),
        ],
      );
    }
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

class _InteractionOptions extends StatefulWidget {
  final LlmInteraction interaction;
  final void Function(String? optionId, String? customAnswer)? onAnswer;

  const _InteractionOptions({required this.interaction, this.onAnswer});

  @override
  State<_InteractionOptions> createState() => _InteractionOptionsState();
}

class _InteractionOptionsState extends State<_InteractionOptions> {
  bool _showCustomField = false;
  bool _submitting = false;
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _submit(String? optionId, String? customAnswer) {
    if (_submitting || widget.interaction.isAnswered) return;
    setState(() => _submitting = true);
    widget.onAnswer?.call(optionId, customAnswer);
  }

  @override
  Widget build(BuildContext context) {
    final interaction = widget.interaction;
    final theme = Theme.of(context);
    if (interaction.isAnswered) {
      return Text(
        '已选择：${interaction.answerText ?? '已回答'}',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final enabled = !_submitting && widget.onAnswer != null;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in interaction.options) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: enabled ? () => _submit(option.id, null) : null,
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(42),
                padding: buttonPadding,
                shape: buttonShape,
                side: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                option.label,
                softWrap: true,
                textAlign: TextAlign.left,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (interaction.allowCustom)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: enabled
                  ? () => setState(() => _showCustomField = !_showCustomField)
                  : null,
              icon: const Icon(CupertinoIcons.pencil, size: 16),
              label: const Text('自定义回答'),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(42),
                padding: buttonPadding,
                shape: buttonShape,
                side: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        if (_showCustomField) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _customController,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: interaction.customPlaceholder ?? '输入你的要求',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                onPressed: enabled && _customController.text.trim().isNotEmpty
                    ? () => _submit(null, _customController.text.trim())
                    : null,
                tooltip: '提交自定义回答',
                icon: const Icon(CupertinoIcons.arrow_up_circle_fill),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 用 Listener 监听原始指针的"短按单击"——不参与手势竞技场，
/// 永远不会被 SelectableText 击败。长按（>300ms）时主动退让，
/// 让 SelectableText 的长按选区识别器接管。
class _TapDetector extends StatefulWidget {
  final VoidCallback? onTap;
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
    if (distance < _maxDragDistance && elapsed < _longPressThreshold) {
      widget.onTap?.call(); // 短按 = 单击 = 弹菜单
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
