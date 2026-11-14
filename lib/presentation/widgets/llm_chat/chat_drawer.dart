import 'dart:convert';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/style_preset_page.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_input_bar.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_scroll_surface.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_message_list.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/prompt_version_dialog.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_sessions_panel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_settings_sheet.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';

class ChatDrawer extends StatefulWidget {
  final VoidCallback onClose;
  final Future<void> Function(LlmChatViewModel vm)? onInitializeScope;
  final Future<void> Function(LlmChatViewModel vm)? onCloseScope;
  final String? title;
  final bool embedded;
  final bool parentResizesForKeyboard;
  final bool? active;

  const ChatDrawer({
    super.key,
    required this.onClose,
    this.onInitializeScope,
    this.onCloseScope,
    this.title,
    this.embedded = false,
    this.parentResizesForKeyboard = false,
    this.active,
  });

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  static Future<bool> _rejectConfirmation(AgentToolConfirmRequest _) async =>
      false;

  static final Future<bool> Function(AgentToolConfirmRequest request)
      _failClosedConfirmation = _rejectConfirmation;

  late final LlmChatViewModel _vm;
  late final Future<bool> Function(AgentToolConfirmRequest request)
      _confirmationHandler = _showConfirmationDialog;
  final TextEditingController _inputController = TextEditingController();
  bool _ready = false;
  late Object _controlsState;

  Object _readControlsState() => (
        _vm.errorMessage,
        _vm.isSending,
        _vm.canStop,
        _vm.canUndoPrompt,
        _vm.activeSession?.parentSessionId,
        _vm.runStage,
      );

  @override
  void initState() {
    super.initState();
    _vm = sl<LlmChatViewModel>();
    _controlsState = _readControlsState();
    _vm.addListener(_onVmChanged);
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncConfirmationHandler();
  }

  @override
  void didUpdateWidget(covariant ChatDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncConfirmationHandler();
    }
  }

  bool get _shouldOwnConfirmationHandler {
    final tabIsActive = widget.active ?? TickerMode.valuesOf(context).enabled;
    final routeIsActive = ModalRoute.of(context)?.isCurrent ?? true;
    return tabIsActive && routeIsActive;
  }

  bool get _ownsConfirmationHandler =>
      _shouldOwnConfirmationHandler &&
      identical(_vm.onRequireConfirmation, _confirmationHandler);

  void _syncConfirmationHandler() {
    final shouldOwn = _shouldOwnConfirmationHandler;
    if (shouldOwn) {
      _vm.onRequireConfirmation = _confirmationHandler;
    } else if (identical(_vm.onRequireConfirmation, _confirmationHandler)) {
      // A null handler auto-approves agent tools in the current ViewModel.
      // Keep the no-visible-owner state explicitly fail-closed.
      _vm.onRequireConfirmation = _failClosedConfirmation;
    } else if (_vm.onRequireConfirmation == null) {
      _vm.onRequireConfirmation = _failClosedConfirmation;
    }
  }

  Future<void> _init() async {
    await _vm.ensureInitialized();
    if (widget.onInitializeScope != null) {
      await widget.onInitializeScope!(_vm);
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<bool> _showConfirmationDialog(AgentToolConfirmRequest request) async {
    if (!mounted || !_ownsConfirmationHandler) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('确认操作'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '工具：${request.toolName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '说明：${request.description}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Text(
                '参数：',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (_vm.isSending)
              TextButton(
                  onPressed: () {
                    _vm.stopSending();
                    Navigator.of(ctx).pop(false);
                  },
                  child: const Text('停止本轮')),
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

  void _onVmChanged() {
    if (!mounted) return;
    final next = _readControlsState();
    if (next == _controlsState) return;
    _controlsState = next;
    setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    if (identical(_vm.onRequireConfirmation, _confirmationHandler)) {
      // Do not detach a newer drawer, and never leave the ViewModel in its
      // null-means-approve state after this confirmation UI is gone.
      _vm.onRequireConfirmation = _failClosedConfirmation;
    }
    if (widget.onCloseScope != null) {
      widget.onCloseScope!(_vm);
    }
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
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
  }

  Future<void> _openStylePresets() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => StylePresetPage(onApplyPrompt: _insertIntoInput),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (widget.embedded) {
      final safeInsets = MediaQuery.paddingOf(context);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
        child: ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: SafeArea(
            top: false,
            bottom: false,
            child: _buildChatColumn(
                safeInsets: EdgeInsets.only(
              top: safeInsets.top,
              bottom: safeInsets.bottom,
            )),
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width * 0.85;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: Container(
              color: Colors.black.withValues(alpha: isDark ? 0.48 : 0.38),
            ),
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
                enabled: FrostedTheme.of(context).blurEnabled,
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.82),
                    border: Border.all(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.08,
                      ),
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      bottomLeft: Radius.circular(28),
                    ),
                  ),
                  child: SafeArea(left: false, child: _buildChatColumn()),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatColumn({EdgeInsets safeInsets = EdgeInsets.zero}) {
    return LayoutBuilder(
      builder: (context, constraints) => ChatScrollSurface(
        background: widget.embedded ? const StudioBackground() : null,
        footerBottomInset: safeInsets.bottom,
        header: Padding(
          padding: EdgeInsets.only(top: safeInsets.top),
          child: _buildTopBar(),
        ),
        bodyBuilder: (insets) => ChatMessageList(
          vm: _vm,
          insets: insets,
          ready: _ready,
          active: widget.active ?? TickerMode.valuesOf(context).enabled,
        ),
        footer: Padding(
          padding: EdgeInsets.only(bottom: safeInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.24)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _vm.errorMessage!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _vm.clearError,
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 14,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_vm.isSending ||
                  _vm.canUndoPrompt ||
                  _vm.activeSession?.parentSessionId != null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Expanded(
                          child: Text(_vm.isSending ? _vm.runStage : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall)),
                      if (_vm.canUndoPrompt)
                        TextButton.icon(
                            onPressed: _vm.undoPromptChange,
                            icon: const Icon(Icons.undo, size: 16),
                            label: const Text('撤销写入')),
                      if (_vm.activeSession?.parentSessionId != null)
                        IconButton(
                            tooltip: '返回原会话',
                            icon: const Icon(Icons.call_split, size: 18),
                            onPressed: _vm.isSending
                                ? null
                                : () => _vm.selectSession(
                                    _vm.activeSession!.parentSessionId!)),
                    ])),
              ChatInputBar(
                updateGuard: sl.isRegistered<AppUpdateInstallGuard>()
                    ? sl<AppUpdateInstallGuard>()
                    : null,
                maxHeight: (constraints.maxHeight -
                        safeInsets.vertical -
                        110 -
                        (_vm.errorMessage == null ? 0 : 90))
                    .clamp(80, double.infinity),
                includeKeyboardInset:
                    !(widget.embedded || widget.parentResizesForKeyboard),
                controller: _inputController,
                isSending: _vm.isSending,
                onStop: _vm.canStop ? _vm.stopSending : null,
                onOpenStylePresets: _openStylePresets,
                onSend: (text,
                        {String? imageBase64,
                        List<String> imageBase64s = const [],
                        String? textAttachment}) =>
                    _vm.sendUserMessage(
                  text,
                  imageBase64: imageBase64,
                  imageBase64s: imageBase64s,
                  textAttachment: textAttachment,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final title = widget.embedded ? null : widget.title;
    final iconColor = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: _openSessions,
            tooltip: '会话历史',
            icon: Icon(CupertinoIcons.list_bullet, color: iconColor),
          ),
          if (title != null)
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            const Spacer(),
          IconButton(
            onPressed: _createNewSession,
            tooltip: '新建会话',
            icon: Icon(CupertinoIcons.square_pencil, color: iconColor),
          ),
          IconButton(
            onPressed: () => showChatSettingsSheet(context, _vm),
            tooltip: '设置',
            icon: Icon(CupertinoIcons.gear_alt, color: iconColor),
          ),
          if (!widget.embedded)
            IconButton(
              onPressed: widget.onClose,
              tooltip: '关闭',
              icon: Icon(CupertinoIcons.xmark_circle_fill, color: iconColor),
            ),
        ],
      ),
    );
  }
}
