import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
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
    this.workspaceHeight,
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

  void _resetImageView() {
    _imageController.value = Matrix4.identity();
    setState(() => _imageScale = 1);
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
    return requested.clamp(220.0, 536.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.task;
    final workspaceHeight = _resolvedWorkspaceHeight(context);

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
          else ...[
            _buildImageViewport(context, theme, current, workspaceHeight),
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
          Expanded(
            child: Text(
              '图像工作区',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
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
            tooltip: _imageScale > 1.02 ? '重置缩放' : '适应窗口',
            onPressed: current == null ? null : _resetImageView,
            icon: Icons.fit_screen_outlined,
          ),
          _toolbarButton(
            context: context,
            tooltip: '全屏查看',
            onPressed: current == null ? null : widget.onPreview,
            icon: Icons.open_in_full,
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
    double workspaceHeight,
  ) {
    final glass = FrostedTheme.of(context);
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
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 34,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.generating ? '正在生成' : '图像工作区',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (widget.onImport != null) ...[
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

  Widget _buildImageViewport(
    BuildContext context,
    ThemeData theme,
    GenerationTask current,
    double workspaceHeight,
  ) {
    final glass = FrostedTheme.of(context);
    final gridLine = glass.border.withValues(alpha: 0.04);
    return Semantics(
      container: true,
      label:
          '图像工作区，双指缩放，Seed ${current.seed ?? '未记录'}，${current.width} × ${current.height}',
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
              if (widget.generating)
                Positioned(
                  right: 10,
                  top: 10,
                  child: FrostedSurface(
                    radius: 10,
                    blur: 12,
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
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(14) / 14;
    final metadataStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      key: const ValueKey('result-workspace-metadata'),
      builder: (context, constraints) {
        final shouldStack = constraints.maxWidth < 330 || textScale >= 1.45;
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
          child: shouldStack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [dimensions, seedMetadata],
                )
              : Row(
                  children: [
                    dimensions,
                    const SizedBox(width: 12),
                    Expanded(child: seedMetadata),
                  ],
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
          return Semantics(
            selected: selected,
            button: true,
            label: '查看第 ${index + 1} 张结果',
            child: Tooltip(
              message: '第 ${index + 1} 张结果',
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
                    child: _ResultImage(task: result, thumbnail: true),
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
    canvas.drawColor(background, BlendMode.src);
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
