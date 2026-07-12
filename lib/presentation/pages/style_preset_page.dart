import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/style_preset.dart';
import 'package:nai_huishi/presentation/pages/style_preset_detail_page.dart';
import 'package:nai_huishi/presentation/viewmodels/style_preset_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class StylePresetPage extends StatefulWidget {
  final void Function(String prompt) onApplyPrompt;

  const StylePresetPage({super.key, required this.onApplyPrompt});

  @override
  State<StylePresetPage> createState() => _StylePresetPageState();
}

class _StylePresetPageState extends State<StylePresetPage> {
  late final StylePresetViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = sl<StylePresetViewModel>();
    _vm.addListener(_onChanged);
    _vm.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _addPreset() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;

    final titleController = TextEditingController();
    final promptController = TextEditingController();

    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('新增画风收藏'),
        content: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              const SizedBox(height: 12),
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
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              final title = titleController.text.trim();
              final prompt = promptController.text.trim();
              if (title.isEmpty || prompt.isEmpty) return;
              await _vm.create(
                title: title,
                prompt: prompt,
                sourceImagePath: picked.path,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    titleController.dispose();
    promptController.dispose();
  }

  void _applyAndClose(String prompt) {
    widget.onApplyPrompt(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('画风收藏'),
        actions: [
          IconButton(
            onPressed: _addPreset,
            icon: const Icon(CupertinoIcons.add),
          ),
        ],
      ),
      body: _vm.isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _vm.presets.isEmpty
              ? Center(
                  child: Text('暂无画风收藏',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _vm.presets.length,
                  itemBuilder: (context, index) {
                    final preset = _vm.presets[index];
                    final file = File(preset.imagePath);
                    final exists = file.existsSync();
                    return _StylePresetGridCard(
                      preset: preset,
                      file: file,
                      exists: exists,
                      onOpen: () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => StylePresetDetailPage(
                              preset: preset,
                              vm: _vm,
                              onApplyPrompt: _applyAndClose,
                            ),
                          ),
                        );
                      },
                      onApply: () {
                        _applyAndClose(preset.prompt);
                        showFloatingToast(context, '已复制到对话框',
                            icon: CupertinoIcons.checkmark_circle_fill);
                      },
                    );
                  },
                ),
    );
  }
}

class _StylePresetGridCard extends StatefulWidget {
  final StylePreset preset;
  final File file;
  final bool exists;
  final VoidCallback onOpen;
  final VoidCallback onApply;

  const _StylePresetGridCard({
    required this.preset,
    required this.file,
    required this.exists,
    required this.onOpen,
    required this.onApply,
  });

  @override
  State<_StylePresetGridCard> createState() => _StylePresetGridCardState();
}

class _StylePresetGridCardState extends State<_StylePresetGridCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _applyWithFeedback() {
    _setPressed(false);
    widget.onApply();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onOpen,
      onDoubleTap: _applyWithFeedback,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 180),
        curve: _pressed ? Curves.easeOutCubic : Curves.elasticOut,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(_pressed ? 20 : 16),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.exists)
                Image.file(widget.file, fit: BoxFit.cover)
              else
                Center(
                  child: Icon(
                    CupertinoIcons.photo,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.25),
                    size: 32,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent
                      ],
                    ),
                  ),
                  child: Text(
                    widget.preset.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
