import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/director_tool.dart';
import 'package:nai_huishi/presentation/viewmodels/director_tools_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class DirectorToolsPage extends StatefulWidget {
  const DirectorToolsPage({super.key});

  @override
  State<DirectorToolsPage> createState() => _DirectorToolsPageState();
}

class _DirectorToolsPageState extends State<DirectorToolsPage> {
  static const _toolOrder = [
    DirectorToolType.bgRemover,
    DirectorToolType.lineart,
    DirectorToolType.sketch,
    DirectorToolType.colorize,
    DirectorToolType.emotion,
    DirectorToolType.declutter,
  ];

  late final DirectorToolsViewModel _vm;
  final _picker = ImagePicker();
  final _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vm = sl<DirectorToolsViewModel>()..addListener(_changed);
    _vm.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _promptController.dispose();
    _vm.removeListener(_changed);
    _vm.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) _vm.selectInput(image.path);
  }

  Future<void> _process() async {
    final ok = await _vm.process();
    if (!mounted) return;
    showFloatingToast(
      context,
      ok ? '处理完成' : (_vm.errorMessage ?? '处理失败'),
      icon: ok
          ? CupertinoIcons.checkmark_circle_fill
          : CupertinoIcons.exclamationmark_circle,
    );
  }

  Future<void> _save() async {
    final ok = await _vm.saveToGallery();
    if (!mounted) return;
    showFloatingToast(
      context,
      ok ? '已保存到相册' : (_vm.errorMessage ?? '保存失败'),
      icon: ok
          ? CupertinoIcons.checkmark_circle_fill
          : CupertinoIcons.exclamationmark_circle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('导演工具')),
      body: Column(
        children: [
          Expanded(child: _canvas(colors)),
          _controlPanel(colors),
        ],
      ),
    );
  }

  Widget _canvas(ColorScheme colors) {
    final path = _vm.outputPath ?? _vm.inputPath;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: path == null
          ? InkWell(
              onTap: _vm.isProcessing ? null : _pickImage,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.photo_fill,
                      size: 64, color: colors.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('点击选择图片',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                ],
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(path), fit: BoxFit.contain),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Chip(
                    label: Text(_vm.outputPath == null ? '原图' : '处理结果'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _controlPanel(ColorScheme colors) {
    final disabled = _vm.isProcessing;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _thumbnail(colors),
                  const SizedBox(width: 10),
                  Expanded(child: _modelDropdown(colors)),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: '更换图片',
                    onPressed: disabled ? null : _pickImage,
                    icon: const Icon(CupertinoIcons.photo_on_rectangle),
                  ),
                ],
              ),
              if (_vm.selectedTool.usesPrompt) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _promptController,
                  enabled: !disabled,
                  onChanged: _vm.updatePrompt,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: _vm.selectedTool == DirectorToolType.colorize
                        ? '配色提示词（可选）'
                        : '表情与特征提示词（可选）',
                    hintText: _vm.selectedTool == DirectorToolType.colorize
                        ? 'red hair, blue eyes'
                        : 'smile, fang',
                  ),
                ),
              ],
              if (_vm.selectedTool.usesDefry)
                _parameterSlider(
                  title: '去噪强度',
                  value: _vm.defry,
                  min: 0,
                  max: 5,
                  onChanged: _vm.updateDefry,
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  PopupMenuButton<DirectorToolType>(
                    enabled: !disabled,
                    initialValue: _vm.selectedTool,
                    tooltip: '选择工具',
                    onSelected: _vm.selectTool,
                    itemBuilder: (_) => _toolOrder
                        .map((tool) => PopupMenuItem(
                              value: tool,
                              child: Row(
                                children: [
                                  if (tool == _vm.selectedTool) ...[
                                    Icon(CupertinoIcons.checkmark,
                                        size: 16, color: colors.primary),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(tool.label),
                                ],
                              ),
                            ))
                        .toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.wand_stars, size: 18),
                          const SizedBox(width: 7),
                          Text(_vm.selectedTool.label),
                          const SizedBox(width: 5),
                          const Icon(CupertinoIcons.chevron_up, size: 14),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: disabled ||
                              _vm.inputPath == null ||
                              _vm.selectedModel == null
                          ? null
                          : _process,
                      icon: disabled
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(CupertinoIcons.sparkles),
                      label: Text(disabled
                          ? '处理中…'
                          : _vm.selectedTool.consumesAnlas
                              ? '转换（消耗 Anlas）'
                              : '转换'),
                    ),
                  ),
                  if (_vm.outputPath != null) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: '保存到相册',
                      onPressed: disabled ? null : _save,
                      icon: const Icon(CupertinoIcons.square_arrow_down),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(ColorScheme colors) {
    final path = _vm.inputPath;
    return Container(
      width: 58,
      height: 58,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: path == null
          ? Icon(CupertinoIcons.photo, color: colors.onSurfaceVariant)
          : Image.file(File(path), fit: BoxFit.cover),
    );
  }

  Widget _modelDropdown(ColorScheme colors) {
    if (_vm.isLoadingModels) {
      return const LinearProgressIndicator();
    }
    return DropdownButtonFormField<String>(
      value: _vm.availableModels.contains(_vm.selectedModel)
          ? _vm.selectedModel
          : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'ikun NovelAI 模型',
        isDense: true,
      ),
      hint: const Text('无可用模型'),
      items: _vm.availableModels
          .map((model) => DropdownMenuItem(
                value: model,
                child: Text(model, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: _vm.isProcessing ? null : _vm.selectModel,
    );
  }

  Widget _parameterSlider({
    required String title,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 76, child: Text('$title $value')),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged:
                _vm.isProcessing ? null : (next) => onChanged(next.round()),
          ),
        ),
      ],
    );
  }
}
