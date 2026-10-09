import 'dart:convert';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/presentation/pages/prompt_memory_page.dart';
import 'package:nai_huishi/presentation/pages/style_preset_page.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_input_bar.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_message_bubble.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/prompt_version_dialog.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_sessions_panel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_settings_sheet.dart';

class ChatDrawer extends StatefulWidget {
  final VoidCallback onClose;
  final Future<void> Function(LlmChatViewModel vm)? onInitializeScope;
  final Future<void> Function(LlmChatViewModel vm)? onCloseScope;
  final String? title;

  const ChatDrawer({
    super.key,
    required this.onClose,
    this.onInitializeScope,
    this.onCloseScope,
    this.title,
  });

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  late final LlmChatViewModel _vm;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  bool _ready = false;
  bool _isAtBottom = true;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _vm = sl<LlmChatViewModel>();
    _vm.addListener(_onVmChanged);
    // 注入副作用工具确认回调：本 State 实现弹窗
    _vm.onRequireConfirmation = _showConfirmationDialog;
    _scrollController.addListener(_onScroll);
    _init();
  }

  Future<void> _init() async {
    await _vm.ensureInitialized();
    if (widget.onInitializeScope != null) {
      await widget.onInitializeScope!(_vm);
    }
    if (!mounted) return;
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  Future<bool> _showConfirmationDialog(AgentToolConfirmRequest request) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Agent 请求执行操作'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('工具：${request.toolName}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Text('说明：${request.description}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Text('参数：',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    const JsonEncoder().convert(request.arguments),
                    style:
                        const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('同意执行'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final cur = _scrollController.position.pixels;
    final atBottom = (max - cur).abs() < 80;
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        if (atBottom) _unreadCount = 0;
      });
    }
  }

  void _onVmChanged() {
    if (!mounted) return;
    if (!_isAtBottom) {
      _unreadCount++;
    }
    setState(() {});
    if (_isAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottomAndClear() {
    _jumpToBottom();
    setState(() {
      _isAtBottom = true;
      _unreadCount = 0;
    });
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _vm.onRequireConfirmation = null;
    if (widget.onCloseScope != null) {
      widget.onCloseScope!(_vm);
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _openSessions() async {
    await showChatSessionsPanel(context, vm: _vm);
  }

  Future<void> _createNewSession() async {
    final version = await showPromptVersionDialog(context);
    if (version == null) return;
    await _vm.createNewSession(promptVersion: version);
  }

  void _insertIntoInput(String text) {
    final current = _inputController.text.trim();
    _inputController.text = current.isEmpty ? text : '$current, $text';
    _inputController.selection =
        TextSelection.collapsed(offset: _inputController.text.length);
  }

  Future<void> _openStylePresets() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => StylePresetPage(onApplyPrompt: _insertIntoInput),
      ),
    );
  }

  Future<void> _openMemories() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => const PromptMemoryPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.85;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: Container(
                color: Colors.black.withValues(alpha: isDark ? 0.48 : 0.38)),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: width,
          child: AnimatedSlide(
            offset: Offset.zero,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                bottomLeft: Radius.circular(28),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF14141A).withValues(alpha: 0.92)
                        : Colors.white.withValues(alpha: 0.94),
                    border: Border.all(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.08)),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      bottomLeft: Radius.circular(28),
                    ),
                  ),
                  child: SafeArea(
                    left: false,
                    child: Column(
                      children: [
                        _buildTopBar(),
                        Expanded(
                          child: !_ready || _vm.isLoading
                              ? Center(child: CircularProgressIndicator())
                              : _buildMessageList(),
                        ),
                        if (_vm.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.24)),
                              ),
                              child: Row(
                                children: [
                                  Icon(CupertinoIcons.exclamationmark_triangle,
                                      size: 16, color: Colors.redAccent),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _vm.errorMessage!,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _vm.clearError,
                                    child: Icon(CupertinoIcons.xmark,
                                        size: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ChatInputBar(
                          controller: _inputController,
                          isSending: _vm.isSending,
                          onSend: (text,
                                  {String? imageBase64,
                                  String? textAttachment}) =>
                              _vm.sendUserMessage(
                            text,
                            imageBase64: imageBase64,
                            textAttachment: textAttachment,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final title = widget.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Row(
        children: [
          if (title != null)
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          IconButton(
            onPressed: _openSessions,
            tooltip: '会话列表',
            icon: Icon(CupertinoIcons.list_bullet,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          IconButton(
            onPressed: _openStylePresets,
            tooltip: '画风收藏',
            icon: Icon(CupertinoIcons.square_grid_2x2,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          IconButton(
            onPressed: _openMemories,
            tooltip: '学习记忆',
            icon: Icon(CupertinoIcons.book,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          if (title == null) const Spacer(),
          IconButton(
            onPressed: _createNewSession,
            tooltip: '新建会话',
            icon: Icon(CupertinoIcons.square_pencil,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          IconButton(
            onPressed: () => showChatSettingsSheet(context, _vm),
            tooltip: '配置',
            icon: Icon(CupertinoIcons.gear_alt,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          IconButton(
            onPressed: widget.onClose,
            tooltip: '关闭',
            icon: Icon(CupertinoIcons.xmark_circle_fill,
                color: Theme.of(context).colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_vm.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.wand_stars,
                  size: 34,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.5)),
              SizedBox(height: 12),
              Text(
                '描述你想生成的画面，我来帮你整理成提示词。\n信息不足时会给出可点击选项确认。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: _vm.messages.length,
          itemBuilder: (context, index) {
            final message = _vm.messages[index];
            return ChatMessageBubble(
              message: message,
              messageIndex: index,
              onRetry: message.role == LlmMessageRole.user
                  ? () => _vm.retryFromIndex(index)
                  : null,
              onEditAndResend: message.role == LlmMessageRole.user
                  ? (newText) => _vm.editAndResend(index, newText)
                  : null,
              onAnswerInteraction: (optionId, customAnswer) =>
                  _vm.answerInteraction(
                message: message,
                optionId: optionId,
                customAnswer: customAnswer,
              ),
            );
          },
        ),
        if (!_isAtBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton(
              mini: true,
              backgroundColor:
                  theme.colorScheme.surface.withValues(alpha: 0.92),
              elevation: 2,
              onPressed: _scrollToBottomAndClear,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(CupertinoIcons.arrow_down,
                      size: 18, color: theme.colorScheme.onSurface),
                  if (_unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        constraints:
                            const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          _unreadCount > 9 ? '9+' : '$_unreadCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
