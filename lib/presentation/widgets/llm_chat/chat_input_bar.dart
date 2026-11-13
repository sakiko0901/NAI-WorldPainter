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
  final VoidCallback? onStop;
  final void Function(String text,
      {String? imageBase64,
      List<String> imageBase64s,
      String? textAttachment}) onSend;
  final TextEditingController? controller;
  final bool includeKeyboardInset;
  final VoidCallback? onOpenStylePresets;
  final double? maxHeight;
  final AppUpdateInstallGuard? updateGuard;

  const ChatInputBar({
    super.key,
    required this.isSending,
    this.onStop,
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
  final List<String> _pendingImages = [];
  final List<String> _pendingPaths = [];
  final List<String> _imagePurposes = [];
  bool _pickingImages = false;
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
          _pendingImages.isNotEmpty ||
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
    if (_pickingImages || widget.isSending) return;
    final remaining = 10 - _pendingImages.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('每条消息最多 10 张图片')));
      return;
    }
    setState(() => _pickingImages = true);
    try {
      final picked = await ImagePicker()
          .pickMultiImage(imageQuality: 85, maxWidth: 1920, maxHeight: 1920);
      final images = <String>[];
      final paths = <String>[];
      for (final item in picked.take(remaining)) {
        images.add(base64Encode(await File(item.path).readAsBytes()));
        paths.add(item.path);
      }
      if (!mounted) return;
      setState(() {
        _pendingImages.addAll(images);
        _pendingPaths.addAll(paths);
        _imagePurposes.addAll(List.filled(paths.length, '综合参考'));
      });
      if (picked.length > remaining) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('每条消息最多 10 张，已保留前 10 张')));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('读取照片失败，请重新选择')));
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
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
            _pendingImages.isEmpty &&
            _pendingTextAttachment == null) ||
        (widget.isSending || _pickingImages)) {
      return;
    }
    HapticFeedback.lightImpact();
    _setAttachmentMenu(false);
    final purposes = _imagePurposes.isEmpty
        ? ''
        : '\n\n参考图用途：\n${List.generate(_imagePurposes.length, (i) => '图片 ${i + 1}：${_imagePurposes[i]}').join('\n')}';
    widget.onSend(
      '$text$purposes'.trim(),
      imageBase64s: List.of(_pendingImages),
      textAttachment: _pendingTextAttachment,
    );
    _controller.clear();
    setState(() {
      _pendingImages.clear();
      _pendingPaths.clear();
      _imagePurposes.clear();
      _pendingTextAttachment = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSend = (_hasText ||
            _pendingImages.isNotEmpty ||
            _pendingTextAttachment != null) &&
        !widget.isSending &&
        !_pickingImages;
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
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight:
                          ((widget.maxHeight ?? 400) * 0.4).clamp(0, 160)),
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_pendingPaths.isNotEmpty) _buildImagePreview(),
                    if (_pendingTextAttachment != null) _buildTextFilePreview(),
                    _buildAttachmentMenu(),
                  ])),
                ),
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
                            label: widget.isSending ? '停止回复' : '发送消息',
                            button: true,
                            enabled: canSend || widget.onStop != null,
                            child: Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: widget.isSending
                                    ? widget.onStop
                                    : canSend
                                        ? _submit
                                        : null,
                                child: Center(
                                  child: widget.isSending
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: const Icon(Icons.stop_rounded,
                                              size: 20, color: Colors.white),
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

  Widget _buildImagePreview() => SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingPaths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => SizedBox(
            width: 100,
            child: Column(children: [
              Stack(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(_pendingPaths[index]),
                        width: 100,
                        height: 80,
                        fit: BoxFit.cover,
                        cacheWidth: 300)),
                Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton.filledTonal(
                        tooltip: '移除图片 ${index + 1}',
                        iconSize: 16,
                        constraints: const BoxConstraints.tightFor(
                            width: 32, height: 32),
                        onPressed: () => setState(() {
                              _pendingImages.removeAt(index);
                              _pendingPaths.removeAt(index);
                              _imagePurposes.removeAt(index);
                            }),
                        icon: const Icon(Icons.close))),
              ]),
              PopupMenuButton<String>(
                initialValue: _imagePurposes[index],
                tooltip: '图片 ${index + 1} 的参考用途',
                onSelected: (value) =>
                    setState(() => _imagePurposes[index] = value),
                itemBuilder: (_) => [
                  for (final label in ['综合参考', '角色外观', '画风', '构图', '服饰', '配色'])
                    PopupMenuItem(value: label, child: Text(label))
                ],
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('${index + 1} · ${_imagePurposes[index]} ▾',
                        style: const TextStyle(fontSize: 12))),
              ),
            ])),
      ));
}
