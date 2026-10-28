import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Shared prompt editing surface for text-to-image and local repainting.
class PromptEditorField extends StatelessWidget {
  const PromptEditorField({
    super.key,
    this.fieldKey,
    required this.controller,
    this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.textColor,
    required this.editorTitle,
    required this.onExpandedSubmit,
    this.enabled = true,
    this.showExpandButton = true,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final Color textColor;
  final String editorTitle;
  final Future<void> Function(String value) onExpandedSubmit;
  final bool enabled;
  final bool showExpandButton;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TextField(
          key: fieldKey,
          enabled: enabled,
          controller: controller,
          focusNode: focusNode,
          minLines: 6,
          maxLines: 14,
          style: TextStyle(fontSize: 14, height: 1.5, color: textColor),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.55),
            ),
            fillColor: Colors.transparent,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.only(right: showExpandButton ? 48 : 0),
          ),
          onChanged: onChanged,
        ),
        if (showExpandButton)
          Positioned(
            top: 0,
            right: -4,
            child: IconButton(
              onPressed: !enabled
                  ? null
                  : () => openExpandedEditor(
                        context: context,
                        title: editorTitle,
                        initialValue: controller.text,
                        onSubmitted: onExpandedSubmit,
                      ),
              tooltip: '放大编辑',
              visualDensity: VisualDensity.standard,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(
                CupertinoIcons.arrow_up_left_arrow_down_right,
                size: 15,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.45),
              ),
            ),
          ),
      ],
    );
  }

  static Future<void> openExpandedEditor({
    required BuildContext context,
    required String title,
    required String initialValue,
    required Future<void> Function(String value) onSubmitted,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _ExpandedPromptEditor(
          title: title,
          initialValue: initialValue,
          onSubmitted: onSubmitted,
        ),
      );
}

class _ExpandedPromptEditor extends StatefulWidget {
  const _ExpandedPromptEditor({
    required this.title,
    required this.initialValue,
    required this.onSubmitted,
  });

  final String title;
  final String initialValue;
  final Future<void> Function(String value) onSubmitted;

  @override
  State<_ExpandedPromptEditor> createState() => _ExpandedPromptEditorState();
}

class _ExpandedPromptEditorState extends State<_ExpandedPromptEditor> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.xmark),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: null,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                  decoration: const InputDecoration(
                    hintText: '请输入提示词...',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await widget.onSubmitted(controller.text);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(CupertinoIcons.check_mark),
                  label: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
