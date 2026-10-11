import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/daily_stats_local_datasource.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/pages/history_detail_page.dart';
import 'package:nai_huishi/presentation/viewmodels/history_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/fullscreen_image_preview.dart';

class HistoryPage extends StatefulWidget {
  final ValueChanged<int>? onNavigate;
  final HistoryDetailImageAction? onInpaint;
  final HistoryDetailImageAction? onUpscale;
  final HistoryDetailImageAction? onEnhance;

  const HistoryPage({
    super.key,
    this.onNavigate,
    this.onInpaint,
    this.onUpscale,
    this.onEnhance,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HistoryViewModel _vm;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late final DailyStatsLocalDatasource _dailyStats;
  String _searchQuery = '';
  bool _showFavorites = false;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _vm = sl<HistoryViewModel>();
    _dailyStats = sl<DailyStatsLocalDatasource>();
    _vm.addListener(_onVmChanged);
    _vm.loadHistory(refresh: true);
    _vm.loadFavorites();
    _scrollController.addListener(_onScroll);
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_showFavorites &&
        _searchQuery.isEmpty &&
        _scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      if (_vm.hasMore && !_vm.isLoading) {
        _vm.loadHistory();
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchTimer?.cancel();
    if (_showFavorites || value.trim().isEmpty) return;
    _searchTimer = Timer(const Duration(milliseconds: 280), () {
      unawaited(_loadAllHistoryForSearch());
    });
  }

  Future<void> _loadAllHistoryForSearch() async {
    if (!mounted || _showFavorites || _searchQuery.trim().isEmpty) return;
    if (_vm.isLoading) {
      _searchTimer = Timer(const Duration(milliseconds: 100), () {
        unawaited(_loadAllHistoryForSearch());
      });
      return;
    }
    while (mounted &&
        !_showFavorites &&
        _searchQuery.trim().isNotEmpty &&
        _vm.hasMore) {
      final countBefore = _vm.history.length;
      await _vm.loadHistory();
      if (_vm.history.length == countBefore) break;
    }
  }

  List<GenerationTask> get _visibleHistory {
    final source = _showFavorites ? _vm.favorites : _vm.history;
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((task) {
      final searchable = [
        task.prompt,
        task.negativePrompt ?? '',
        task.model,
        task.seed?.toString() ?? '',
      ].join('\n').toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  bool _isFavorite(String taskId) =>
      _vm.favorites.any((item) => item.taskId == taskId);

  Future<void> _toggleFavorite(String taskId) async {
    await _vm.toggleFavorite(taskId);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _searchTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 每日生成成功统计弹窗：今日数量 + 最近 7 天明细。
  Future<void> _showDailyStatsSheet() async {
    final now = DateTime.now().toLocal();
    final todayCount = await _dailyStats.getSuccessCount(now);
    final recent = await _dailyStats.getRecentCounts(days: 7);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '每日生成统计',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '记录生成成功的图像数量，每日 0 点重置，长期保留。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.sparkles,
                      size: 22,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$todayCount',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '今日生成成功',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (recent.isEmpty)
                  Text(
                    '最近 7 天暂无记录',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  Text(
                    '最近 7 天',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...recent.entries.map((entry) {
                    final parts = entry.key.split('-');
                    final month = int.tryParse(parts[1]) ?? 0;
                    final day = int.tryParse(parts[2]) ?? 0;
                    final date = DateTime(
                      int.tryParse(parts[0]) ?? now.year,
                      month,
                      day,
                    );
                    final isToday = entry.key == _dateKey(now);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              '$month/$day 周${weekdays[date.weekday - 1]}'
                              '${isToday ? ' · 今' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: todayCount > 0
                                    ? (entry.value / todayCount).clamp(0.0, 1.0)
                                    : (entry.value > 0 ? 1.0 : 0.0),
                                minHeight: 6,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.08,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${entry.value}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _dateKey(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final visibleHistory = _visibleHistory;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.photo_on_rectangle, size: 18),
            SizedBox(width: 6),
            Text(
              '历史画廊',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '每日生成统计',
            icon: const Icon(CupertinoIcons.chart_bar, size: 20),
            onPressed: _showDailyStatsSheet,
          ),
          IconButton(
            tooltip: '清空历史',
            icon: const Icon(CupertinoIcons.trash, size: 20),
            onPressed: _vm.history.isEmpty
                ? null
                : () async {
                    final confirmed = await showCupertinoDialog<bool>(
                      context: context,
                      builder: (ctx) => CupertinoAlertDialog(
                        title: const Text('清空历史记录'),
                        content: const Text(
                          '只会清空历史列表，不会删除已保存到本地或系统相册的图片。是否继续？',
                        ),
                        actions: [
                          CupertinoDialogAction(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          CupertinoDialogAction(
                            onPressed: () => Navigator.pop(ctx, true),
                            isDestructiveAction: true,
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _vm.clearHistory();
                    }
                  },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _vm.loadHistory(refresh: true);
          await _vm.loadFavorites();
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索作品或提示词',
                    prefixIcon: const Icon(CupertinoIcons.search, size: 19),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: !_showFavorites,
                      onSelected: (_) {
                        setState(() => _showFavorites = false);
                        if (_searchQuery.trim().isNotEmpty) {
                          _onSearchChanged(_searchQuery);
                        }
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.star_outline, size: 16),
                      label: const Text('收藏'),
                      selected: _showFavorites,
                      onSelected: (_) async {
                        await _vm.loadFavorites();
                        if (mounted) setState(() => _showFavorites = true);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 3, 18, 0),
                child: Text(
                  '${visibleHistory.length} 张${_showFavorites ? '收藏' : '作品'}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
            if (_vm.isLoading && _vm.history.isEmpty && !_showFavorites)
              const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (visibleHistory.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_vm.isLoading && _searchQuery.trim().isNotEmpty)
                          const CupertinoActivityIndicator()
                        else
                          Icon(
                            CupertinoIcons.sparkles,
                            size: 42,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          _searchQuery.isNotEmpty
                              ? _vm.isLoading
                                  ? '正在搜索更早的作品…'
                                  : '没有匹配的作品'
                              : _showFavorites
                                  ? '还没有收藏的作品'
                                  : '请去创造更多美好回忆吧！',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_searchQuery.isEmpty && !_showFavorites) ...[
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: widget.onNavigate == null
                                ? null
                                : () => widget.onNavigate!(1),
                            child: const Text('去创作'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.crossAxisExtent >= 720 ? 3 : 2;
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverMasonryGrid.count(
                      crossAxisCount: columns,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childCount: visibleHistory.length,
                      itemBuilder: (context, index) {
                        final item = visibleHistory[index];
                        return _HistoryGridCard(
                          key: ValueKey(item.taskId),
                          item: item,
                          onNavigate: widget.onNavigate,
                          isFavorite: _isFavorite(item.taskId),
                          onToggleFavorite: () => _toggleFavorite(item.taskId),
                          onInpaint: widget.onInpaint,
                          onUpscale: widget.onUpscale,
                          onEnhance: widget.onEnhance,
                        );
                      },
                    ),
                  );
                },
              ),
            if (visibleHistory.isNotEmpty && _vm.isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CupertinoActivityIndicator()),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 24 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryGridCard extends StatefulWidget {
  final GenerationTask item;
  final ValueChanged<int>? onNavigate;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final HistoryDetailImageAction? onInpaint;
  final HistoryDetailImageAction? onUpscale;
  final HistoryDetailImageAction? onEnhance;

  const _HistoryGridCard({
    super.key,
    required this.item,
    this.onNavigate,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onInpaint,
    this.onUpscale,
    this.onEnhance,
  });

  @override
  State<_HistoryGridCard> createState() => _HistoryGridCardState();
}

class _HistoryGridCardState extends State<_HistoryGridCard> {
  bool _pressed = false;
  bool _rebounding = false;
  Timer? _reboundTimer;

  void _setPressed(bool pressed) {
    _reboundTimer?.cancel();
    setState(() {
      _pressed = pressed;
      _rebounding = false;
    });
  }

  void _releasePress() {
    setState(() {
      _pressed = false;
      _rebounding = true;
    });
    _reboundTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _rebounding = false);
    });
  }

  @override
  void dispose() {
    _reboundTimer?.cancel();
    super.dispose();
  }

  void _openDetail() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => HistoryDetailPage(
          task: widget.item,
          onNavigate: widget.onNavigate,
          isFavorite: widget.isFavorite,
          onToggleFavorite: widget.onToggleFavorite,
          onInpaint: widget.onInpaint,
          onUpscale: widget.onUpscale,
          onEnhance: widget.onEnhance,
        ),
      ),
    );
  }

  void _openPreview() {
    showFullscreenImagePreview(
      context,
      imagePath: widget.item.imagePath,
      imageUrl: widget.item.imageUrl,
    );
  }

  Future<void> _showActions() async {
    final item = widget.item;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.94, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            );
          },
          child: DraggableScrollableSheet(
            initialChildSize: 0.78,
            minChildSize: 0.35,
            maxChildSize: 0.96,
            snap: true,
            snapSizes: const [0.78, 0.96],
            builder: (context, scrollController) {
              return SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C21) : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.08,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.35 : 0.12,
                        ),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.34),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: AspectRatio(
                            aspectRatio: 0.86,
                            child: item.imagePath != null &&
                                    File(item.imagePath!).existsSync()
                                ? Image.file(
                                    File(item.imagePath!),
                                    fit: BoxFit.cover,
                                  )
                                : item.imageUrl != null
                                    ? Image.network(
                                        item.imageUrl!,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: theme.colorScheme.surface,
                                        child: Icon(
                                          CupertinoIcons.photo,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _HistoryActionTile(
                          icon: CupertinoIcons.fullscreen,
                          title: '放大查看',
                          onTap: () {
                            Navigator.pop(ctx);
                            _openPreview();
                          },
                        ),
                        _HistoryActionTile(
                          icon: CupertinoIcons.doc_on_doc,
                          title: '复制提示词',
                          onTap: () {
                            Navigator.pop(ctx);
                            Clipboard.setData(
                              ClipboardData(text: widget.item.prompt),
                            );
                          },
                        ),
                        _HistoryActionTile(
                          icon: widget.isFavorite
                              ? CupertinoIcons.star_fill
                              : CupertinoIcons.star,
                          title: widget.isFavorite ? '取消收藏' : '收藏作品',
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onToggleFavorite?.call();
                          },
                        ),
                        _HistoryActionTile(
                          icon: CupertinoIcons.info_circle,
                          title: '查看生成详情',
                          onTap: () {
                            Navigator.pop(ctx);
                            _openDetail();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _imagePlaceholder(BuildContext context, {bool loading = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: loading
            ? const CupertinoActivityIndicator()
            : Icon(
                CupertinoIcons.photo,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
                size: 32,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final hasLocalImage =
        item.imagePath != null && File(item.imagePath!).existsSync();
    final rawRatio = item.height > 0 ? item.width / item.height : 0.8;
    final aspectRatio =
        rawRatio.isFinite && rawRatio > 0 ? rawRatio.clamp(0.62, 1.5) : 0.8;

    Widget image;
    if (hasLocalImage) {
      image = Image.file(
        File(item.imagePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imagePlaceholder(context),
      );
    } else if (item.imageUrl != null) {
      image = Image.network(
        item.imageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : _imagePlaceholder(context, loading: true),
        errorBuilder: (_, __, ___) => _imagePlaceholder(context),
      );
    } else {
      image = _imagePlaceholder(context);
    }

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: GestureDetector(
        onTap: _openDetail,
        onDoubleTap: _openPreview,
        onLongPressStart: (_) => _setPressed(true),
        onLongPressEnd: (_) => _releasePress(),
        onLongPress: _showActions,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: _releasePress,
        onTapUp: (_) => _releasePress(),
        child: AnimatedScale(
          scale: _pressed
              ? 0.96
              : _rebounding
                  ? 1.025
                  : 1,
          duration: Duration(milliseconds: _pressed ? 210 : 180),
          curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(_pressed ? 24 : 20),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(
                  alpha: _pressed ? 0.34 : 0.1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.brightness == Brightness.dark
                      ? Colors.black.withValues(alpha: _pressed ? 0.12 : 0.28)
                      : theme.colorScheme.primary.withValues(
                          alpha: _pressed ? 0.04 : 0.1,
                        ),
                  blurRadius: _pressed ? 5 : 14,
                  offset: Offset(0, _pressed ? 2 : 7),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.82),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      item.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _HistoryActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onTap: onTap,
    );
  }
}
