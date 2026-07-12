import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/style_preset.dart';
import 'package:nai_huishi/presentation/viewmodels/style_preset_viewmodel.dart';

class StylePresetDetailPage extends StatefulWidget {
  final StylePreset preset;
  final StylePresetViewModel vm;
  final void Function(String prompt) onApplyPrompt;

  const StylePresetDetailPage({
    super.key,
    required this.preset,
    required this.vm,
    required this.onApplyPrompt,
  });

  @override
  State<StylePresetDetailPage> createState() => _StylePresetDetailPageState();
}

class _StylePresetDetailPageState extends State<StylePresetDetailPage> {
  late StylePreset _preset;

  @override
  void initState() {
    super.initState();
    _preset = widget.preset;
  }

  Future<void> _edit() async {
    final titleController = TextEditingController(text: _preset.title);
    final promptController = TextEditingController(text: _preset.prompt);

    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('编辑画风收藏'),
        content: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              TextField(
                controller: promptController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '画风/画师串'),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              final title = titleController.text.trim();
              final prompt = promptController.text.trim();
              if (title.isEmpty || prompt.isEmpty) return;
              final updated = _preset.copyWith(
                title: title,
                prompt: prompt,
              );
              await widget.vm.update(updated);
              setState(() => _preset = updated);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('保存'),
          ),
        ],
      ),
    );

    titleController.dispose();
    promptController.dispose();
  }

  Future<void> _delete() async {
    final id = _preset.id;
    if (id == null) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('删除收藏'),
        content: Text('确定删除这个画风画师串收藏吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.vm.delete(id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(_preset.imagePath);
    final exists = file.existsSync();
    return Scaffold(
      appBar: AppBar(
        title: Text(_preset.title),
        actions: [
          IconButton(onPressed: _edit, icon: Icon(CupertinoIcons.pencil)),
          IconButton(onPressed: _delete, icon: Icon(CupertinoIcons.delete)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 360,
              color: const Color(0xFF1C1C21),
              child: exists
                  ? InteractiveViewer(
                      child: Image.file(file, fit: BoxFit.contain))
                  : Center(
                      child: Icon(CupertinoIcons.photo,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.25),
                          size: 44)),
            ),
          ),
          SizedBox(height: 16),
          SelectableText(
            _preset.prompt,
            style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () {
              widget.onApplyPrompt(_preset.prompt);
              Navigator.pop(context);
            },
            icon: Icon(CupertinoIcons.plus_circle),
            label: Text('添加到对话栏'),
          ),
        ],
      ),
    );
  }
}
