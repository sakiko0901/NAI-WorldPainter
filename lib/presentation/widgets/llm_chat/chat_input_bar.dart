import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class ChatInputBar extends StatefulWidget {
  final bool isSending;
  final bool webSearchEnabled;
  final VoidCallback onToggleWebSearch;
  final void Function(String text, {String? imageBase64}) onSend;
  final TextEditingController? controller;

  const ChatInputBar({
    super.key,
    required this.isSending,
    required this.webSearchEnabled,
    required this.onToggleWebSearch,
    required this.onSend,
    this.controller,
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

  void _submit() {
    final text = _controller.text.trim();
    if ((text.isEmpty && _pendingImageBase64 == null) || widget.isSending) {
      return;
    }
    HapticFeedback.lightImpact();
    widget.onSend(text, imageBase64: _pendingImageBase64);
    _controller.clear();
    setState(() {
      _pendingImageBase64 = null;
      _pendingImagePath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSend =
        (_hasText || _pendingImageBase64 != null) && !widget.isSending;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImagePath != null) _buildImagePreview(),
          Container(
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.black.withValues(alpha: 0.35) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
            ),
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: widget.isSending ? null : _pickImage,
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
                  onPressed: widget.isSending ? null : widget.onToggleWebSearch,
                  tooltip:
                      widget.webSearchEnabled ? '联网搜索：开（点击关闭）' : '联网搜索：关（点击开启）',
                  icon: Icon(
                    CupertinoIcons.globe,
                    size: 20,
                    color: widget.webSearchEnabled
                        ? theme.colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: canSend
                        ? const LinearGradient(
                            colors: [Color(0xFFF5D57A), Color(0xFFD4A373)],
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
                              color: const Color(0xFFF5D57A)
                                  .withValues(alpha: 0.3),
                              blurRadius: 14,
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
                                    ? theme.colorScheme.onPrimary
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
