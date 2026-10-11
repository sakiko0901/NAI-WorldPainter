import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

typedef GenerationResultAction = FutureOr<void> Function(GenerationTask task);

enum _ResultMoreAction { inpaint, upscale, enhance }

/// The displayed result owns every action. Draft parameters are never used as
/// metadata for an existing image.
class GenerationResultCard extends StatelessWidget {
  final GenerationTask? task;
  final List<GenerationTask> results;
  final String? error;
  final bool generating;
  final ValueChanged<GenerationTask> onSelect;
  final VoidCallback? onPreview;
  final VoidCallback? onSave;
  final GenerationResultAction? onInpaint;
  final GenerationResultAction? onUpscale;
  final GenerationResultAction? onEnhance;

  const GenerationResultCard({
    super.key,
    required this.task,
    this.results = const [],
    this.error,
    this.generating = false,
    required this.onSelect,
    this.onPreview,
    this.onSave,
    this.onInpaint,
    this.onUpscale,
    this.onEnhance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = task;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, theme, current),
            if (error != null && error!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildError(theme),
            ],
            const SizedBox(height: 10),
            if (current == null)
              _buildEmptyState(theme)
            else ...[
              _buildImageViewport(context, current),
              const SizedBox(height: 9),
              _buildImageMetadata(context, current),
              if (results.length > 1) ...[
                const SizedBox(height: 9),
                _buildThumbnails(context, theme, current),
              ],
              const SizedBox(height: 10),
              _buildActions(context, current),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    GenerationTask? current,
  ) {
    final colors = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '图像工作区',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
            ),
          ),
        ),
        if (results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              '${current == null ? 0 : results.indexWhere((item) => item.taskId == current.taskId) + 1} / ${results.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        IconButton(
          tooltip: '全屏查看',
          onPressed: current == null ? null : onPreview,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: const Icon(Icons.open_in_full, size: 18),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
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
                error!,
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

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 34,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            generating ? '正在绘制你的想象…' : '写下灵感，生成第一张作品',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 5),
          Text(
            '在下方编辑提示词，或让 AI 助手帮你构思。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageViewport(BuildContext context, GenerationTask current) {
    final media = MediaQuery.of(context);
    final availableHeight = (media.size.height - media.viewInsets.bottom)
        .clamp(320.0, 1200.0)
        .toDouble();
    final viewportHeight =
        (availableHeight * 0.42).clamp(300.0, 470.0).toDouble();
    return Semantics(
      button: true,
      label: '全屏查看当前结果',
      child: InkWell(
        onTap: onPreview,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: viewportHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: themePanelColor(context),
            borderRadius: BorderRadius.circular(13),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 170),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: SizedBox.expand(
              key: ValueKey(current.taskId),
              child: _ResultImage(task: current),
            ),
          ),
        ),
      ),
    );
  }

  Color themePanelColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0D0F13)
          : const Color(0xFF202328);

  Widget _buildImageMetadata(BuildContext context, GenerationTask current) {
    final theme = Theme.of(context);
    final metadataStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${current.width} × ${current.height}',
                  style: metadataStyle),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
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
                      width: 32,
                      height: 28,
                      child: IconButton(
                        tooltip: '复制记录的 Seed',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: current.seed.toString()),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Seed 已复制')),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined, size: 15),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (generating)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 7, color: theme.colorScheme.primary),
              const SizedBox(width: 5),
              Text('已就绪', style: metadataStyle),
            ],
          ),
      ],
    );
  }

  Widget _buildThumbnails(
    BuildContext context,
    ThemeData theme,
    GenerationTask current,
  ) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: results.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final result = results[index];
          final selected = current.taskId == result.taskId;
          return Semantics(
            selected: selected,
            button: true,
            label: '查看第 ${index + 1} 张结果',
            child: Tooltip(
              message: '第 ${index + 1} 张结果',
              child: InkWell(
                onTap: () => onSelect(result),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
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
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('result-save-button'),
            onPressed: onSave,
            icon: const Icon(Icons.save_alt, size: 19),
            label: const Text('保存图片'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
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
              _ResultMoreAction.inpaint => onInpaint,
              _ResultMoreAction.upscale => onUpscale,
              _ResultMoreAction.enhance => onEnhance,
            };
            if (callback != null)
              unawaited(Future.sync(() => callback(current)));
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ResultMoreAction.inpaint,
              enabled: onInpaint != null,
              child: const Text('导入到局部重绘'),
            ),
            PopupMenuItem(
              value: _ResultMoreAction.upscale,
              enabled: onUpscale != null,
              child: const Text('Upscale'),
            ),
            PopupMenuItem(
              value: _ResultMoreAction.enhance,
              enabled: onEnhance != null,
              child: const Text('Enhance'),
            ),
          ],
          child: SizedBox(
            height: 46,
            width: 46,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border:
                    Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: const Icon(Icons.more_horiz),
            ),
          ),
        ),
      ],
    );
  }
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
