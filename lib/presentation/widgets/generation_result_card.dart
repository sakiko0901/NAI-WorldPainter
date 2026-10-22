import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';

typedef GenerationResultAction = FutureOr<void> Function(GenerationTask task);

enum _ResultMoreAction { inpaint, upscale, enhance }

/// Shows the selected generation result and actions for that exact task.
/// Draft parameters are never used as metadata for an existing image.
class GenerationResultCard extends StatefulWidget {
  final GenerationTask? task;
  final List<GenerationTask> results;
  final String? error;
  final bool generating;
  final ValueChanged<GenerationTask> onSelect;
  final VoidCallback? onPreview;
  final VoidCallback? onImport;
  final VoidCallback? onSave;
  final GenerationResultAction? onInpaint;
  final GenerationResultAction? onUpscale;
  final GenerationResultAction? onEnhance;

  /// Optional image-stage height selected by the parent page. When omitted,
  /// the stage grows with the available window height and remains capped.
  final double? workspaceHeight;

  /// V5 Full Effort 等级（High/Medium），为 null 时不显示切换按钮。
  final GenerationEffort? effort;
  final ValueChanged<GenerationEffort>? onEffortChanged;

  /// 删除当前工作区显示的图像（由页面给出确认弹窗）。
  final GenerationResultAction? onDelete;

  /// 官方渠道流式预览帧（JPEG 字节），生成中实时刷新；为 null 显示占位。
  final Uint8List? streamPreviewBytes;
  final int? streamPreviewStep;

  const GenerationResultCard({
    super.key,
    required this.task,
    this.results = const [],
    this.error,
    this.generating = false,
    required this.onSelect,
    this.onPreview,
    this.onImport,
    this.onSave,
    this.onInpaint,
    this.onUpscale,
    this.onEnhance,
    this.onDelete,
    this.workspaceHeight,
    this.effort,
    this.onEffortChanged,
    this.streamPreviewBytes,
    this.streamPreviewStep,
  });

  @override
  State<GenerationResultCard> createState() => _GenerationResultCardState();
}

class _GenerationResultCardState extends State<GenerationResultCard> {
  late final TransformationController _imageController;
  double _imageScale = 1;

  @override
  void initState() {
    super.initState();
    _imageController = TransformationController();
  }

  @override
  void didUpdateWidget(covariant GenerationResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_imageIdentity(oldWidget.task) != _imageIdentity(widget.task)) {
      _imageController.value = Matrix4.identity();
      _imageScale = 1;
    }
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  String? _imageIdentity(GenerationTask? task) {
    if (task == null) return null;
    return '${task.taskId}\u0000${task.imagePath ?? ''}\u0000${task.imageUrl ?? ''}';
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    final nextScale = _imageController.value.getMaxScaleOnAxis();
    if ((nextScale - _imageScale).abs() < 0.02) return;
    setState(() => _imageScale = nextScale);
  }

  double _resolvedWorkspaceHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.bottom;
    final textScaleExtra =
        ((media.textScaler.scale(14) - 14) * 5).clamp(0.0, 72.0);
    final requested =
        widget.workspaceHeight ?? availableHeight - 424 - textScaleExtra;
    final maxHeight = (availableHeight * 0.85).clamp(536.0, double.infinity);
    return requested
        .clamp(widget.task == null ? 220.0 : 160.0, maxHeight)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.task;
    final workspaceHeight = _resolvedWorkspaceHeight(context);
    // 占位卡：任务存在但还没有本地/网络图片（pending/generating），
    // 有流式帧就实时显示，否则显示生成中占位。
    final isPlaceholder = current != null &&
        (current.imagePath == null || !File(current.imagePath!).existsSync()) &&
        (current.imageUrl == null || current.imageUrl!.trim().isEmpty);

    return FrostedSurface(
      radius: 16,
      blur: 18,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, theme, current),
          if (widget.error != null && widget.error!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildError(theme),
          ],
          const SizedBox(height: 8),
          if (current == null)
            _buildEmptyState(context, theme, workspaceHeight)
          else if (isPlaceholder && widget.generating) ...[
            // 选中项是生成中的占位卡：显示流式帧/转圈，
            // 缩略图条保留，用户可随时切回旧图。
            widget.streamPreviewBytes != null
                ? _buildStreamPreview(context, theme, workspaceHeight)
                : _buildEmptyState(context, theme, workspaceHeight,
                    generating: true),
            if (widget.results.length > 1) ...[
              const SizedBox(height: 6),
              _buildThumbnails(context, theme, current),
            ],
          ] else ...[
            _buildImageViewport(
              context,
              theme,
              current,
              workspaceHeight,
              isPlaceholder: isPlaceholder,
            ),
            const SizedBox(height: 4),
            _buildImageMetadata(context, theme, current),
            if (widget.results.length > 1) ...[
              const SizedBox(height: 6),
              _buildThumbnails(context, theme, current),
            ],
            const SizedBox(height: 8),
            _buildActions(context, current),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    GenerationTask? current,
  ) {
    final colors = theme.colorScheme;
    final selectedIndex = current == null
        ? -1
        : widget.results.indexWhere((item) => item.taskId == current.taskId);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (widget.effort != null && widget.onEffortChanged != null)
            _EffortToggle(
              effort: widget.effort!,
              onChanged: widget.onEffortChanged!,
            ),
          const Spacer(),
          if (widget.results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text(
                '${selectedIndex < 0 ? 0 : selectedIndex + 1} / ${widget.results.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (widget.onImport != null)
            _toolbarButton(
              context: context,
              tooltip: '导入新图片',
              onPressed: widget.onImport,
              icon: Icons.add_photo_alternate_outlined,
            ),
          _toolbarButton(
            context: context,
            tooltip: '删除当前图片',
            onPressed:
                widget.generating || current == null || widget.onDelete == null
                    ? null
                    : () => widget.onDelete!(current),
            icon: Icons.delete_outline,
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required BuildContext context,
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        style: IconButton.styleFrom(
          minimumSize: const Size(34, 34),
          maximumSize: const Size(34, 34),
          padding: EdgeInsets.zero,
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              size: 19,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    double workspaceHeight, {
    bool generating = false,
  }) {
    final glass = FrostedTheme.of(context);
    final showGenerating = generating || widget.generating;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        key: const ValueKey('result-workspace-empty'),
        height: workspaceHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: _WorkspaceGridPainter(
            background: glass.stage,
            line: glass.border.withValues(alpha: 0.04),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showGenerating) ...[
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 12),
                  ] else
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 34,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    showGenerating ? '正在生成' : '图像工作区',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (!showGenerating && widget.onImport != null) ...[
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      key: const ValueKey('result-import-button'),
                      onPressed: widget.onImport,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('导入图片'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 生成中的流式预览：显示官方渠道返回的中间帧（JPEG）。
  Widget _buildStreamPreview(
    BuildContext context,
    ThemeData theme,
    double workspaceHeight,
  ) {
    final glass = FrostedTheme.of(context);
    final bytes = widget.streamPreviewBytes!;
    final step = widget.streamPreviewStep;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        key: const ValueKey('result-workspace-preview'),
        height: workspaceHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _WorkspaceGridPainter(
                background: glass.stage,
                line: glass.border.withValues(alpha: 0.04),
              ),
            ),
            Center(
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      step != null ? '流式预览 · 第 $step 步' : '流式预览',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageViewport(
    BuildContext context,
    ThemeData theme,
    GenerationTask current,
    double workspaceHeight, {
    bool isPlaceholder = false,
  }) {
    final glass = FrostedTheme.of(context);
    final gridLine = glass.border.withValues(alpha: 0.04);
    return Semantics(
      container: true,
      label:
          '图像工作区，点按全屏查看，双指缩放，Seed ${current.seed ?? '未记录'}，${current.width} × ${current.height}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          key: const ValueKey('result-workspace-stage'),
          height: workspaceHeight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _WorkspaceGridPainter(
                  background: glass.stage,
                  line: gridLine,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onPreview,
                child: InteractiveViewer(
                  key: const ValueKey('result-image-viewer'),
                  transformationController: _imageController,
                  minScale: 1,
                  maxScale: 5,
                  boundaryMargin: EdgeInsets.zero,
                  onInteractionUpdate: _handleInteractionUpdate,
                  child: SizedBox.expand(
                    child: Center(child: _ResultImage(task: current)),
                  ),
                ),
              ),
              // 仅当选中的还是生成中的占位卡时才提示"正在生成"，
              // 查看旧图时不打扰。
              if (widget.generating && isPlaceholder)
                Positioned(
                  right: 10,
                  top: 10,
                  child: FrostedSurface(
                    radius: 10,
                    blur: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.7,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text('正在生成', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageMetadata(
    BuildContext context,
    ThemeData theme,
    GenerationTask current,
  ) {
    final metadataStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      key: const ValueKey('result-workspace-metadata'),
      builder: (context, constraints) {
        final seedMetadata = Row(
          children: [
            Flexible(
              child: Text(
                'Seed ${current.seed ?? '未记录'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metadataStyle,
              ),
            ),
            if (current.seed != null) ...[
              const SizedBox(width: 2),
              SizedBox(
                width: 25,
                height: 24,
                child: IconButton(
                  tooltip: '复制记录的 Seed',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(25, 24),
                    maximumSize: const Size(25, 24),
                    padding: EdgeInsets.zero,
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: current.seed.toString()),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Seed 已复制')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: 14),
                ),
              ),
            ],
          ],
        );
        final dimensions = Text(
          '${current.width} × ${current.height}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: metadataStyle,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [dimensions, seedMetadata],
          ),
        );
      },
    );
  }

  Widget _buildThumbnails(
    BuildContext context,
    ThemeData theme,
    GenerationTask current,
  ) {
    final glass = FrostedTheme.of(context);
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.results.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final result = widget.results[index];
          final selected = current.taskId == result.taskId;
          // 占位（生成中）：无任何图片来源的任务。仅在生成期间显示转圈。
          final isPending = widget.generating &&
              result.imagePath == null &&
              (result.imageUrl == null || result.imageUrl!.trim().isEmpty);
          return Semantics(
            selected: selected,
            button: true,
            label: '查看第 ${index + 1} 张结果',
            child: Tooltip(
              message:
                  isPending ? '第 ${index + 1} 张（生成中）' : '第 ${index + 1} 张结果',
              child: InkWell(
                onTap: () => widget.onSelect(result),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  width: 46,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: selected ? glass.selection : glass.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: isPending
                        ? Container(
                            color: glass.stage,
                            child: Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          )
                        : _ResultImage(task: result, thumbnail: true),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActions(BuildContext context, GenerationTask current) {
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            key: const ValueKey('result-save-button'),
            onPressed: widget.onSave,
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('保存图片'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              backgroundColor: glass.raised,
              foregroundColor: theme.colorScheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
                side: BorderSide(
                  color: glass.border,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_ResultMoreAction>(
          key: const ValueKey('result-more-button'),
          tooltip: '更多图片操作',
          onSelected: (action) {
            final callback = switch (action) {
              _ResultMoreAction.inpaint => widget.onInpaint,
              _ResultMoreAction.upscale => widget.onUpscale,
              _ResultMoreAction.enhance => widget.onEnhance,
            };
            if (callback != null) {
              unawaited(Future.sync(() => callback(current)));
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ResultMoreAction.inpaint,
              enabled: widget.onInpaint != null,
              child: const Text('导入到局部重绘'),
            ),
            PopupMenuItem(
              value: _ResultMoreAction.upscale,
              enabled: widget.onUpscale != null,
              child: const Text('Upscale'),
            ),
            PopupMenuItem(
              value: _ResultMoreAction.enhance,
              enabled: widget.onEnhance != null,
              child: const Text('Enhance'),
            ),
          ],
          child: SizedBox(
            height: 44,
            width: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: glass.raised,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: glass.border,
                ),
              ),
              child: Icon(
                Icons.more_horiz,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkspaceGridPainter extends CustomPainter {
  final Color background;
  final Color line;

  const _WorkspaceGridPainter({required this.background, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    // This painter can share a canvas with the glass panel's backdrop. Source
    // replacement erases that backdrop and changes appearance when the engine
    // moves the grid into or out of a cached layer. Composite within our bounds.
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..color = line
      ..strokeWidth = 0.65;
    const step = 24.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkspaceGridPainter oldDelegate) =>
      background != oldDelegate.background || line != oldDelegate.line;
}

class _ResultImage extends StatelessWidget {
  final GenerationTask task;
  final bool thumbnail;

  const _ResultImage({required this.task, this.thumbnail = false});

  @override
  Widget build(BuildContext context) {
    final fit = thumbnail ? BoxFit.cover : BoxFit.contain;
    Widget unavailable() => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: thumbnail
                ? const Icon(Icons.broken_image_outlined)
                : Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_outlined, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          '图片暂不可用，提示词与参数仍可查看',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
          ),
        );
    if (task.imagePath != null && File(task.imagePath!).existsSync()) {
      return Image.file(
        File(task.imagePath!),
        fit: fit,
        cacheWidth: thumbnail ? 192 : null,
        errorBuilder: (_, __, ___) => unavailable(),
      );
    }
    if (task.imageUrl != null && task.imageUrl!.trim().isNotEmpty) {
      return Image.network(
        task.imageUrl!,
        fit: fit,
        cacheWidth: thumbnail ? 192 : null,
        errorBuilder: (_, __, ___) => unavailable(),
      );
    }
    return unavailable();
  }
}

/// V5 Effort 等级左右切换控件（High ⇄ Medium），点击或左右滑动切换。
class _EffortToggle extends StatelessWidget {
  final GenerationEffort effort;
  final ValueChanged<GenerationEffort> onChanged;

  const _EffortToggle({required this.effort, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isHigh = effort == GenerationEffort.high;
    return Tooltip(
      message: isHigh
          ? '思考等级：High（完整模型，点击切换 Medium 节约模式）'
          : '思考等级：Medium（蒸馏版，固定 14 步，点击切换 High）',
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120 && isHigh) {
            onChanged(GenerationEffort.medium);
          } else if (velocity > 120 && !isHigh) {
            onChanged(GenerationEffort.high);
          }
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(
            isHigh ? GenerationEffort.medium : GenerationEffort.high,
          ),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isHigh
                  ? colors.primary.withValues(alpha: 0.14)
                  : colors.tertiary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                width: 1,
                color: isHigh
                    ? colors.primary.withValues(alpha: 0.45)
                    : colors.tertiary.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHigh ? Icons.psychology : Icons.bolt,
                  size: 14,
                  color: isHigh ? colors.primary : colors.tertiary,
                ),
                const SizedBox(width: 5),
                Text(
                  isHigh ? 'High' : 'Medium',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isHigh ? colors.primary : colors.tertiary,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  isHigh ? Icons.arrow_forward_ios : Icons.arrow_back_ios,
                  size: 10,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
