import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

class ChatInputBar extends StatefulWidget {
  final bool isSending;
  final void Function(String text,
      {String? imageBase64, String? textAttachment}) onSend;
  final TextEditingController? controller;
  final bool includeKeyboardInset;

  const ChatInputBar({
    super.key,
    required this.isSending,
    required this.onSend,
    this.controller,
    this.includeKeyboardInset = true,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;
  bool _ownsController = false;
  bool _hasText = false;
  String? _pendingImageBase64;
  String? _pendingImagePath;
  String? _pendingTextAttachment;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) {
      setState(() => _hasText = has);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12 +
            (widget.includeKeyboardInset
                ? MediaQuery.viewInsetsOf(context).bottom
                : 0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImagePath != null) _buildImagePreview(),
          if (_pendingTextAttachment != null) _buildTextFilePreview(),
          FrostedSurface(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: widget.isSending ? null : _pickImage,
                  tooltip: '添加图片',
                  icon: Icon(
                    CupertinoIcons.photo,
                    size: 20,
                    color: _pendingImageBase64 != null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  onPressed: widget.isSending ? null : _pickTextFile,
                  tooltip: '添加文本文件',
                  icon: Icon(
                    CupertinoIcons.doc_text,
                    size: 20,
                    color: _pendingTextAttachment != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                        fontSize: 14,
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
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                SizedBox(width: 4),
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
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
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canSend ? _submit : null,
                      child: Center(
                        child: widget.isSending
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Icon(
                                CupertinoIcons.arrow_up,
                                size: 20,
                                color: canSend
                                    ? glass.onSelection
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 2),
              ],
            ),
          ),
        ],
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
