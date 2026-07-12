import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/artist_prompt.dart';
import 'package:nai_huishi/presentation/viewmodels/artist_prompt_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class ArtistPromptManagerPage extends StatefulWidget {
  const ArtistPromptManagerPage({super.key});

  @override
  State<ArtistPromptManagerPage> createState() =>
      _ArtistPromptManagerPageState();
}

class _ArtistPromptManagerPageState extends State<ArtistPromptManagerPage> {
  late final ArtistPromptViewModel _vm;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vm = sl<ArtistPromptViewModel>();
    _vm.addListener(_onChanged);
    _vm.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAddCategoryDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分类'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如 厚涂 / 水墨 / R18'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    await _vm.addCategory(name);
    if (mounted) showFloatingToast(context, '已新建分类');
  }

  Future<void> _showEditArtistSheet([ArtistPrompt? artist]) async {
    final nameCtrl = TextEditingController(text: artist?.name ?? '');
    final tagCtrl = TextEditingController(text: artist?.tag ?? '');
    final imageCtrl = TextEditingController(text: artist?.imagePath ?? '');
    final countCtrl =
        TextEditingController(text: (artist?.danbooruCount ?? 0).toString());
    final selectedCategories = <String>{
      ...(artist?.categories ?? ['未分类'])
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(ctx);
            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        artist == null ? '添加画师' : '编辑画师',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: '名称')),
                      const SizedBox(height: 10),
                      TextField(
                          controller: tagCtrl,
                          decoration:
                              const InputDecoration(labelText: '画师 Tag *')),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                              child: TextField(
                                  controller: imageCtrl,
                                  decoration: const InputDecoration(
                                      labelText: '封面路径 / URL'))),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: () async {
                              final picked = await ImagePicker()
                                  .pickImage(source: ImageSource.gallery);
                              if (picked == null) return;
                              // 复制到应用私有目录并压缩，避免临时路径失效导致图片消失
                              final persistedPath =
                                  await ImageUtils.copyAndCompressImage(
                                      File(picked.path));
                              imageCtrl.text = persistedPath;
                              setSheetState(() {});
                            },
                            icon: const Icon(CupertinoIcons.photo),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: countCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Danbooru 热度'),
                      ),
                      const SizedBox(height: 14),
                      Text('分类',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in ['未分类', ..._vm.categories])
                            FilterChip(
                              label: Text(category),
                              selected: selectedCategories.contains(category),
                              onSelected: (selected) {
                                setSheetState(() {
                                  if (selected) {
                                    selectedCategories.add(category);
                                  } else {
                                    selectedCategories.remove(category);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () async {
                          final tag = tagCtrl.text.trim();
                          if (tag.isEmpty) {
                            showFloatingToast(context, 'Tag 不能为空',
                                icon:
                                    CupertinoIcons.exclamationmark_circle_fill);
                            return;
                          }
                          final categories = selectedCategories.isEmpty
                              ? ['未分类']
                              : selectedCategories.toList();
                          final count =
                              int.tryParse(countCtrl.text.trim()) ?? 0;
                          if (artist == null) {
                            await _vm.create(
                              name: nameCtrl.text.trim(),
                              tag: tag,
                              imagePath: imageCtrl.text.trim(),
                              categories: categories,
                              danbooruCount: count,
                            );
                          } else {
                            await _vm.update(artist.copyWith(
                              name: nameCtrl.text.trim(),
                              tag: tag,
                              imagePath: imageCtrl.text.trim(),
                              categories: categories,
                              danbooruCount: count,
                            ));
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted)
                            showFloatingToast(
                                context, artist == null ? '已添加画师' : '已更新画师');
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    tagCtrl.dispose();
    imageCtrl.dispose();
    countCtrl.dispose();
  }

  Future<void> _showArtistActions(ArtistPrompt artist) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99))),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(CupertinoIcons.pencil),
                  title: const Text('编辑'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditArtistSheet(artist);
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.doc_on_doc),
                  title: const Text('复制 Tag'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: artist.tag));
                    Navigator.pop(ctx);
                    showFloatingToast(context, '已复制 Tag');
                  },
                ),
                ListTile(
                  leading:
                      const Icon(CupertinoIcons.trash, color: Colors.redAccent),
                  title: const Text('删除',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (artist.id == null) return;
                    await _vm.delete(artist.id!);
                    if (mounted) showFloatingToast(context, '已删除画师');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSelectedSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SelectedPromptSheet(
        vm: _vm,
        onCopy: () {
          Clipboard.setData(ClipboardData(text: _vm.generatedPrompt));
          showFloatingToast(context, 'NAI 画师串已复制');
        },
      ),
    );
  }

  Future<void> _exportJson() async {
    final data = await _vm.exportData();
    await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)));
    if (mounted) showFloatingToast(context, '导出 JSON 已复制到剪贴板');
  }

  String get _sortLabel {
    switch (_vm.sortMode) {
      case ArtistPromptSortMode.name:
        return '名称';
      case ArtistPromptSortMode.hot:
        return '热度';
      case ArtistPromptSortMode.recent:
        return '最近';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artists = _vm.filteredArtists;
    return Scaffold(
      appBar: AppBar(
        title: const Text('画师串管理'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') _exportJson();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('导出 JSON 到剪贴板')),
            ],
          ),
          IconButton(
              onPressed: () => _showEditArtistSheet(),
              icon: const Icon(CupertinoIcons.add)),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _vm.setSearchQuery,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(CupertinoIcons.search),
                    hintText: '搜索画师名 / Tag',
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  children: [
                    _CategoryChip(
                        label: '全部',
                        selected: _vm.currentCategory == '全部',
                        onTap: () => _vm.setCategory('全部')),
                    const SizedBox(width: 8),
                    _CategoryChip(
                        label: '未分类',
                        selected: _vm.currentCategory == '未分类',
                        onTap: () => _vm.setCategory('未分类')),
                    for (final category in _vm.categories) ...[
                      const SizedBox(width: 8),
                      _CategoryChip(
                          label: category,
                          selected: _vm.currentCategory == category,
                          onTap: () => _vm.setCategory(category)),
                    ],
                    const SizedBox(width: 8),
                    ActionChip(
                        label: const Text('+ 分类'),
                        onPressed: _showAddCategoryDialog),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Text('共 ${artists.length} 位画师',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _vm.toggleSortMode,
                      icon: const Icon(CupertinoIcons.arrow_up_arrow_down,
                          size: 15),
                      label: Text(_sortLabel),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _vm.isLoading
                    ? const Center(child: CupertinoActivityIndicator())
                    : artists.isEmpty
                        ? Center(
                            child: Text('暂无画师串',
                                style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant)))
                        : GridView.builder(
                            padding: EdgeInsets.fromLTRB(16, 8, 16,
                                _vm.selectedWeights.isEmpty ? 96 : 156),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.72,
                            ),
                            itemCount: artists.length,
                            itemBuilder: (context, index) {
                              final artist = artists[index];
                              final selected = artist.id != null &&
                                  _vm.selectedWeights.containsKey(artist.id);
                              return _ArtistCard(
                                artist: artist,
                                selected: selected,
                                onTap: () => _vm.toggleSelected(artist),
                                onLongPress: () => _showArtistActions(artist),
                              );
                            },
                          ),
              ),
            ],
          ),
          if (_vm.selectedWeights.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 18 + MediaQuery.paddingOf(context).bottom,
              child: _SelectedFloatingBar(
                count: _vm.selectedWeights.length,
                onOpen: _showSelectedSheet,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: _vm.generatedPrompt));
                  showFloatingToast(context, 'NAI 画师串已复制');
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
        label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

class _ArtistCard extends StatefulWidget {
  final ArtistPrompt artist;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ArtistCard(
      {required this.artist,
      required this.selected,
      required this.onTap,
      required this.onLongPress});

  @override
  State<_ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<_ArtistCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePath = widget.artist.imagePath;
    final isFile = imagePath.isNotEmpty && File(imagePath).existsSync();
    final isNetwork =
        imagePath.startsWith('http://') || imagePath.startsWith('https://');
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (_) => setState(() => _pressed = true),
      onLongPressEnd: (_) => setState(() => _pressed = false),
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed || widget.selected ? 0.96 : 1,
        duration: const Duration(milliseconds: 190),
        curve: _pressed ? Curves.easeOutCubic : Curves.elasticOut,
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: widget.selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.08),
              width: widget.selected ? 1.6 : 0.8,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isFile)
                Image.file(File(imagePath), fit: BoxFit.cover)
              else if (isNetwork)
                Image.network(imagePath, fit: BoxFit.cover)
              else
                Container(
                  color: theme.colorScheme.surface,
                  child: Icon(CupertinoIcons.person_crop_square,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.24),
                      size: 42),
                ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.flame_fill,
                          color: Color(0xFFFFB020), size: 11),
                      const SizedBox(width: 3),
                      Text('${widget.artist.danbooruCount}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              if (widget.selected)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.checkmark_alt,
                        color: theme.colorScheme.onPrimary, size: 14),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.82),
                        Colors.transparent
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(widget.artist.tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontFamily: 'monospace')),
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
}

class _SelectedFloatingBar extends StatelessWidget {
  final int count;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  const _SelectedFloatingBar(
      {required this.count, required this.onOpen, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C21).withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        children: [
          Expanded(
              child: Text('已选 $count 位画师',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface))),
          TextButton(onPressed: onOpen, child: const Text('查看')),
          FilledButton(onPressed: onCopy, child: const Text('复制')),
        ],
      ),
    );
  }
}

class _SelectedPromptSheet extends StatefulWidget {
  final ArtistPromptViewModel vm;
  final VoidCallback onCopy;

  const _SelectedPromptSheet({required this.vm, required this.onCopy});

  @override
  State<_SelectedPromptSheet> createState() => _SelectedPromptSheetState();
}

class _SelectedPromptSheetState extends State<_SelectedPromptSheet> {
  @override
  void initState() {
    super.initState();
    widget.vm.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final theme = Theme.of(context);
    final selectedArtists = vm.artists
        .where((artist) =>
            artist.id != null && vm.selectedWeights.containsKey(artist.id))
        .toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.38,
          maxChildSize: 0.92,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              children: [
                Center(
                    child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 14),
                Text('NAI 画师串',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface)),
                const SizedBox(height: 12),
                for (final artist in selectedArtists)
                  _SelectedArtistTile(
                    artist: artist,
                    weight: vm.selectedWeights[artist.id] ?? 1,
                    onMinus: () => vm.adjustWeight(artist.id!, -0.1),
                    onPlus: () => vm.adjustWeight(artist.id!, 0.1),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.08)),
                  ),
                  child: SelectableText(
                      vm.generatedPrompt.isEmpty ? '暂无输出' : vm.generatedPrompt,
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                          height: 1.45)),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: vm.clearSelected,
                            child: const Text('清空'))),
                    const SizedBox(width: 10),
                    Expanded(
                        flex: 2,
                        child: FilledButton(
                            onPressed: widget.onCopy,
                            child: const Text('复制 NAI 画师串'))),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SelectedArtistTile extends StatelessWidget {
  final ArtistPrompt artist;
  final double weight;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _SelectedArtistTile(
      {required this.artist,
      required this.weight,
      required this.onMinus,
      required this.onPlus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface)),
                Text(artist.tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
              onPressed: onMinus,
              icon: const Icon(CupertinoIcons.minus_circle, size: 19)),
          Text(weight.toStringAsFixed(1),
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface)),
          IconButton(
              onPressed: onPlus,
              icon: const Icon(CupertinoIcons.plus_circle, size: 19)),
        ],
      ),
    );
  }
}
