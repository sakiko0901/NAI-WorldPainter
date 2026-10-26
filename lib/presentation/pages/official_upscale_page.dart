import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

/// Official NovelAI Upscale for a gallery image or a previously saved result.
class OfficialUpscalePage extends StatefulWidget {
  final GenerationTask? initialTask;
  final String? initialImagePath;

  const OfficialUpscalePage({
    super.key,
    this.initialTask,
    this.initialImagePath,
  });

  @override
  State<OfficialUpscalePage> createState() => _OfficialUpscalePageState();
}

class _OfficialUpscalePageState extends State<OfficialUpscalePage> {
  late final GenerationViewModel _generation;
  late final SaveImageUseCase _saveImage;
  final ImagePicker _picker = ImagePicker();
  late String? _sourcePath =
      widget.initialTask?.imagePath ?? widget.initialImagePath;
  late GenerationTask? _sourceTask = widget.initialTask;
  String? _outputPath;
  String? _error;
  int _scale = 2;
  bool _processing = false;
  bool _saving = false;

  bool get _generationBusy =>
      _generation.isGenerating || _generation.isProcessingImage;

  @override
  void initState() {
    super.initState();
    _generation = sl<GenerationViewModel>();
    _saveImage = sl<SaveImageUseCase>();
    _generation.addListener(_onGenerationChanged);
  }

  @override
  void dispose() {
    _generation.removeListener(_onGenerationChanged);
    super.dispose();
  }

  void _onGenerationChanged() {
    if (mounted) setState(() {});
  }

  bool _exists(String? path) => path != null && File(path).existsSync();

  Future<void> _pickImage() async {
    if (_processing || _saving || _generationBusy) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() {
      _sourcePath = picked.path;
      _sourceTask = null;
      _outputPath = null;
      _error = null;
    });
  }

  Future<void> _runUpscale() async {
    final path = _sourcePath;
    if (!_exists(path) || _processing || _saving || _generationBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('开始 $_scale× 官方 Upscale？'),
        content: Text(
          _scale == 4 ? '官方处理会消耗 Anlas，并连续执行两遍。' : '官方处理会消耗 Anlas。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _processing = true;
      _error = null;
      _outputPath = null;
    });
    try {
      final output = await _generation.upscaleFileWithOfficial(
        path!,
        _scale,
        sourceTask: _sourceTask,
      );
      if (mounted) setState(() => _outputPath = output);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('AppException(null): ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _saveOutput() async {
    final path = _outputPath;
    if (!_exists(path) || _saving || _processing || _generationBusy) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await _saveImage.saveToGallery(path!);
    } catch (_) {
      saved = false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) {
      showFloatingToast(
        context,
        saved ? '已保存到相册' : '保存失败',
        icon: saved
            ? CupertinoIcons.checkmark_circle
            : CupertinoIcons.exclamationmark_circle,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shownPath = _exists(_outputPath) ? _outputPath : _sourcePath;
    final hasSource = _exists(_sourcePath);
    final hasOutput = _exists(_outputPath);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NovelAI Upscale'),
        actions: [
          IconButton(
            tooltip: '选择图片',
            onPressed:
                _processing || _saving || _generationBusy ? null : _pickImage,
            icon: const Icon(CupertinoIcons.photo),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildPreview(shownPath, hasSource, hasOutput),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '放大倍率',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment<int>(value: 2, label: Text('2×')),
                        ButtonSegment<int>(value: 4, label: Text('4×')),
                      ],
                      selected: {_scale},
                      onSelectionChanged: _processing ||
                              _saving ||
                              _generationBusy
                          ? null
                          : (values) => setState(() => _scale = values.first),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '使用 NovelAI 官方接口 · 会消耗 Anlas',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (_processing || _generationBusy) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _generation.isGenerating
                              ? '正在生成，暂不可执行 Upscale'
                              : _generation.officialUpscaleStatus ?? '官方超分处理中…',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('official-upscale-run'),
              onPressed:
                  hasSource && !_processing && !_saving && !_generationBusy
                      ? _runUpscale
                      : null,
              icon: _processing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.arrow_up_right_square),
              label: Text(_processing ? '处理中…' : '开始 $_scale× 放大'),
            ),
            if (hasOutput) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving || _processing || _generationBusy
                    ? null
                    : _saveOutput,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.arrow_down_to_line),
                label: Text(_saving ? '保存中…' : '保存到相册'),
              ),
              if (_sourceTask != null) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const ValueKey('official-upscale-return-to-workspace'),
                  onPressed: _processing || _saving || _generationBusy
                      ? null
                      : () => Navigator.of(context).pop(true),
                  icon: const Icon(CupertinoIcons.square_grid_2x2),
                  label: const Text('返回创作工作区'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(String? path, bool hasSource, bool hasOutput) {
    final theme = Theme.of(context);
    final file = path == null ? null : File(path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hasOutput ? '放大结果' : '原图',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed:
                  _processing || _saving || _generationBusy ? null : _pickImage,
              icon: const Icon(CupertinoIcons.photo, size: 17),
              label: Text(hasSource ? '更换' : '选择图片'),
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 360,
            color: theme.colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: file != null && _exists(path)
                ? Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _emptyPreview(
                      '图片无法读取，请重新选择',
                      CupertinoIcons.exclamationmark_triangle,
                    ),
                  )
                : _emptyPreview(
                    widget.initialTask == null &&
                            widget.initialImagePath == null
                        ? '选择一张图片开始'
                        : '原图不可用，请重新选择',
                    CupertinoIcons.photo_on_rectangle,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _emptyPreview(String label, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 42, color: colors.onSurfaceVariant),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }
}
