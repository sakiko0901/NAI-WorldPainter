import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/online_gallery.dart';
import 'package:nai_huishi/domain/repositories/online_gallery_repository.dart';

/// Loads gallery media through the repository's bounded local preview cache.
/// The widget does not issue an independent network request while scrolling.
class OnlineGalleryImage extends StatefulWidget {
  const OnlineGalleryImage({
    super.key,
    required this.repository,
    required this.item,
    required this.media,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.backgroundColor,
    this.semanticLabel,
    this.compact = false,
  });

  final OnlineGalleryRepository repository;
  final OnlineGalleryItem item;
  final OnlineGalleryMedia media;
  final BoxFit fit;
  final Alignment alignment;
  final Color? backgroundColor;
  final String? semanticLabel;
  final bool compact;

  @override
  State<OnlineGalleryImage> createState() => _OnlineGalleryImageState();
}

class _OnlineGalleryImageState extends State<OnlineGalleryImage> {
  late Future<String?> _pathFuture;
  int _loadSequence = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OnlineGalleryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.item.key != widget.item.key ||
        oldWidget.media.id != widget.media.id ||
        oldWidget.media.previewUrl != widget.media.previewUrl ||
        oldWidget.media.displayUrl != widget.media.displayUrl) {
      _load();
    }
  }

  void _load() {
    final sequence = ++_loadSequence;
    _pathFuture = widget.repository.previewPath(widget.item, widget.media).then(
          (path) => sequence == _loadSequence ? path : null,
        );
  }

  void _retry() => setState(_load);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = widget.backgroundColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
    return ColoredBox(
      color: background,
      child: FutureBuilder<String?>(
        future: _pathFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: widget.compact
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const CircularProgressIndicator(),
            );
          }

          final path = snapshot.data;
          if (snapshot.hasError || path == null || path.isEmpty) {
            return _ImageUnavailable(
              compact: widget.compact,
              onRetry: _retry,
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final cacheWidth = constraints.maxWidth.isFinite
                  ? (constraints.maxWidth *
                          MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(64, 1600)
                      .toInt()
                  : null;
              return Image.file(
                File(path),
                fit: widget.fit,
                alignment: widget.alignment,
                semanticLabel: widget.semanticLabel,
                cacheWidth: cacheWidth,
                errorBuilder: (_, __, ___) => _ImageUnavailable(
                  compact: widget.compact,
                  onRetry: _retry,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable({required this.compact, required this.onRetry});

  final bool compact;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    if (compact) {
      return Center(
        child: Icon(Icons.image_not_supported_outlined, size: 24, color: color),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 34, color: color),
          const SizedBox(height: 6),
          Text('图片加载失败', style: Theme.of(context).textTheme.labelMedium),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('重试'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
          ),
        ],
      ),
    );
  }
}
