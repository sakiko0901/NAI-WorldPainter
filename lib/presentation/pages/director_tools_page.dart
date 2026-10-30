import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/director_tool.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/viewmodels/director_tools_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_comparison.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';
import 'package:nai_huishi/presentation/widgets/studio_select.dart';

class DirectorToolsPage extends StatefulWidget {
  final String? initialImagePath;

  const DirectorToolsPage({super.key, this.initialImagePath});

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
    _vm = sl<DirectorToolsViewModel>();
    final initialPath = widget.initialImagePath;
    if (initialPath != null) _vm.selectInput(initialPath);
    _vm.addListener(_changed);
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
    if (image != null && mounted) _vm.selectInput(image.path);
  }

  Future<void> _process() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await _vm.process();
    if (!mounted) return;
    showFloatingToast(context, ok ? '处理完成' : (_vm.errorMessage ?? '处理失败'),
        icon: ok
            ? CupertinoIcons.checkmark_circle_fill
            : CupertinoIcons.exclamationmark_circle);
  }

  Future<void> _save() async {
    final ok = await _vm.saveToGallery();
    if (!mounted) return;
    showFloatingToast(context, ok ? '已保存到相册' : (_vm.errorMessage ?? '保存失败'),
        icon: ok
            ? CupertinoIcons.checkmark_circle_fill
            : CupertinoIcons.exclamationmark_circle);
  }

  @override
  Widget build(BuildContext context) {
    final input = _vm.inputPath;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: StudioBackground(
                image: input == null ? null : FileImage(File(input))),
          ),
          SafeArea(
            child: BackdropGroup(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
                    child: Row(
                      children: [
                        BackButton(
                            onPressed: () => Navigator.maybePop(context)),
                        const SizedBox(width: 4),
                        Text('导演工具',
                            style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      if (constraints.maxWidth >= 720) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Row(children: [
                            Expanded(child: _canvas()),
                            const SizedBox(width: 12),
                            SizedBox(width: 320, child: _controlPanel()),
                          ]),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(children: [
                          Expanded(child: _canvas()),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight * 0.55),
                            child: _controlPanel(),
                          ),
                        ]),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvas() {
    final colors = Theme.of(context).colorScheme;
    final before = _vm.inputPath;
    final after = _vm.outputPath;
    return FrostedSurface(
      radius: 18,
      child: before == null
          ? InkWell(
              onTap: _vm.isProcessing ? null : _pickImage,
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.photo_fill,
                        size: 48, color: colors.onSurfaceVariant),
                    const SizedBox(height: 14),
                    Text('开始导演你的梦',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          : after != null
              ? InpaintComparison(
                  key: ValueKey('director-comparison-$before-$after'),
                  beforePath: before,
                  afterPath: after,
                  beforeLabel: '处理前',
                  afterLabel: '处理后',
                  semanticsLabel: '处理前后滑动对比',
                  fit: BoxFit.contain,
                  afterBackgroundColor: colors.surface,
                  onGestureActive: (_) {},
                )
              : SizedBox.expand(
                  child: Image.file(File(before), fit: BoxFit.contain)),
    );
  }

  Widget _controlPanel() {
    final colors = Theme.of(context).colorScheme;
    final disabled = _vm.isProcessing || _vm.isLoading;
    return FrostedSurface(
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<DirectorChannel>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: DirectorChannel.gateway7877, label: Text('7877')),
                ButtonSegment(value: DirectorChannel.ikun, label: Text('ikun')),
                ButtonSegment(
                    value: DirectorChannel.official, label: Text('官方')),
              ],
              style: SegmentedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              selected: {_vm.selectedChannel},
              onSelectionChanged: disabled
                  ? null
                  : (selection) => _vm.selectChannel(selection.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _thumbnail(),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: disabled ? null : _pickImage,
                icon: const Icon(CupertinoIcons.photo_on_rectangle, size: 18),
                label: const Text('更换图片'),
              ),
            ]),
            const SizedBox(height: 12),
            StudioSelect<DirectorToolType>(
              id: 'director-tool',
              label: '选择工具',
              value: _vm.selectedTool,
              options: [
                for (final tool in _toolOrder)
                  StudioSelectOption(tool, tool.label)
              ],
              onChanged: disabled ? null : _vm.selectTool,
            ),
            if (_vm.selectedTool.usesPrompt) ...[
              const SizedBox(height: 12),
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
            if (_vm.selectedTool.usesDefry) ...[
              const SizedBox(height: 8),
              Text('去噪强度 ${_vm.defry}',
                  style: Theme.of(context).textTheme.bodySmall),
              Slider(
                value: _vm.defry.toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                onChanged:
                    disabled ? null : (next) => _vm.updateDefry(next.round()),
              ),
            ],
            if (_vm.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_vm.errorMessage!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('director-process'),
                  onPressed:
                      disabled || _vm.inputPath == null ? null : _process,
                  icon: _vm.isProcessing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(CupertinoIcons.sparkles),
                  label: Text(_vm.isProcessing
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
            ]),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail() {
    final path = _vm.inputPath;
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: FrostedTheme.of(context).field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FrostedTheme.of(context).border),
      ),
      child: path == null
          ? Icon(CupertinoIcons.photo,
              color: Theme.of(context).colorScheme.onSurfaceVariant)
          : Image.file(File(path), fit: BoxFit.cover),
    );
  }
}
