import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/online_gallery.dart';
import 'package:nai_huishi/domain/repositories/online_gallery_repository.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/online_gallery_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/online_gallery_image.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// Online references are a separate route and never touch local generation
/// history. The list remains mounted under the detail route, preserving its
/// scroll position and active query when the user returns.
class OnlineGalleryScreen extends StatefulWidget {
  const OnlineGalleryScreen({
    super.key,
    this.repository,
    this.onNavigateToGenerate,
  });

  final OnlineGalleryRepository? repository;
  final VoidCallback? onNavigateToGenerate;

  @override
  State<OnlineGalleryScreen> createState() => _OnlineGalleryScreenState();
}

class _OnlineGalleryScreenState extends State<OnlineGalleryScreen> {
  late final OnlineGalleryRepository _repository;
  late final OnlineGalleryViewModel _viewModel;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? sl<OnlineGalleryRepository>();
    _viewModel = OnlineGalleryViewModel(_repository);
    _viewModel.addListener(_onViewModelChanged);
    _scrollController.addListener(_onScroll);
    unawaited(_viewModel.initialize());
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    if (!_queryFocus.hasFocus &&
        _queryController.text != _viewModel.query.query) {
      _queryController.value = TextEditingValue(
        text: _viewModel.query.query,
        selection: TextSelection.collapsed(
          offset: _viewModel.query.query.length,
        ),
      );
    }
    setState(() {});
  }

  void _onScroll() {
    if (_viewModel.isShowingFavorites ||
        !_scrollController.hasClients ||
        !_viewModel.hasMore ||
        _viewModel.isLoading ||
        _viewModel.isLoadingMore ||
        _viewModel.loadMoreErrorMessage != null ||
        _viewModel.page.items.isEmpty) {
      return;
    }
    if (_scrollController.position.extentAfter < 420) {
      unawaited(_viewModel.loadMore());
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _queryController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    await _viewModel.search(
      _viewModel.query.copyWith(query: _queryController.text.trim()),
    );
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _selectSource(OnlineGallerySource source) async {
    if (source == _viewModel.query.source) return;
    if (source == OnlineGallerySource.gelbooru) {
      var configured = false;
      try {
        configured = await _repository.hasGelbooruCredentials();
      } catch (_) {
        _showMessage('无法读取 Gelbooru 凭据状态');
        return;
      }
      if (!configured) {
        final credentials = await _requestGelbooruCredentials();
        if (credentials == null || !mounted) return;
        try {
          await _viewModel.saveGelbooruCredentials(credentials);
        } catch (_) {
          if (mounted) _showMessage('凭据保存失败，请重试');
          return;
        }
      }
    }
    await _viewModel.changeSource(source);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<OnlineGalleryCredentials?> _requestGelbooruCredentials() async {
    final userId = TextEditingController();
    final apiKey = TextEditingController();
    try {
      return await showModalBottomSheet<OnlineGalleryCredentials>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gelbooru 凭据',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '凭据会交给安全存储保存，用于访问 Gelbooru API。',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('gelbooru-user-id'),
                  controller: userId,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'User ID'),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('gelbooru-api-key'),
                  controller: apiKey,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  key: const ValueKey('save-gelbooru-credentials'),
                  onPressed: () {
                    final id = userId.text.trim();
                    final key = apiKey.text.trim();
                    if (id.isEmpty || key.isEmpty) return;
                    Navigator.of(sheetContext).pop(
                      OnlineGalleryCredentials(userId: id, apiKey: key),
                    );
                  },
                  child: const Text('保存并打开 Gelbooru'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      userId.dispose();
      apiKey.dispose();
    }
  }

  Future<void> _openFilters() async {
    FocusScope.of(context).unfocus();
    final query = await showModalBottomSheet<OnlineGalleryQuery>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => OnlineGalleryFilterSheet(
        query: _viewModel.query,
        categories: _viewModel.page.categories,
        collections: _viewModel.page.collections,
        repository: _repository,
      ),
    );
    if (!mounted || query == null) return;
    _queryController.text = query.query;
    await _viewModel.search(query);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _toggleFavorites() async {
    final show = !_viewModel.isShowingFavorites;
    final loaded = await _viewModel.setFavoritesMode(show);
    if (!mounted) return;
    if (show && !loaded) {
      _showMessage(_viewModel.favoritesErrorMessage ?? '加载收藏失败，请重试');
    }
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _openItem(OnlineGalleryItem item) async {
    if (item.isCollection) {
      await _viewModel.enterCollection(item);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      return;
    }
    final listOffset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => OnlineGalleryDetailPage(
          repository: _repository,
          viewModel: _viewModel,
          item: item,
          safeOnly: item.metadata['safeOnly'] is bool
              ? item.metadata['safeOnly'] as bool
              : _viewModel.query.safeOnly,
          onNavigateToGenerate: widget.onNavigateToGenerate,
        ),
      ),
    );
    if (!mounted || !_scrollController.hasClients) return;
    // The popped Cupertino route can complete before the retained gallery
    // viewport has laid out again. Wait for that frame so jumpTo is clamped
    // against the restored grid extent rather than a transient near-zero one.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(listOffset.clamp(0.0, position.maxScrollExtent));
  }

  Future<void> _toggleFavorite(OnlineGalleryItem item) async {
    final saved =
        await _viewModel.setFavorite(item, !_viewModel.isFavorite(item));
    if (!mounted) return;
    _showMessage(saved
        ? (_viewModel.isFavorite(item) ? '已收藏' : '已取消收藏')
        : (_viewModel.favoritesErrorMessage ?? '收藏操作失败，请重试'));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int get _activeFilterCount {
    final query = _viewModel.query;
    var count = 0;
    if (query.sort != query.source.sorts.first) count++;
    if (query.timeRange != 'all') count++;
    if (query.safeOnly && _supportsSafeFilter(query.source)) count++;
    if (query.source == OnlineGallerySource.tagsGallery) {
      if (query.model != 'v5') count++;
      if (query.category != 'artist') count++;
    }
    if (query.collectionId != null || query.categoryPath.isNotEmpty) count++;
    if (query.searchAll) count++;
    return count;
  }

  static bool _supportsSafeFilter(OnlineGallerySource source) =>
      switch (source) {
        OnlineGallerySource.danbooru ||
        OnlineGallerySource.safebooru ||
        OnlineGallerySource.gelbooru ||
        OnlineGallerySource.civitai ||
        OnlineGallerySource.quickTag =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showingFavorites = _viewModel.isShowingFavorites;
    final visibleItems = _viewModel.visibleItems;
    return Scaffold(
      key: const ValueKey('online-gallery-screen'),
      appBar: AppBar(
        title: const Text('在线图库', maxLines: 1, overflow: TextOverflow.ellipsis),
        flexibleSpace: const FrostedSurface(
          radius: 0,
          child: SizedBox.expand(),
        ),
        actions: [
          IconButton(
            key: const ValueKey('online-gallery-favorites'),
            tooltip: showingFavorites ? '返回搜索结果' : '查看收藏',
            onPressed: _toggleFavorites,
            icon: Icon(showingFavorites
                ? Icons.star_rounded
                : Icons.star_outline_rounded),
          ),
          PopupMenuButton<OnlineGallerySource>(
            key: const ValueKey('online-gallery-source-menu'),
            tooltip: '画廊来源：${_viewModel.query.source.label}',
            icon: const Icon(Icons.public_outlined),
            onSelected: (source) => unawaited(_selectSource(source)),
            itemBuilder: (context) => OnlineGallerySource.values
                .map(
                  (source) => PopupMenuItem<OnlineGallerySource>(
                    key: ValueKey('online-gallery-source-${source.id}'),
                    value: source,
                    child: Row(
                      children: [
                        Expanded(child: Text(source.label)),
                        if (source == _viewModel.query.source)
                          Icon(Icons.check,
                              size: 18, color: theme.colorScheme.primary),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          IconButton(
            key: const ValueKey('online-gallery-refresh'),
            tooltip: '刷新',
            onPressed: _viewModel.isLoading ? null : () => _viewModel.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: StudioBackground()),
          SafeArea(
            top: false,
            child: BackdropGroup(
              child: CustomScrollView(
                key: const PageStorageKey<String>('online-gallery-results'),
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('online-gallery-query'),
                              controller: _queryController,
                              focusNode: _queryFocus,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _search(),
                              decoration: InputDecoration(
                                hintText: _viewModel.query.source.searchHint,
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: IconButton(
                                  key: const ValueKey('online-gallery-submit'),
                                  tooltip: '搜索',
                                  onPressed: _search,
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  key: const ValueKey(
                                      'open-online-gallery-filters'),
                                  tooltip: '筛选与设置',
                                  onPressed: _openFilters,
                                  icon: const Icon(Icons.tune_rounded),
                                ),
                                if (_activeFilterCount > 0)
                                  Positioned(
                                    right: 2,
                                    top: 2,
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Text(
                                            '$_activeFilterCount',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color:
                                                  theme.colorScheme.onPrimary,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              showingFavorites
                                  ? '收藏 · ${visibleItems.length} 项'
                                  : '${_viewModel.query.source.label} · ${visibleItems.length} 项',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (!showingFavorites &&
                              _viewModel.query.collectionId != null)
                            TextButton.icon(
                              key: const ValueKey(
                                  'online-gallery-back-collections'),
                              onPressed: _viewModel.leaveCollection,
                              icon: const Icon(Icons.arrow_back_rounded,
                                  size: 17),
                              label: const Text('合集'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 40),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_viewModel.page.warnings.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                        child: _GalleryNotice(
                          icon: Icons.info_outline_rounded,
                          text: _viewModel.page.warnings.join(' · '),
                        ),
                      ),
                    ),
                  ..._buildResultsSlivers(visibleItems),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 24 + MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResultsSlivers(List<OnlineGalleryItem> items) {
    final loadingEmpty = _viewModel.isShowingFavorites
        ? _viewModel.isLoadingFavorites && items.isEmpty
        : _viewModel.isLoading && items.isEmpty;
    final error = _viewModel.isShowingFavorites
        ? _viewModel.favoritesErrorMessage
        : _viewModel.errorMessage;
    if (loadingEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CupertinoActivityIndicator(radius: 14)),
        ),
      ];
    }
    if (error != null && items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _GalleryStateMessage(
            icon: Icons.cloud_off_outlined,
            title: error,
            actionLabel: '重试',
            onAction: _viewModel.isShowingFavorites
                ? () => _viewModel.loadFavorites()
                : _viewModel.retrySearch,
          ),
        ),
      ];
    }
    if (items.isEmpty) {
      final canContinue = !_viewModel.isShowingFavorites && _viewModel.hasMore;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _GalleryStateMessage(
            icon: _viewModel.isShowingFavorites
                ? Icons.star_border_rounded
                : Icons.image_search_outlined,
            title: _viewModel.isShowingFavorites
                ? '还没有收藏的作品'
                : canContinue
                    ? '当前页面没有作品，仍可继续翻页'
                    : '没有找到匹配的作品',
            actionLabel: canContinue
                ? (_viewModel.isLoadingMore ? '正在继续…' : '继续加载')
                : null,
            onAction: canContinue ? _viewModel.loadMore : null,
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        sliver: SliverMasonryGrid.count(
          key: const ValueKey('online-gallery-grid'),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _OnlineGalleryCard(
              key: ValueKey(item.key),
              repository: _repository,
              item: item,
              favorite: _viewModel.isFavorite(item),
              favoriteBusy: _viewModel.isFavoriteBusy(item),
              onOpen: () => _openItem(item),
              onFavorite: () => _toggleFavorite(item),
            );
          },
        ),
      ),
      if (!_viewModel.isShowingFavorites && _viewModel.hasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                if (_viewModel.loadMoreErrorMessage != null)
                  _GalleryNotice(
                    icon: Icons.error_outline_rounded,
                    text: _viewModel.loadMoreErrorMessage!,
                  )
                else if (_viewModel.page.items.isEmpty)
                  const _GalleryNotice(
                    icon: Icons.info_outline_rounded,
                    text: '这一页没有作品，可继续尝试下一页。',
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('online-gallery-load-more'),
                  onPressed: _viewModel.isLoadingMore
                      ? null
                      : _viewModel.loadMoreErrorMessage == null
                          ? _viewModel.loadMore
                          : _viewModel.loadMore,
                  icon: _viewModel.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(
                    _viewModel.isLoadingMore
                        ? '正在加载…'
                        : _viewModel.loadMoreErrorMessage == null
                            ? '加载更多'
                            : '重试加载',
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}

class _OnlineGalleryCard extends StatelessWidget {
  const _OnlineGalleryCard({
    super.key,
    required this.repository,
    required this.item,
    required this.favorite,
    required this.favoriteBusy,
    required this.onOpen,
    required this.onFavorite,
  });

  final OnlineGalleryRepository repository;
  final OnlineGalleryItem item;
  final bool favorite;
  final bool favoriteBusy;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = item.cover;
    final aspectRatio = media.width > 0 && media.height > 0
        ? (media.width / media.height).clamp(0.62, 1.3).toDouble()
        : 0.82;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OnlineGalleryImage(
                    repository: repository,
                    item: item,
                    media: media,
                    compact: true,
                    semanticLabel: item.title,
                  ),
                  if (item.isCollection)
                    const Positioned(
                      left: 7,
                      bottom: 7,
                      child: _GalleryBadge(
                        icon: Icons.folder_copy_outlined,
                        label: '合集',
                      ),
                    ),
                  if (item.mediaCount > 1)
                    Positioned(
                      right: 7,
                      bottom: 7,
                      child: _GalleryBadge(
                        icon: Icons.collections_outlined,
                        label: '${item.mediaCount}',
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      key: ValueKey('favorite-${item.key}'),
                      tooltip: favorite ? '取消收藏' : '收藏',
                      onPressed: favoriteBusy ? null : onFavorite,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.48),
                        foregroundColor: favorite ? Colors.amber : Colors.white,
                        minimumSize: const Size(44, 44),
                      ),
                      icon: favoriteBusy
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(favorite
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? '#${item.id}' : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnlineGalleryFilterSheet extends StatefulWidget {
  const OnlineGalleryFilterSheet({
    super.key,
    required this.query,
    required this.categories,
    required this.collections,
    required this.repository,
  });

  final OnlineGalleryQuery query;
  final List<OnlineGalleryCategory> categories;
  final List<OnlineGalleryCollection> collections;
  final OnlineGalleryRepository repository;

  @override
  State<OnlineGalleryFilterSheet> createState() =>
      _OnlineGalleryFilterSheetState();
}

class _OnlineGalleryFilterSheetState extends State<OnlineGalleryFilterSheet> {
  late OnlineGalleryQuery _query = widget.query;
  bool _credentialsBusy = false;
  String? _credentialsStatus;
  bool _cacheBusy = false;
  String? _cacheStatus;

  static const _tagsCategories = <OnlineGalleryCategory>[
    OnlineGalleryCategory(path: ['artist'], title: '画师'),
    OnlineGalleryCategory(path: ['character'], title: '角色'),
    OnlineGalleryCategory(path: ['copyright'], title: '作品'),
    OnlineGalleryCategory(path: ['fashion_style'], title: '服装风格'),
    OnlineGalleryCategory(path: ['face'], title: '面容'),
    OnlineGalleryCategory(path: ['face_parts'], title: '五官'),
    OnlineGalleryCategory(path: ['hair'], title: '发型'),
    OnlineGalleryCategory(path: ['accessories'], title: '配饰'),
    OnlineGalleryCategory(path: ['composition'], title: '构图'),
  ];

  bool get _supportsSafeFilter => switch (_query.source) {
        OnlineGallerySource.danbooru ||
        OnlineGallerySource.safebooru ||
        OnlineGallerySource.gelbooru ||
        OnlineGallerySource.civitai ||
        OnlineGallerySource.quickTag =>
          true,
        _ => false,
      };

  Future<void> _configureGelbooru() async {
    final userId = TextEditingController();
    final apiKey = TextEditingController();
    try {
      final credentials = await showModalBottomSheet<OnlineGalleryCredentials>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gelbooru 凭据',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('凭据将通过安全存储保存。'),
                const SizedBox(height: 14),
                TextField(
                  controller: userId,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'User ID'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: apiKey,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () {
                    final id = userId.text.trim();
                    final key = apiKey.text.trim();
                    if (id.isEmpty || key.isEmpty) return;
                    Navigator.of(context).pop(OnlineGalleryCredentials(
                      userId: id,
                      apiKey: key,
                    ));
                  },
                  child: const Text('保存凭据'),
                ),
              ],
            ),
          ),
        ),
      );
      if (credentials == null || !mounted) return;
      setState(() {
        _credentialsBusy = true;
        _credentialsStatus = null;
      });
      try {
        await widget.repository.setGelbooruCredentials(credentials);
        if (mounted) setState(() => _credentialsStatus = '凭据已安全保存');
      } catch (_) {
        if (mounted) setState(() => _credentialsStatus = '保存失败，请重试');
      } finally {
        if (mounted) setState(() => _credentialsBusy = false);
      }
    } finally {
      userId.dispose();
      apiKey.dispose();
    }
  }

  Future<void> _clearPreviewCache() async {
    setState(() {
      _cacheBusy = true;
      _cacheStatus = null;
    });
    try {
      await widget.repository.clearCache();
      if (mounted) {
        setState(() => _cacheStatus = '预览缓存已清理，收藏和已保存原图会保留');
      }
    } catch (_) {
      if (mounted) setState(() => _cacheStatus = '清理预览缓存失败，请重试');
    } finally {
      if (mounted) setState(() => _cacheBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _query.source;
    final categories = source == OnlineGallerySource.tagsGallery
        ? _tagsCategories
        : widget.categories;
    final types = widget.collections
        .map((collection) => collection.type)
        .where((type) => type.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final screenHeight = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('online-gallery-filter-sheet'),
        height: math.min(screenHeight * 0.88, 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('筛选与设置',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const ValueKey('online-gallery-sort-filter'),
                      initialValue: _query.sort,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '排序'),
                      items: source.sorts
                          .map((sort) => DropdownMenuItem(
                                value: sort,
                                child: Text(_sortLabel(source, sort)),
                              ))
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _query = _query.copyWith(sort: value));
                        }
                      },
                    ),
                    if (source.supportsTimeRange) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('online-gallery-time-filter'),
                        initialValue: _query.timeRange,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: source == OnlineGallerySource.civitai
                              ? '热度统计范围'
                              : '时间范围',
                        ),
                        items: source.timeRanges.entries
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() =>
                                _query = _query.copyWith(timeRange: value));
                          }
                        },
                      ),
                    ],
                    if (source == OnlineGallerySource.tagsGallery) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('online-gallery-tags-model-filter'),
                        initialValue: _query.model,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'TAGs 模型'),
                        items: const [
                          DropdownMenuItem(value: 'v4-5', child: Text('V4.5')),
                          DropdownMenuItem(value: 'v5', child: Text('V5')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(
                                () => _query = _query.copyWith(model: value));
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('分类', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _CategoryChoices(
                        categories: categories,
                        selectedPath: _query.categoryPath.isNotEmpty
                            ? _query.categoryPath
                            : [_query.category],
                        onSelected: (category) {
                          setState(() {
                            _query = _query.copyWith(
                              category: category.path.first,
                              categoryPath: category.path,
                              clearCollection: true,
                            );
                          });
                        },
                      ),
                    ],
                    if (source == OnlineGallerySource.quickTag) ...[
                      const SizedBox(height: 12),
                      if (widget.collections.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: const ValueKey(
                              'online-gallery-quicktag-collection-filter'),
                          initialValue: _query.collectionId ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '合集'),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('全部合集'),
                            ),
                            ...widget.collections
                                .map((collection) => DropdownMenuItem(
                                      value: collection.id,
                                      child: Text(
                                        collection.count > 0
                                            ? '${collection.title} · ${collection.count}'
                                            : collection.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _query = value.isEmpty
                                  ? _query.copyWith(
                                      clearCollection: true,
                                      collectionType: '',
                                      categoryPath: const [],
                                    )
                                  : _query.copyWith(
                                      collectionId: value,
                                      collectionType: widget.collections
                                          .where((item) => item.id == value)
                                          .firstOrNull
                                          ?.type,
                                      categoryPath: const [],
                                    );
                            });
                          },
                        ),
                      if (types.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const ValueKey(
                              'online-gallery-quicktag-type-filter'),
                          initialValue: types.contains(_query.collectionType)
                              ? _query.collectionType
                              : '',
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '合集类型'),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('全部类型'),
                            ),
                            ...types.map((type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                )),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _query =
                                  _query.copyWith(collectionType: value));
                            }
                          },
                        ),
                      ],
                      if (categories.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('分类层级',
                            style: Theme.of(context).textTheme.titleSmall),
                        if (_query.categoryPath.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              _query.categoryPath.join(' / '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          )
                        else
                          const SizedBox(height: 8),
                        _CategoryChoices(
                          categories: categories,
                          selectedPath: _query.categoryPath,
                          onSelected: (category) => setState(() {
                            _query = _query.copyWith(
                              categoryPath: category.path,
                              clearCollection: false,
                            );
                          }),
                        ),
                      ],
                      SwitchListTile.adaptive(
                        key: const ValueKey(
                            'online-gallery-quicktag-search-all'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('搜索全部合集'),
                        subtitle: const Text('忽略当前合集与层级范围'),
                        value: _query.searchAll,
                        onChanged: (value) =>
                            setState(() => _query = _query.copyWith(
                                  searchAll: value,
                                  clearCollection: value,
                                  categoryPath: value ? const [] : null,
                                )),
                      ),
                      if (_query.collectionId != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey(
                                'online-gallery-quicktag-back-collections'),
                            onPressed: () =>
                                setState(() => _query = _query.copyWith(
                                      clearCollection: true,
                                      collectionType: '',
                                      categoryPath: const [],
                                    )),
                            icon:
                                const Icon(Icons.arrow_back_rounded, size: 17),
                            label: const Text('返回合集列表'),
                          ),
                        ),
                    ],
                    if (_supportsSafeFilter)
                      SwitchListTile.adaptive(
                        key: const ValueKey('online-gallery-safe-filter'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('仅显示全年龄内容'),
                        value: _query.safeOnly,
                        onChanged: (value) => setState(
                            () => _query = _query.copyWith(safeOnly: value)),
                      ),
                    if (source == OnlineGallerySource.gelbooru) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        key: const ValueKey('configure-gelbooru-credentials'),
                        onPressed: _credentialsBusy ? null : _configureGelbooru,
                        icon: _credentialsBusy
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.key_outlined),
                        label:
                            Text(_credentialsBusy ? '正在保存…' : '设置 Gelbooru 凭据'),
                      ),
                      if (_credentialsStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_credentialsStatus!),
                        ),
                    ],
                    const Divider(height: 24),
                    OutlinedButton.icon(
                      key: const ValueKey('clear-online-gallery-cache'),
                      onPressed: _cacheBusy ? null : _clearPreviewCache,
                      icon: _cacheBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cleaning_services_outlined),
                      label: Text(
                        _cacheBusy ? '正在清理…' : '清理预览图片缓存',
                      ),
                    ),
                    const Text('仅清理图库预览缓存，收藏和已保存原图会保留。'),
                    if (_cacheStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _cacheStatus!,
                          key: const ValueKey('online-gallery-cache-status'),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('online-gallery-cancel-filters'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('online-gallery-apply-filters'),
                      onPressed: () => Navigator.of(context).pop(_query),
                      child: const Text('应用筛选'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sortLabel(OnlineGallerySource source, String value) {
    if (source == OnlineGallerySource.civitai && value == 'score') {
      return '互动最多';
    }
    return gallerySortLabels[value] ?? value;
  }
}

class _CategoryChoices extends StatelessWidget {
  const _CategoryChoices({
    required this.categories,
    required this.selectedPath,
    required this.onSelected,
  });

  final List<OnlineGalleryCategory> categories;
  final List<String> selectedPath;
  final ValueChanged<OnlineGalleryCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Text(
        '当前没有可选分类',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final category in categories)
          ChoiceChip(
            key: ValueKey('online-gallery-category-${category.path.join('-')}'),
            label: Text(category.title),
            selected: listEquals(selectedPath, category.path),
            onSelected: (_) => onSelected(category),
          ),
      ],
    );
  }
}

class OnlineGalleryDetailPage extends StatefulWidget {
  const OnlineGalleryDetailPage({
    super.key,
    required this.repository,
    required this.viewModel,
    required this.item,
    required this.safeOnly,
    this.onNavigateToGenerate,
  });

  final OnlineGalleryRepository repository;
  final OnlineGalleryViewModel viewModel;
  final OnlineGalleryItem item;
  final bool safeOnly;
  final VoidCallback? onNavigateToGenerate;

  @override
  State<OnlineGalleryDetailPage> createState() =>
      _OnlineGalleryDetailPageState();
}

class _OnlineGalleryDetailPageState extends State<OnlineGalleryDetailPage> {
  late Future<OnlineGalleryItem> _detailFuture;
  int _detailSequence = 0;
  int _selectedMedia = 0;
  bool _downloading = false;
  bool _savingStyle = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  void _loadDetail() {
    final sequence = ++_detailSequence;
    _detailFuture = widget.repository
        .detail(widget.item, safeOnly: widget.safeOnly)
        .then((item) {
      if (sequence != _detailSequence) return widget.item;
      return item;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _toggleFavorite(OnlineGalleryItem item) async {
    final value = !widget.viewModel.isFavorite(item);
    final succeeded = await widget.viewModel.setFavorite(item, value);
    if (!mounted) return;
    _showMessage(succeeded
        ? value
            ? '已收藏'
            : '已取消收藏'
        : (widget.viewModel.favoritesErrorMessage ?? '收藏操作失败，请重试'));
  }

  Future<void> _download(
    OnlineGalleryItem item, {
    bool currentOnly = false,
  }) async {
    final allMedia = item.media.isEmpty ? [item.cover] : item.media;
    final media = currentOnly
        ? [allMedia[_selectedMedia.clamp(0, allMedia.length - 1)]]
        : allMedia.take(100).toList(growable: false);
    final wasLimited = !currentOnly && allMedia.length > media.length;
    setState(() => _downloading = true);
    try {
      final result = await widget.repository.download(item, media);
      if (!mounted) return;
      final message = result.saved > 0
          ? '已保存 ${result.saved} 张${result.failed > 0 ? '，失败 ${result.failed} 张' : ''}'
              '${wasLimited ? '（共 ${allMedia.length} 张，单次最多保存 100 张）' : ''}'
          : '下载失败，请检查网络后重试';
      _showMessage(message);
    } catch (_) {
      if (mounted) _showMessage('下载失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _saveStyle(OnlineGalleryItem item) async {
    if (item.prompt.trim().isEmpty) return;
    setState(() => _savingStyle = true);
    try {
      await widget.repository.saveStyle(item);
      if (mounted) _showMessage('已保存到画风库');
    } catch (_) {
      if (mounted) _showMessage('保存画风失败，请重试');
    } finally {
      if (mounted) setState(() => _savingStyle = false);
    }
  }

  Future<void> _openSource(OnlineGalleryItem item) async {
    try {
      await widget.repository.openSource(item);
    } catch (_) {
      if (mounted) _showMessage('无法打开来源页面');
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _showMessage('已复制$label');
  }

  Future<void> _openApplySheet(OnlineGalleryItem item) async {
    final generation = sl<GenerationViewModel>();
    final choice = await showModalBottomSheet<_PromptApplyChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PromptApplySheet(
        item: item,
        currentPrompt: generation.prompt,
        currentNegativePrompt: generation.negativePrompt,
      ),
    );
    if (!mounted || choice == null) return;

    try {
      if (choice.positive) {
        await generation.updatePrompt(
          _mergePrompt(
            generation.prompt,
            item.prompt,
            choice.mode,
          ),
        );
      }
      // Do not write an empty/missing negative prompt: existing draft content
      // must remain intact when the source has no negative prompt.
      if (choice.negative && item.negativePrompt.trim().isNotEmpty) {
        await generation.updateNegativePrompt(
          _mergePrompt(
            generation.negativePrompt,
            item.negativePrompt,
            choice.mode,
          ),
        );
      }
      if (!mounted) return;
      _showMessage('提示词已写入创作草稿');
      final navigate = widget.onNavigateToGenerate;
      if (navigate != null) {
        navigate();
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (_) {
      if (mounted) _showMessage('写入草稿失败，请重试');
    }
  }

  String _mergePrompt(
    String current,
    String incoming,
    _PromptApplyMode mode,
  ) {
    if (mode == _PromptApplyMode.replace || current.trim().isEmpty) {
      return incoming.trim();
    }
    if (incoming.trim().isEmpty) return current;
    return '${current.trim()}, ${incoming.trim()}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<OnlineGalleryItem>(
      future: _detailFuture,
      builder: (context, snapshot) {
        final item = snapshot.data ?? widget.item;
        final mediaCount =
            item.media.isEmpty ? item.mediaCount : item.media.length;
        final loading = snapshot.connectionState != ConnectionState.done;
        final error = snapshot.hasError;
        return Scaffold(
          key: const ValueKey('online-gallery-detail'),
          appBar: AppBar(
            title: Text(
              item.title.isEmpty ? '#${item.id}' : item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              AnimatedBuilder(
                animation: widget.viewModel,
                builder: (context, _) => IconButton(
                  key: const ValueKey('online-gallery-detail-favorite'),
                  tooltip: widget.viewModel.isFavorite(item) ? '取消收藏' : '收藏',
                  onPressed: () => _toggleFavorite(item),
                  icon: Icon(
                    widget.viewModel.isFavorite(item)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: widget.viewModel.isFavorite(item)
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) {
                  switch (value) {
                    case 'download-current':
                      unawaited(_download(item, currentOnly: true));
                      break;
                    case 'download-all':
                      unawaited(_download(item));
                      break;
                    case 'source':
                      unawaited(_openSource(item));
                      break;
                    case 'style':
                      unawaited(_saveStyle(item));
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: const ValueKey(
                        'online-gallery-download-current-action'),
                    value: 'download-current',
                    enabled: !_downloading && !loading,
                    child: Text(_downloading ? '正在下载…' : '下载当前图'),
                  ),
                  if (mediaCount > 1)
                    PopupMenuItem(
                      key: const ValueKey('online-gallery-download-all-action'),
                      value: 'download-all',
                      enabled: !_downloading && !loading,
                      child: Text(
                        _downloading
                            ? '正在下载…'
                            : mediaCount > 100
                                ? '下载前 100 张（共 $mediaCount 张）'
                                : '下载全部（$mediaCount 张）',
                      ),
                    ),
                  PopupMenuItem(
                    key: const ValueKey('online-gallery-open-source-action'),
                    value: 'source',
                    enabled: !loading,
                    child: const Text('打开原站'),
                  ),
                  if (item.source == OnlineGallerySource.quickTag &&
                      item.prompt.trim().isNotEmpty)
                    PopupMenuItem(
                      key: const ValueKey('online-gallery-save-style-action'),
                      value: 'style',
                      enabled: !_savingStyle && !loading,
                      child: Text(_savingStyle ? '正在保存…' : '保存到画风库'),
                    ),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
          body: Stack(
            children: [
              const Positioned.fill(child: StudioBackground()),
              SafeArea(
                top: false,
                child: loading
                    ? const Center(
                        child: CupertinoActivityIndicator(radius: 14))
                    : error
                        ? _GalleryStateMessage(
                            icon: Icons.cloud_off_outlined,
                            title: '详情加载失败，请重试',
                            actionLabel: '重试',
                            onAction: () => setState(_loadDetail),
                          )
                        : _buildDetailBody(item),
              ),
            ],
          ),
          bottomNavigationBar:
              !loading && !error ? _buildDetailActions(item) : null,
        );
      },
    );
  }

  Widget _buildDetailBody(OnlineGalleryItem item) {
    final theme = Theme.of(context);
    final media = item.media.isEmpty ? [item.cover] : item.media;
    final selectedIndex = _selectedMedia.clamp(0, media.length - 1);
    final selected = media[selectedIndex];
    final displayUrl = selected.displayUrl.trim().isNotEmpty
        ? selected.displayUrl
        : selected.previewUrl;
    final fullMedia = OnlineGalleryMedia(
      id: '${selected.id}:display',
      previewUrl: displayUrl,
      displayUrl: displayUrl,
      downloadUrl: selected.downloadUrl,
      width: selected.width,
      height: selected.height,
      extension: selected.extension,
    );
    final imageHeight = (MediaQuery.sizeOf(context).height * 0.47)
        .clamp(260.0, 440.0)
        .toDouble();
    return CustomScrollView(
      key: const PageStorageKey<String>('online-gallery-detail-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          sliver: SliverList.list(
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: imageHeight,
                  child: OnlineGalleryImage(
                    key: ValueKey('detail-${item.key}-${selected.id}'),
                    repository: widget.repository,
                    item: item,
                    media: fullMedia,
                    fit: BoxFit.contain,
                    backgroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF0D0F13)
                        : const Color(0xFF202328),
                    semanticLabel: item.title,
                  ),
                ),
              ),
              if (media.length > 1) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: media.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final thumb = media[index];
                      return InkWell(
                        key: ValueKey('online-gallery-media-${thumb.id}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _selectedMedia = index),
                        child: Container(
                          width: 70,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: index == selectedIndex
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              width: index == selectedIndex ? 2 : 1,
                            ),
                          ),
                          child: OnlineGalleryImage(
                            repository: widget.repository,
                            item: item,
                            media: thumb,
                            compact: true,
                            semanticLabel: '${item.title} ${index + 1}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _DetailSection(
                title: '作品信息',
                icon: Icons.info_outline_rounded,
                children: [
                  _DetailValue(label: '来源', value: item.source.label),
                  if (item.author.isNotEmpty)
                    _DetailValue(label: '作者', value: item.author),
                  if (item.rating.isNotEmpty)
                    _DetailValue(label: '分级', value: item.rating),
                  if (selected.width > 0 && selected.height > 0)
                    _DetailValue(
                      label: '尺寸',
                      value: '${selected.width} × ${selected.height}',
                    ),
                  if (item.createdAt.isNotEmpty)
                    _DetailValue(label: '发布时间', value: item.createdAt),
                ],
              ),
              if (_hasModelMetadata(item.metadata)) ...[
                const SizedBox(height: 10),
                _DetailSection(
                  title: '原模型信息',
                  icon: Icons.auto_awesome_outlined,
                  children: _modelMetadata(item.metadata),
                ),
              ],
              if (item.prompt.trim().isNotEmpty ||
                  item.negativePrompt.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _DetailSection(
                  title: '提示词',
                  icon: Icons.notes_rounded,
                  children: [
                    if (item.prompt.trim().isNotEmpty)
                      _PromptDetailBlock(
                        title: '正向提示词',
                        keySuffix: 'positive',
                        text: item.prompt,
                        onCopy: () => _copy(item.prompt, '正向提示词'),
                      ),
                    if (item.prompt.trim().isNotEmpty &&
                        item.negativePrompt.trim().isNotEmpty)
                      const Divider(height: 26),
                    if (item.negativePrompt.trim().isNotEmpty)
                      _PromptDetailBlock(
                        title: '负向提示词',
                        keySuffix: 'negative',
                        text: item.negativePrompt,
                        onCopy: () => _copy(item.negativePrompt, '负向提示词'),
                      ),
                  ],
                ),
              ] else if (item.source == OnlineGallerySource.civitai) ...[
                const SizedBox(height: 10),
                const _DetailSection(
                  title: '提示词',
                  icon: Icons.notes_rounded,
                  children: [
                    Text('这张图片没有公开的生成提示词。'),
                  ],
                ),
              ],
              if (_characterPromptBlocks(item.metadata).isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildCharacterPrompts(item.metadata),
              ],
              if (item.categoryPath.isNotEmpty || item.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildTagsSection(item),
              ],
              if (item.description.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _DetailSection(
                  title: '说明',
                  icon: Icons.subject_rounded,
                  children: [SelectableText(item.description)],
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTagsSection(OnlineGalleryItem item) {
    const knownLabels = <String, String>{
      'artists': '画师',
      'artist': '画师',
      'characters': '角色',
      'character': '角色',
      'copyrights': '作品',
      'copyright': '作品',
      'general': '通用',
      'meta': '元数据',
    };
    final entries = item.tags.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    return _DetailSection(
      title: '标签',
      icon: Icons.sell_outlined,
      children: [
        if (item.categoryPath.isNotEmpty)
          _DetailValue(label: '分类路径', value: item.categoryPath.join(' / ')),
        for (final entry in entries) ...[
          Text(
            knownLabels[entry.key.toLowerCase()] ?? entry.key,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final tag in entry.value)
                InputChip(
                  label: Text(tag.replaceAll('_', ' ')),
                  onPressed: () => _copy(tag, '标签'),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildCharacterPrompts(Map<String, dynamic> metadata) {
    final blocks = _characterPromptBlocks(metadata);
    return _DetailSection(
      title: '角色提示词',
      icon: Icons.people_alt_outlined,
      children: [
        Text(
          '角色块可单独复制；不会自动套入创作。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0) const Divider(height: 24),
          _PromptDetailBlock(
            title: blocks[index]['label']?.toString().trim().isNotEmpty == true
                ? blocks[index]['label'].toString()
                : '角色 ${index + 1}',
            keySuffix: 'character-$index',
            text: blocks[index]['prompt']!.toString(),
            onCopy: () => _copy(
              blocks[index]['prompt']!.toString(),
              '角色提示词',
            ),
          ),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> _characterPromptBlocks(
    Map<String, dynamic> metadata,
  ) {
    final value = metadata['characterPrompts'];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) => entry['prompt']?.toString().trim().isNotEmpty == true)
        .toList(growable: false);
  }

  bool _hasModelMetadata(Map<String, dynamic> metadata) =>
      _modelMetadata(metadata).isNotEmpty;

  List<Widget> _modelMetadata(Map<String, dynamic> metadata) {
    const preferredOrder = [
      'baseModel',
      'model',
      'sampler',
      'steps',
      'cfgScale',
      'cfg',
      'seed',
      'width',
      'height',
      'scheduler',
    ];
    const labels = <String, String>{
      'baseModel': '基础模型',
      'model': '模型',
      'sampler': '采样器',
      'steps': 'Steps',
      'cfgScale': 'CFG',
      'cfg': 'CFG',
      'seed': 'Seed',
      'width': '宽度',
      'height': '高度',
      'scheduler': '调度器',
    };
    final selected = <String, dynamic>{};
    for (final key in preferredOrder) {
      final value = metadata[key];
      if (value is String || value is num || value is bool) {
        if (value.toString().trim().isNotEmpty) selected[key] = value;
      }
    }
    return selected.entries
        .map((entry) => _DetailValue(
              label: labels[entry.key] ?? entry.key,
              value: entry.value.toString(),
            ))
        .toList(growable: false);
  }

  Widget _buildDetailActions(OnlineGalleryItem item) {
    final hasPrompt =
        item.prompt.trim().isNotEmpty || item.negativePrompt.trim().isNotEmpty;
    return FrostedSurface(
      radius: 0,
      padding: EdgeInsets.fromLTRB(
        14,
        8,
        14,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('online-gallery-open-source'),
              onPressed: () => _openSource(item),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('打开原站', maxLines: 1),
            ),
          ),
          if (hasPrompt) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('online-gallery-apply-to-create'),
                onPressed: () => _openApplySheet(item),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('用于创作', maxLines: 1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _PromptApplyMode { replace, append }

class _PromptApplyChoice {
  const _PromptApplyChoice({
    required this.positive,
    required this.negative,
    required this.mode,
  });

  final bool positive;
  final bool negative;
  final _PromptApplyMode mode;
}

class _PromptApplySheet extends StatefulWidget {
  const _PromptApplySheet({
    required this.item,
    required this.currentPrompt,
    required this.currentNegativePrompt,
  });

  final OnlineGalleryItem item;
  final String currentPrompt;
  final String currentNegativePrompt;

  @override
  State<_PromptApplySheet> createState() => _PromptApplySheetState();
}

class _PromptApplySheetState extends State<_PromptApplySheet> {
  late bool _positive = widget.item.prompt.trim().isNotEmpty;
  late bool _negative = widget.item.negativePrompt.trim().isNotEmpty;
  _PromptApplyMode _mode = _PromptApplyMode.replace;

  String _preview(String current, String incoming) {
    if (_mode == _PromptApplyMode.replace || current.trim().isEmpty) {
      return incoming.trim();
    }
    return '${current.trim()}, ${incoming.trim()}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canApply = (_positive && widget.item.prompt.trim().isNotEmpty) ||
        (_negative && widget.item.negativePrompt.trim().isNotEmpty);
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('online-gallery-prompt-preview-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('用于创作预览', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '只写入提示词草稿，不会生成图片，也不会更改模型或 Seed。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('prompt-apply-replace'),
                    label: const Text('替换'),
                    selected: _mode == _PromptApplyMode.replace,
                    onSelected: (_) =>
                        setState(() => _mode = _PromptApplyMode.replace),
                  ),
                  ChoiceChip(
                    key: const ValueKey('prompt-apply-append'),
                    label: const Text('追加'),
                    selected: _mode == _PromptApplyMode.append,
                    onSelected: (_) =>
                        setState(() => _mode = _PromptApplyMode.append),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  children: [
                    CheckboxListTile.adaptive(
                      key: const ValueKey('prompt-apply-positive-toggle'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('正向提示词'),
                      subtitle: Text(widget.item.prompt.trim().isEmpty
                          ? '来源没有提供正向提示词'
                          : '预览为写入后的正向草稿'),
                      value: _positive && widget.item.prompt.trim().isNotEmpty,
                      onChanged: widget.item.prompt.trim().isEmpty
                          ? null
                          : (value) =>
                              setState(() => _positive = value ?? false),
                    ),
                    if (widget.item.prompt.trim().isNotEmpty)
                      _PromptPreviewBlock(
                        label: '正向预览',
                        value: _preview(
                          widget.currentPrompt,
                          widget.item.prompt,
                        ),
                      ),
                    const SizedBox(height: 10),
                    CheckboxListTile.adaptive(
                      key: const ValueKey('prompt-apply-negative-toggle'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('负向提示词'),
                      subtitle: Text(widget.item.negativePrompt.trim().isEmpty
                          ? '来源没有负向提示词；现有内容会保留'
                          : '预览为写入后的负向草稿'),
                      value: _negative &&
                          widget.item.negativePrompt.trim().isNotEmpty,
                      onChanged: widget.item.negativePrompt.trim().isEmpty
                          ? null
                          : (value) =>
                              setState(() => _negative = value ?? false),
                    ),
                    if (widget.item.negativePrompt.trim().isNotEmpty)
                      _PromptPreviewBlock(
                        label: '负向预览',
                        value: _preview(
                          widget.currentNegativePrompt,
                          widget.item.negativePrompt,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('confirm-online-gallery-prompt-apply'),
                onPressed: canApply
                    ? () => Navigator.of(context).pop(_PromptApplyChoice(
                          positive: _positive,
                          negative: _negative,
                          mode: _mode,
                        ))
                    : null,
                child: const Text('写入草稿并返回创作'),
              ),
              TextButton(
                key: const ValueKey('cancel-online-gallery-prompt-apply'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptPreviewBlock extends StatelessWidget {
  const _PromptPreviewBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 170),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 5),
            SelectableText(value),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
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

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PromptDetailBlock extends StatelessWidget {
  const _PromptDetailBlock({
    required this.title,
    required this.keySuffix,
    required this.text,
    required this.onCopy,
  });

  final String title;
  final String keySuffix;
  final String text;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            IconButton(
              key: ValueKey('copy-gallery-$keySuffix'),
              tooltip: '复制$title',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 19),
            ),
          ],
        ),
        SelectableText(text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
      ],
    );
  }
}

class _GalleryBadge extends StatelessWidget {
  const _GalleryBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryNotice extends StatelessWidget {
  const _GalleryNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _GalleryStateMessage extends StatelessWidget {
  const _GalleryStateMessage({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 42,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
