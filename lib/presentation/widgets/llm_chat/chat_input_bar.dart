import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

class ChatInputBar extends StatefulWidget {
  final bool isSending;
  final void Function(String text,
      {String? imageBase64, String? textAttachment}) onSend;
  final TextEditingController? controller;
  final bool includeKeyboardInset;
  final VoidCallback? onOpenStylePresets;
  final double? maxHeight;
  final AppUpdateInstallGuard? updateGuard;

  const ChatInputBar({
    super.key,
    required this.isSending,
    required this.onSend,
    this.controller,
    this.includeKeyboardInset = true,
    this.onOpenStylePresets,
    this.maxHeight,
    this.updateGuard,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _attachmentAnimation;
  late final CurvedAnimation _attachmentCurve;
  bool _ownsController = false;
  bool _hasText = false;
  bool _attachmentMenuOpen = false;
  String? _pendingImageBase64;
  String? _pendingImagePath;
  String? _pendingTextAttachment;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    widget.updateGuard?.registerUnsaved(this, _updateWarning);
    _ownsController = widget.controller == null;
    _hasText = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _attachmentAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _attachmentCurve = CurvedAnimation(
      parent: _attachmentAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updateGuard != widget.updateGuard) {
      oldWidget.updateGuard?.unregisterUnsaved(this);
      widget.updateGuard?.registerUnsaved(this, _updateWarning);
    }
    if (widget.isSending && !oldWidget.isSending) {
      _setAttachmentMenu(false);
    }
  }

  void _onFocusChanged() => setState(() {});

  String? _updateWarning() => _controller.text.trim().isNotEmpty ||
          _pendingImageBase64 != null ||
          _pendingTextAttachment != null
      ? 'AI 助手还有未发送的文字或附件，请先保存或发送'
      : null;

  void _setAttachmentMenu(bool open) {
    if (_attachmentMenuOpen == open) return;
    setState(() => _attachmentMenuOpen = open);
    if (MediaQuery.disableAnimationsOf(context)) {
      _attachmentAnimation.value = open ? 1 : 0;
    } else if (open) {
      _attachmentAnimation.forward();
    } else {
      _attachmentAnimation.reverse();
    }
  }

  void _chooseAttachment(VoidCallback action) {
    _setAttachmentMenu(false);
    action();
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) {
      setState(() => _hasText = has);
    }
  }

  @override
  void dispose() {
    widget.updateGuard?.unregisterUnsaved(this);
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _attachmentCurve.dispose();
    _attachmentAnimation.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    final base64Str = base64Encode(bytes);
    if (!mounted) return;
    setState(() {
      _pendingImageBase64 = base64Str;
      _pendingImagePath = picked.path;
    });
  }

  void _removeImage() {
    setState(() {
      _pendingImageBase64 = null;
      _pendingImagePath = null;
    });
  }

  Future<void> _pickTextFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'markdown', 'json'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final file = File(path);
    if (await file.length() > 200 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文本文件不能超过 200 KB。')),
        );
      }
      return;
    }
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) throw const FormatException();
      if (!mounted) return;
      setState(() =>
          _pendingTextAttachment = '文件：${result!.files.single.name}\n$content');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('仅支持 UTF-8 编码的文本文件。')),
        );
      }
    }
  }

  void _removeTextFile() => setState(() => _pendingTextAttachment = null);

  void _submit() {
    final text = _controller.text.trim();
    if ((text.isEmpty &&
            _pendingImageBase64 == null &&
            _pendingTextAttachment == null) ||
        widget.isSending) {
      return;
    }
    HapticFeedback.lightImpact();
    _setAttachmentMenu(false);
    widget.onSend(
      text,
      imageBase64: _pendingImageBase64,
      textAttachment: _pendingTextAttachment,
    );
    _controller.clear();
    setState(() {
      _pendingImageBase64 = null;
      _pendingImagePath = null;
      _pendingTextAttachment = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSend = (_hasText ||
            _pendingImageBase64 != null ||
            _pendingTextAttachment != null) &&
        !widget.isSending;
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final horizontalInset = _focusNode.hasFocus ? 12.0 : 24.0;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.maxHeight ?? double.infinity,
      ),
      child: AnimatedPadding(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(
          horizontalInset,
          8,
          horizontalInset,
          12 +
              (widget.includeKeyboardInset
                  ? MediaQuery.viewInsetsOf(context).bottom
                  : 0),
        ),
        child: TextFieldTapRegion(
          child: TapRegion(
            onTapOutside: (_) => _setAttachmentMenu(false),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingImagePath != null) _buildImagePreview(),
                if (_pendingTextAttachment != null) _buildTextFilePreview(),
                _buildAttachmentMenu(),
                Flexible(
                  fit: FlexFit.loose,
                  child: FrostedSurface(
                    key: const ValueKey('chat-composer-surface'),
                    radius: 26,
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: widget.isSending
                              ? null
                              : () => _setAttachmentMenu(!_attachmentMenuOpen),
                          tooltip: _attachmentMenuOpen ? '收起添加菜单' : '添加附件',
                          icon: AnimatedRotation(
                            turns: _attachmentMenuOpen ? 0.125 : 0,
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              CupertinoIcons.plus,
                              size: 23,
                              color: widget.isSending
                                  ? theme.disabledColor
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            onTap: () => _setAttachmentMenu(false),
                            onTapOutside: (_) => _focusNode.unfocus(),
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '描述你想画的画面...',
                              hintStyle: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                  fontSize: 14),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 13.5),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: canSend
                                ? LinearGradient(
                                    colors: [glass.selection, glass.selection],
                                  )
                                : LinearGradient(
                                    colors: [
                                      theme.colorScheme.onSurface
                                          .withValues(alpha: 0.14),
                                      theme.colorScheme.onSurface
                                          .withValues(alpha: 0.08),
                                    ],
                                  ),
                            boxShadow: canSend
                                ? [
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.12),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Semantics(
                            label: widget.isSending ? '正在发送' : '发送消息',
                            button: true,
                            enabled: canSend,
                            child: Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: canSend ? _submit : null,
                                child: Center(
                                  child: widget.isSending
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation(
                                                Colors.white),
                                          ),
                                        )
                                      : Icon(
                                          CupertinoIcons.arrow_up,
                                          size: 20,
                                          color: canSend
                                              ? glass.onSelection
                                              : theme
                                                  .colorScheme.onSurfaceVariant,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentMenu() {
    return SizeTransition(
      sizeFactor: _attachmentCurve,
      axisAlignment: 1,
      child: FadeTransition(
        opacity: _attachmentCurve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(_attachmentCurve),
          child: IgnorePointer(
            ignoring: !_attachmentMenuOpen || widget.isSending,
            child: ExcludeSemantics(
              excluding: !_attachmentMenuOpen,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FrostedSurface(
                  radius: 22,
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAttachmentAction(
                        icon: CupertinoIcons.photo,
                        label: '添加照片',
                        onTap: _pickImage,
                      ),
                      _buildAttachmentAction(
                        icon: CupertinoIcons.doc_text,
                        label: '添加文档',
                        onTap: _pickTextFile,
                      ),
                      _buildAttachmentAction(
                        icon: CupertinoIcons.square_grid_2x2,
                        label: '画风收藏',
                        onTap: widget.onOpenStylePresets,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final color =
        onTap == null ? theme.disabledColor : theme.colorScheme.onSurface;
    return Expanded(
      child: Semantics(
        button: true,
        enabled: onTap != null,
        child: InkWell(
          onTap: onTap == null ? null : () => _chooseAttachment(onTap),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 9),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFilePreview() {
    final title =
        _pendingTextAttachment!.split('\n').first.replaceFirst('文件：', '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Chip(
        avatar: const Icon(CupertinoIcons.doc_text, size: 16),
        label: Text(title, overflow: TextOverflow.ellipsis),
        onDeleted: _removeTextFile,
      ),
    );
  }

  Widget _buildImagePreview() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_pendingImagePath!),
              height: 80,
              width: 80,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: _removeImage,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(CupertinoIcons.xmark,
                    size: 12, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
