import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/novelai_route.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/pages/official_upscale_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';
import 'package:nai_huishi/presentation/widgets/fullscreen_image_preview.dart';

enum HistoryPromptReuseScope { positive, negative, both }

enum _DetailMoreAction { inpaint, upscale, enhance }

typedef HistoryPromptReuseCallback = Future<void> Function(
  GenerationTask task,
  HistoryPromptReuseScope scope,
);
typedef HistoryParameterReuseCallback = Future<void> Function(
  GenerationTask task,
);
typedef HistoryDetailImageAction = FutureOr<void> Function(
  GenerationTask task,
);

class HistoryDetailPage extends StatefulWidget {
  final GenerationTask task;
  final ValueChanged<int>? onNavigate;

  /// Optional action seams for widget tests and embedding hosts.
  final HistoryPromptReuseCallback? onReusePrompt;
  final HistoryParameterReuseCallback? onReuseParameters;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final HistoryDetailImageAction? onInpaint;
  final HistoryDetailImageAction? onUpscale;
  final HistoryDetailImageAction? onEnhance;

  const HistoryDetailPage({
    super.key,
    required this.task,
    this.onNavigate,
    this.onReusePrompt,
    this.onReuseParameters,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onInpaint,
    this.onUpscale,
    this.onEnhance,
  });

  @override
  State<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends State<HistoryDetailPage> {
  bool _dialogOpen = false;
  bool _isApplying = false;
  late bool _isFavorite;

  GenerationTask get task => widget.task;

  bool get _generationBusy {
    if (!sl.isRegistered<GenerationViewModel>()) return false;
    final generation = sl<GenerationViewModel>();
    return generation.isGenerating || generation.isProcessingImage;
  }

  bool get _hasImage =>
      (task.imagePath != null && File(task.imagePath!).existsSync()) ||
      (task.imageUrl?.trim().isNotEmpty ?? false);

  bool get _supportsInpaint =>
      task.providerType == ImageProviderType.novelAi && _hasImage;

  bool get _supportsUpscale => _hasImage;

  bool get _supportsEnhance =>
      task.providerType == ImageProviderType.novelAi &&
      NovelAiRoute.fromIds(task.endpointId, task.protocol).isOfficial &&
      _hasImage;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
  }

  void _toggleFavorite() {
    final callback = widget.onToggleFavorite;
    if (callback == null) return;
    setState(() => _isFavorite = !_isFavorite);
    callback();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('作品详情'),
        actions: [
          IconButton(
            tooltip: _isFavorite ? '取消收藏' : '收藏作品',
            onPressed: widget.onToggleFavorite == null ? null : _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.star_rounded : Icons.star_outline,
              color: _isFavorite ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildImageSection(context, theme),
            const SizedBox(height: 14),
            _buildPromptSection(context, theme),
            const SizedBox(height: 10),
            _buildParameterSection(),
            const SizedBox(height: 10),
            _buildSourceSection(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActions(context),
    );
  }

  Widget _buildImageSection(BuildContext context, ThemeData theme) {
    final localPath = task.imagePath;
    final localFile = localPath == null ? null : File(localPath);
    final hasLocalImage = localFile?.existsSync() ?? false;
    final imageUrl = task.imageUrl?.trim();
    final hasImageUrl = imageUrl != null && imageUrl.isNotEmpty;
    final canPreview = hasLocalImage || hasImageUrl;

    Widget imageWidget;
    if (hasLocalImage) {
      imageWidget = Image.file(
        localFile!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _imagePlaceholder(
          theme,
          icon: Icons.broken_image_outlined,
          message: '图片文件无法读取',
        ),
      );
    } else if (hasImageUrl) {
      imageWidget = Image.network(
        imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes == null
                  ? null
                  : progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!,
            ),
          );
        },
        errorBuilder: (_, __, ___) => _imagePlaceholder(
          theme,
          icon: Icons.cloud_off_outlined,
          message: '图片加载失败，请检查网络或图片地址',
        ),
      );
    } else {
      final message =
          localPath != null ? '历史记录中的本地图片不存在，且没有可用的图片地址' : '历史记录没有可预览的图片';
      imageWidget = _imagePlaceholder(
        theme,
        icon: Icons.image_not_supported_outlined,
        message: message,
      );
    }

    final height = (MediaQuery.sizeOf(context).height * 0.46)
        .clamp(300.0, 460.0)
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canPreview ? () => _openImagePreview(context) : null,
            child: Container(
              height: height,
              width: double.infinity,
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF0D0F13)
                  : const Color(0xFF202328),
              alignment: Alignment.center,
              child: imageWidget,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${task.width} × ${task.height}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              'Seed ${task.seed ?? '未记录'}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          task.model,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _imagePlaceholder(
    ThemeData theme, {
    required IconData icon,
    required String message,
  }) {
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    final disabled = _dialogOpen || _isApplying;
    final imageActionsDisabled = disabled || _generationBusy;
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('detail-save-button'),
                onPressed: disabled ? null : () => _saveToGallery(context),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: theme.colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: const Icon(Icons.save_alt, size: 19),
                label: const Text('保存图片'),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<_DetailMoreAction>(
              key: const ValueKey('detail-more-button'),
              tooltip: '更多图片操作',
              onSelected: (action) {
                unawaited(_handleMoreAction(action));
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _DetailMoreAction.inpaint,
                  enabled: !imageActionsDisabled &&
                      (widget.onInpaint != null || _supportsInpaint),
                  child: const Text('导入到局部重绘'),
                ),
                PopupMenuItem(
                  value: _DetailMoreAction.upscale,
                  enabled: !imageActionsDisabled &&
                      (widget.onUpscale != null || _supportsUpscale),
                  child: const Text('Upscale'),
                ),
                PopupMenuItem(
                  value: _DetailMoreAction.enhance,
                  enabled: !imageActionsDisabled &&
                      (widget.onEnhance != null || _supportsEnhance),
                  child: const Text('Enhance'),
                ),
              ],
              child: SizedBox(
                width: 46,
                height: 46,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: const Icon(Icons.more_horiz),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runImageAction(HistoryDetailImageAction action) async {
    await _executeImageAction(() async => action(task));
  }

  Future<void> _handleMoreAction(_DetailMoreAction action) async {
    if (_isApplying) return;
    final callback = switch (action) {
      _DetailMoreAction.inpaint => widget.onInpaint,
      _DetailMoreAction.upscale => widget.onUpscale,
      _DetailMoreAction.enhance => widget.onEnhance,
    };
    if (callback != null) {
      await _runImageAction(callback);
      return;
    }

    await _executeImageAction(() async {
      switch (action) {
        case _DetailMoreAction.inpaint:
          await _importTaskToInpaint();
          break;
        case _DetailMoreAction.upscale:
          await _openOfficialUpscale();
          break;
        case _DetailMoreAction.enhance:
          await _enhanceFromHistory();
          break;
      }
    });
  }

  Future<void> _executeImageAction(Future<void> Function() action) async {
    if (_isApplying) return;
    if (_generationBusy) {
      showFloatingToast(context, '生成或图片处理中，请稍后再试');
      return;
    }
    setState(() => _isApplying = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      showFloatingToast(
        context,
        '操作失败：${error.toString()}',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<String?> _ensureLocalImage() async {
    final path = task.imagePath;
    if (path != null && await File(path).exists()) return path;
    if (task.imageUrl == null || task.imageUrl!.trim().isEmpty) return null;
    return sl<SaveImageUseCase>().execute(task);
  }

  Future<void> _importTaskToInpaint() async {
    if (!_supportsInpaint) {
      showFloatingToast(
        context,
        '当前记录没有可导入的 NovelAI 图片',
        icon: Icons.error_outline,
      );
      return;
    }
    final path = await _ensureLocalImage();
    if (!mounted) return;
    if (path == null) {
      showFloatingToast(context, '当前图片不可用', icon: Icons.error_outline);
      return;
    }
    final generation = sl<GenerationViewModel>();
    final sourceTask = task.copyWith(imagePath: path);
    await generation.importTaskToInpaint(sourceTask);
    _leaveDetailForWorkspace('已导入局部重绘');
  }

  Future<void> _openOfficialUpscale() async {
    if (!_supportsUpscale) {
      showFloatingToast(context, '当前记录没有可用图片', icon: Icons.error_outline);
      return;
    }
    final path = await _ensureLocalImage();
    if (!mounted) return;
    if (path == null) {
      showFloatingToast(context, '当前图片不可用', icon: Icons.error_outline);
      return;
    }
    final sourceTask = task.copyWith(imagePath: path);
    final returnToWorkspace = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OfficialUpscalePage(initialTask: sourceTask),
      ),
    );
    if (!mounted || returnToWorkspace != true) return;
    _leaveDetailForWorkspace('Upscale 完成，已加入创作工作区');
  }

  Future<void> _enhanceFromHistory() async {
    if (!_supportsEnhance) {
      showFloatingToast(
        context,
        'Enhance 仅支持 NovelAI 官方渠道的历史图片',
        icon: Icons.error_outline,
      );
      return;
    }
    final options = await _showEnhanceOptions();
    if (options == null || !mounted) return;
    final imagePath = await _ensureLocalImage();
    if (!mounted) return;
    if (imagePath == null) {
      showFloatingToast(context, '当前图片不可用', icon: Icons.error_outline);
      return;
    }

    final sourceTask = task.copyWith(imagePath: imagePath);
    final generation = sl<GenerationViewModel>();
    GenerationTask? enhanced;
    final succeeded = await generation.enhanceWithOfficial(
      scale: options.$3 ? 1.0 : 1.5,
      strength: options.$1,
      noise: options.$2,
      max: options.$3,
      sourceTask: sourceTask,
      onCompleted: (result) => enhanced = result,
    );
    if (!mounted) return;
    if (!succeeded) {
      showFloatingToast(
        context,
        generation.errorMessage ?? '官方 Enhance 失败',
        icon: Icons.error_outline,
      );
      return;
    }

    final completed = enhanced;
    if (completed == null) {
      showFloatingToast(
        context,
        'Enhance 已完成，但未找到新结果',
        icon: Icons.error_outline,
      );
      return;
    }
    await sl<HistoryRepository>().saveTask(completed);
    _leaveDetailForWorkspace('Enhance 完成，已加入创作工作区');
  }

  void _leaveDetailForWorkspace(String message) {
    if (!mounted) return;
    showFloatingToast(context, message, icon: Icons.check_circle_outline);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
    widget.onNavigate?.call(1);
  }

  Future<(double, double, bool)?> _showEnhanceOptions() async {
    var strength = 0.3;
    var noise = 0.1;
    var max = false;
    return showModalBottomSheet<(double, double, bool)>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(26),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Enhance · 官方重绘放大',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(
                  '将使用此记录的提示词与模型设置。官方处理会消耗 Anlas。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Text('重绘幅度 ${(strength * 100).round()}%'),
                Slider(
                  value: strength,
                  min: 0.05,
                  max: 0.6,
                  divisions: 55,
                  onChanged: (value) => setSheetState(() => strength = value),
                ),
                Text('细节噪声 ${(noise * 100).round()}%'),
                Slider(
                  value: noise,
                  min: 0,
                  max: 0.5,
                  divisions: 50,
                  onChanged: (value) => setSheetState(() => noise = value),
                ),
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Max 放大（V5）'),
                    subtitle: const Text('服务端放大到 2× / 像素上限，消耗 Anlas'),
                    value: max,
                    onChanged: (value) => setSheetState(() => max = value),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          (strength, noise, max),
                        ),
                        child: const Text('开始 Enhance'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptSection(BuildContext context, ThemeData theme) {
    return _DetailSection(
      title: '提示词',
      icon: Icons.notes,
      children: [
        _CopyableText(
          title: '正向提示词',
          value: task.prompt,
          emptyLabel: '（为空）',
          copyKey: const ValueKey('copy-positive-prompt'),
          onCopy: () => _copyText(context, task.prompt),
        ),
        const Divider(height: 24),
        _CopyableText(
          title: '负向提示词',
          value: task.negativePrompt ?? '',
          emptyLabel: task.negativePrompt == null ? '未记录' : '（为空）',
          copyKey: const ValueKey('copy-negative-prompt'),
          onCopy: () => _copyText(context, task.negativePrompt ?? ''),
        ),
        if (task.characters != null && task.characters!.isNotEmpty) ...[
          const Divider(height: 24),
          Text('角色提示词', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          ...task.characters!.asMap().entries.map((entry) {
            final index = entry.key;
            final character = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == task.characters!.length - 1 ? 0 : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CopyableText(
                    title: '角色 ${index + 1} · 正向',
                    value: character.prompt,
                    emptyLabel: '（为空）',
                    copyKey: ValueKey('copy-character-$index-positive'),
                    onCopy: () => _copyText(context, character.prompt),
                  ),
                  const SizedBox(height: 12),
                  _CopyableText(
                    title: '角色 ${index + 1} · 负向',
                    value: character.uc ?? '',
                    emptyLabel: character.uc == null ? '未记录' : '（为空）',
                    copyKey: ValueKey('copy-character-$index-negative'),
                    onCopy: () => _copyText(context, character.uc ?? ''),
                  ),
                  const SizedBox(height: 8),
                  _DetailValue(
                    label: '角色位置',
                    value:
                        character.centerX != null && character.centerY != null
                            ? '(${character.centerX!.toStringAsFixed(2)}, '
                                '${character.centerY!.toStringAsFixed(2)})'
                            : '未记录',
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const ValueKey('reuse-prompts-button'),
            onPressed: _dialogOpen || _isApplying
                ? null
                : () => _confirmPromptReuse(context),
            icon: const Icon(Icons.text_fields, size: 17),
            label: const Text('复用提示词'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParameterSection() {
    final values = <(String, String)>[
      ('画布尺寸', '${task.width} × ${task.height}'),
      ('模型尺寸参数', task.size ?? '未记录'),
      ('Steps', task.steps.toString()),
      ('Scale', task.scale.toStringAsFixed(1)),
      ('CFG Rescale', task.cfgRescale.toStringAsFixed(2)),
      ('采样器', task.sampler),
      ('噪声调度', task.noiseSchedule),
      ('Seed', task.seed?.toString() ?? '未记录'),
      ('使用坐标', task.useCoords ? '是' : '否'),
      ('生成模式', _generationModeName(task.mode)),
      if (task.mode == GenerationMode.inpainting) ...[
        ('重绘强度', task.inpaintStrength?.toStringAsFixed(2) ?? '未记录'),
        ('禁用原图', task.disabledOriginalImage ? '是' : '否'),
        ('颜色校正', task.colorCorrect ? '是' : '否'),
      ],
      if (task.img2imgStrength != null)
        ('图生图强度', task.img2imgStrength!.toStringAsFixed(2)),
      if (task.responseFormat != null) ('响应格式', task.responseFormat!),
      if (task.nanoImageSize != null) ('接口图像尺寸', task.nanoImageSize!),
    ];

    return _DetailSection(
      title: '生成参数',
      icon: Icons.tune,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in values)
                  SizedBox(
                    width: tileWidth,
                    child: _ParameterValue(
                      label: value.$1,
                      value: value.$2,
                      valueKey: value.$1 == 'Seed'
                          ? const ValueKey('parameter-seed-value')
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const ValueKey('reuse-parameters-button'),
            onPressed: _dialogOpen || _isApplying
                ? null
                : () => _confirmParameterReuse(context),
            icon: const Icon(Icons.tune, size: 17),
            label: const Text('复用记录参数'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceSection() {
    final values = <(String, String)>[
      ('任务编号', task.taskId),
      ('服务来源', _providerName(task.providerType)),
      ('模型', task.model),
      ('接口渠道 ID', task.endpointId ?? '未记录'),
      ('接口协议', task.protocol ?? '未记录'),
      ('状态', task.status),
      ('创建时间', task.createdAt.toString()),
      if (task.completedAt != null) ('完成时间', task.completedAt!.toString()),
      if (task.errorMessage != null) ('错误信息', task.errorMessage!),
      if (task.mode == GenerationMode.inpainting &&
          task.sourceImagePath != null)
        ('重绘原图', task.sourceImagePath!),
      if (task.mode == GenerationMode.inpainting && task.maskImagePath != null)
        ('蒙版文件', task.maskImagePath!),
      if (task.img2imgSourceImagePath != null)
        ('图生图来源图', task.img2imgSourceImagePath!),
      if (task.gptImagePaths != null)
        for (final entry in task.gptImagePaths!.asMap().entries)
          ('输入图片 ${entry.key + 1}', entry.value),
      for (final entry in task.vibeReferences.asMap().entries)
        ('Vibe 参考图 ${entry.key + 1}', entry.value.path),
      for (final entry in task.preciseReferences.asMap().entries)
        (
          'Precise Reference ${entry.key + 1}',
          '${entry.value.path} · ${entry.value.referenceType} · '
              '强度 ${entry.value.strength.toStringAsFixed(2)}',
        ),
      if (task.characters != null)
        for (final characterEntry in task.characters!.asMap().entries)
          for (final referenceEntry
              in characterEntry.value.referenceImages.asMap().entries)
            (
              '角色 ${characterEntry.key + 1} 参考图 ${referenceEntry.key + 1}',
              '${referenceEntry.value.path} · 强度 '
                  '${referenceEntry.value.strength.toStringAsFixed(2)}',
            ),
    ];

    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        leading: Icon(
          Icons.account_tree_outlined,
          color: theme.colorScheme.primary,
          size: 20,
        ),
        title: Text('来源与记录', style: theme.textTheme.titleSmall),
        subtitle: Text(
          '${_providerName(task.providerType)} · ${task.createdAt.toLocal()}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          for (final value in values)
            _DetailValue(label: value.$1, value: value.$2),
        ],
      ),
    );
  }

  String _generationModeName(GenerationMode mode) => switch (mode) {
        GenerationMode.textToImage => '文生图',
        GenerationMode.inpainting => '局部重绘',
      };

  String _providerName(ImageProviderType provider) => switch (provider) {
        ImageProviderType.novelAi => 'NovelAI',
        ImageProviderType.gpt => 'GPT 图像服务',
        ImageProviderType.nanoBanana => 'Nano Banana',
      };

  Future<void> _copyText(BuildContext context, String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!context.mounted) return;
      showFloatingToast(context, '已复制到剪贴板', icon: Icons.content_copy);
    } catch (_) {
      if (!context.mounted) return;
      showFloatingToast(context, '复制失败', icon: Icons.error_outline);
    }
  }

  Future<void> _confirmPromptReuse(BuildContext context) async {
    if (_dialogOpen || _isApplying) return;
    setState(() => _dialogOpen = true);
    final scope = await showDialog<HistoryPromptReuseScope>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('复用提示词到创作页'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '会覆盖创作页中所选的提示词输入框。记录中的空字段也会写入，'
              '因此可用于清空对应输入框。操作完成后进入创作页，不会自动生成，'
              '也不会主动切换当前结果图。',
            ),
            const SizedBox(height: 16),
            _reuseChoiceButton(
              dialogContext,
              label: '仅正向提示词',
              scope: HistoryPromptReuseScope.positive,
            ),
            const SizedBox(height: 8),
            _reuseChoiceButton(
              dialogContext,
              label: '仅负向提示词',
              scope: HistoryPromptReuseScope.negative,
            ),
            const SizedBox(height: 8),
            _reuseChoiceButton(
              dialogContext,
              label: '正向与负向提示词',
              scope: HistoryPromptReuseScope.both,
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-prompt-reuse'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (scope == null) return;

    await _runReuse(() async {
      final callback = widget.onReusePrompt;
      if (callback != null) {
        await callback(task, scope);
        return;
      }

      final viewModel = sl<GenerationViewModel>();
      switch (scope) {
        case HistoryPromptReuseScope.positive:
          await viewModel.updatePrompt(task.prompt);
          break;
        case HistoryPromptReuseScope.negative:
          await viewModel.updateNegativePrompt(task.negativePrompt ?? '');
          break;
        case HistoryPromptReuseScope.both:
          await Future.wait([
            viewModel.updatePrompt(task.prompt),
            viewModel.updateNegativePrompt(task.negativePrompt ?? ''),
          ]);
          break;
      }
    }, successMessage: '已复用提示词');
  }

  Widget _reuseChoiceButton(
    BuildContext dialogContext, {
    required String label,
    required HistoryPromptReuseScope scope,
  }) {
    return OutlinedButton(
      key: ValueKey('reuse-prompt-${scope.name}'),
      onPressed: () => Navigator.of(dialogContext).pop(scope),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(label),
    );
  }

  Future<void> _confirmParameterReuse(BuildContext context) async {
    if (_dialogOpen || _isApplying) return;
    setState(() => _dialogOpen = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('按记录恢复参数？'),
        content: const Text(
          '旧复用方法会恢复其支持的记录字段：模型、尺寸、Scale、CFG Rescale、'
          '采样器、噪声调度、Seed、正负向提示词（按记录模式），以及文生图记录中的角色词；'
          '并按记录内容尝试恢复引用图、局部重绘等字段。Steps、批量数量等未由该方法处理的字段不会恢复。'
          '范围受历史记录和现有方法支持限制。不会自动生成，也不会主动切换当前结果图。',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-parameter-reuse'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('取消'),
          ),
          ElevatedButton(
            key: const ValueKey('confirm-parameter-reuse'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('确认复用'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (confirmed != true) return;

    await _runReuse(() async {
      final callback = widget.onReuseParameters;
      if (callback != null) {
        await callback(task);
      } else {
        await sl<GenerationViewModel>().loadFromHistory(task);
      }
    }, successMessage: '已恢复记录字段');
  }

  Future<void> _runReuse(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    try {
      await action();
      if (!mounted) return;
      showFloatingToast(
        context,
        successMessage,
        icon: Icons.check_circle_outline,
      );
      Navigator.of(context).pop();
      final onNavigate = widget.onNavigate;
      onNavigate?.call(1);
    } catch (_) {
      if (!mounted) return;
      showFloatingToast(context, '复用失败，请重试', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _saveToGallery(BuildContext context) async {
    try {
      final saveUseCase = sl<SaveImageUseCase>();
      if (task.imagePath != null && await File(task.imagePath!).exists()) {
        final saved = await saveUseCase.saveToGallery(task.imagePath!);
        if (!context.mounted) return;
        showFloatingToast(
          context,
          saved ? '已保存到相册' : '保存失败',
          icon: Icons.save_alt,
        );
      } else if (task.imageUrl != null && task.imageUrl!.trim().isNotEmpty) {
        final filePath = await saveUseCase.execute(task);
        final saved = await saveUseCase.saveToGallery(filePath);
        if (!context.mounted) return;
        showFloatingToast(
          context,
          saved ? '已保存到相册' : '保存失败',
          icon: Icons.save_alt,
        );
      } else {
        showFloatingToast(context, '没有可保存的图片', icon: Icons.error_outline);
      }
    } catch (_) {
      if (!context.mounted) return;
      showFloatingToast(context, '保存失败', icon: Icons.error_outline);
    }
  }

  void _openImagePreview(BuildContext context) {
    showFullscreenImagePreview(
      context,
      imagePath: task.imagePath,
      imageUrl: task.imageUrl,
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CopyableText extends StatelessWidget {
  final String title;
  final String value;
  final String emptyLabel;
  final Key copyKey;
  final VoidCallback onCopy;

  const _CopyableText({
    required this.title,
    required this.value,
    required this.emptyLabel,
    required this.copyKey,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            IconButton(
              key: copyKey,
              tooltip: '复制$title',
              onPressed: onCopy,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
        SelectableText(
          value.isEmpty ? emptyLabel : value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: value.isEmpty ? colors.onSurfaceVariant : colors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ParameterValue extends StatelessWidget {
  final String label;
  final String value;
  final Key? valueKey;

  const _ParameterValue({
    required this.label,
    required this.value,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            key: valueKey,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailValue extends StatelessWidget {
  final String label;
  final String value;

  const _DetailValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
