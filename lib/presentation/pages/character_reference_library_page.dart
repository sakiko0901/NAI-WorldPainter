import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart' show CupertinoDialogAction;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/data/repositories/character_reference_catalog_repository.dart';
import 'package:nai_huishi/domain/entities/character_reference_asset.dart';
import 'package:nai_huishi/presentation/navigation/studio_page_route.dart';
import 'package:nai_huishi/presentation/widgets/fullscreen_image_preview.dart';
import 'package:nai_huishi/presentation/widgets/studio_alert_dialog.dart';
import 'package:nai_huishi/presentation/widgets/studio_scaffold.dart';
import 'package:path/path.dart' as p;

class CharacterReferenceLibraryPage extends StatefulWidget {
  const CharacterReferenceLibraryPage({
    super.key,
    required this.repository,
    this.onApplyPrecise,
    this.onApplyVibe,
    this.applyUnavailableReason,
    this.picker,
  });

  final CharacterReferenceCatalogRepository repository;
  final Future<bool> Function(SavedCharacterReference reference)?
      onApplyPrecise;
  final Future<bool> Function(SavedCharacterReference reference)? onApplyVibe;
  final String? applyUnavailableReason;
  final ImagePicker? picker;

  @override
  State<CharacterReferenceLibraryPage> createState() =>
      _CharacterReferenceLibraryPageState();
}

enum _LibraryTab { online, saved }

enum _LibraryWork { reading, editing }

const _importCategory = '本地导入';

class _LibraryFilters {
  final query = TextEditingController();
  String? game;
  String? category;

  List<String> games(List<CharacterReferenceAsset> assets) => assets
      .map((asset) => asset.game)
      .where((game) => game.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<String> categories(List<CharacterReferenceAsset> assets) => assets
      .where((asset) => game == null || asset.game == game)
      .map((asset) => asset.category)
      .where((category) => category.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  void reconcile(List<CharacterReferenceAsset> assets) {
    if (game != null && !games(assets).contains(game)) game = null;
    if (category != null && !categories(assets).contains(category)) {
      category = null;
    }
  }

  bool includes(CharacterReferenceAsset asset, String keyword) =>
      (game == null || asset.game == game) &&
      (category == null || asset.category == category) &&
      (keyword.isEmpty || asset.matches(keyword));
}

typedef _Progress = ({String label, double? value, bool canCancel});
typedef _DownloadResult = ({
  int saved,
  int failed,
  Object? error,
  bool cancelled
});

class _CharacterReferenceLibraryPageState
    extends State<CharacterReferenceLibraryPage> {
  final _onlineFilters = _LibraryFilters();
  final _savedFilters = _LibraryFilters();
  final _work = ValueNotifier<_LibraryWork?>(null);
  final _progress = ValueNotifier<_Progress?>(null);
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  _LibraryTab _tab = _LibraryTab.online;
  List<CharacterReferenceAsset> _catalog = const [];
  final _saved = <String, SavedCharacterReference>{};
  bool _loadingOnline = false;
  String? _onlineError;
  String? _savedError;
  CancelToken? _downloadToken;

  bool get _busy => _work.value != null;
  bool get _editing => _work.value == _LibraryWork.editing;
  List<CharacterReferenceAsset> get _savedAssets =>
      _saved.values.map((saved) => saved.asset).toList(growable: false);

  @override
  void initState() {
    super.initState();
    unawaited(_loadOnline());
    unawaited(_loadSaved());
  }

  @override
  void dispose() {
    _downloadToken?.cancel();
    _work.dispose();
    _progress.dispose();
    _onlineFilters.query.dispose();
    _savedFilters.query.dispose();
    super.dispose();
  }

  Future<void> _loadOnline({bool refresh = false}) async {
    if (_loadingOnline) return;
    setState(() {
      _loadingOnline = true;
      _onlineError = null;
    });
    try {
      final assets = await widget.repository.load(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _catalog = assets;
        _onlineFilters.reconcile(assets);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _onlineError = _errorText(error, '在线目录加载失败，请检查网络后重试。'));
      }
    } finally {
      if (mounted) setState(() => _loadingOnline = false);
    }
  }

  Future<void> _loadSaved() async {
    if (_busy) return;
    _savedError = null;
    _work.value = _LibraryWork.reading;
    try {
      final saved = await widget.repository.listSaved();
      if (!mounted) return;
      _saved
        ..clear()
        ..addEntries(saved.map((item) => MapEntry(item.asset.id, item)));
      _savedFilters.reconcile(_savedAssets);
    } catch (error) {
      _savedError = _errorText(error, '无法读取已保存的参考图，请重试。');
    } finally {
      if (mounted) _work.value = null;
    }
  }

  Future<void> _runWork(
    BuildContext actionContext,
    String failure,
    Future<void> Function() action,
  ) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _work.value = _LibraryWork.editing;
    try {
      await action();
    } catch (error) {
      if (actionContext.mounted) {
        _notice(actionContext, _errorText(error, failure));
      }
    } finally {
      if (mounted) {
        _progress.value = null;
        _work.value = null;
      }
    }
  }

  Future<_DownloadResult> _download(
    List<CharacterReferenceAsset> assets,
  ) async {
    final token = _downloadToken = CancelToken();
    var savedCount = 0;
    var failedCount = 0;
    Object? firstError;
    try {
      for (var i = 0; i < assets.length; i++) {
        if (!mounted || token.isCancelled) break;
        final asset = assets[i];
        if (_saved.containsKey(asset.id)) continue;
        final label = assets.length == 1
            ? '正在下载 ${asset.name}'
            : '正在下载 ${i + 1}/${assets.length} · ${asset.name}';
        _progress.value = (
          label: label,
          value: assets.length == 1 ? null : i / assets.length,
          canCancel: true,
        );
        try {
          final reference = await widget.repository.download(
            asset,
            cancelToken: token,
            onProgress: (received, total) {
              if (!mounted || token.isCancelled || total <= 0) return;
              final fraction = (received / total).clamp(0.0, 1.0);
              _progress.value = (
                label: label,
                value: (i + fraction) / assets.length,
                canCancel: true,
              );
            },
          );
          if (!mounted) break;
          _saved[reference.asset.id] = reference;
          savedCount++;
        } catch (error) {
          if (token.isCancelled) break;
          failedCount++;
          firstError ??= error;
        }
      }
      return (
        saved: savedCount,
        failed: failedCount,
        error: firstError,
        cancelled: token.isCancelled,
      );
    } finally {
      _downloadToken = null;
      if (mounted) _progress.value = null;
    }
  }

  void _cancelDownload() {
    final token = _downloadToken;
    if (token == null || token.isCancelled) return;
    token.cancel();
    _progress.value = (label: '正在取消下载…', value: null, canCancel: false);
  }

  Future<SavedCharacterReference?> _ensureSaved(
    CharacterReferenceAsset asset,
  ) async {
    final existing = _saved[asset.id];
    if (existing != null) return existing;
    final result = await _download([asset]);
    if (result.error case final error?) throw error;
    return result.cancelled ? null : _saved[asset.id];
  }

  Future<void> _save(
          BuildContext actionContext, CharacterReferenceAsset asset) =>
      _runWork(actionContext, '参考图下载失败，请重试。', () async {
        final reference = await _ensureSaved(asset);
        if (actionContext.mounted) {
          _notice(actionContext, reference == null ? '已取消下载' : '已保存至参考预设');
        }
      });

  Future<void> _apply(
    BuildContext previewContext,
    CharacterReferenceAsset asset,
    Future<bool> Function(SavedCharacterReference) apply,
  ) =>
      _runWork(previewContext, '应用参考图失败，请重试。', () async {
        final saved = await _ensureSaved(asset);
        if (!mounted || saved == null || !previewContext.mounted) return;
        _progress.value = (label: '正在应用参考图…', value: null, canCancel: false);
        if (await apply(saved) &&
            previewContext.mounted &&
            ModalRoute.of(previewContext)?.isCurrent == true) {
          Navigator.of(previewContext).pop(true);
        }
      });

  Future<void> _downloadSeries(String game) async {
    if (_busy || ModalRoute.of(context)?.isCurrent != true) return;
    if (_savedError != null) {
      await _loadSaved();
      if (!mounted ||
          _tab != _LibraryTab.online ||
          _onlineFilters.game != game ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (_savedError case final error?) {
        _notice(context, error);
        return;
      }
    }
    final pending = _catalog
        .where((asset) => asset.game == game && !_saved.containsKey(asset.id))
        .toList(growable: false);
    if (pending.isEmpty) {
      _notice(context, '这部作品的参考图已全部保存');
      return;
    }

    final bytes = pending
        .where((asset) => asset.bytes > 0)
        .fold(0, (total, asset) => total + asset.bytes);
    final unknown = pending.where((asset) => asset.bytes <= 0).length;
    final size = unknown == 0
        ? '约 ${_formatBytes(bytes)}'
        : bytes == 0
            ? '大小未知'
            : '至少 ${_formatBytes(bytes)}，另有 $unknown 张大小未知';
    final confirmed = await _confirm(
      context,
      title: '下载整部作品？',
      description: '「$game」还有 ${pending.length} 张参考图待下载，$size。',
      label: '开始下载',
    );
    if (!mounted || !confirmed) return;

    await _runWork(context, '作品参考图下载失败，请重试。', () async {
      final result = await _download(pending);
      if (!mounted) return;
      if (result.cancelled) {
        _notice(context, '已取消下载，本次保存 ${result.saved} 张');
        return;
      }
      if (result.failed > 0) {
        final message = _errorText(result.error!, '请检查网络后重试。');
        _notice(
            context, '已保存 ${result.saved} 张，${result.failed} 张下载失败。$message');
        return;
      }
      _notice(context, '已保存 ${result.saved} 张参考图');
    });
  }

  Future<void> _remove(
    BuildContext previewContext,
    SavedCharacterReference saved,
  ) async {
    if (_busy || ModalRoute.of(previewContext)?.isCurrent != true) return;
    final confirmed = await _confirm(
      previewContext,
      title: '移除已保存的参考图？',
      description: '「${saved.asset.name}」将从参考预设的本地列表中移除。',
      label: '移除',
      destructive: true,
    );
    if (!previewContext.mounted || !confirmed) return;
    await _runWork(previewContext, '移除参考图失败，请重试。', () async {
      await widget.repository.remove(saved);
      if (!mounted) return;
      _saved.remove(saved.asset.id);
      _savedFilters.reconcile(_savedAssets);
      if (previewContext.mounted &&
          ModalRoute.of(previewContext)?.isCurrent == true) {
        Navigator.of(previewContext).pop();
      }
    });
  }

  Future<void> _importLocal() =>
      _runWork(context, '无法导入参考图，请检查所选图片。', () async {
        final images = await _picker.pickMultiImage();
        if (!mounted || images.isEmpty) return;
        final game = await _chooseImportGame(images.length);
        if (!mounted || game == null) return;

        var imported = 0;
        var failed = 0;
        Object? firstError;
        for (var i = 0; i < images.length; i++) {
          if (!mounted) return;
          final image = images[i];
          final name = p.basenameWithoutExtension(image.name).trim();
          _progress.value = (
            label: '正在导入 ${i + 1}/${images.length}',
            value: i / images.length,
            canCancel: false,
          );
          try {
            final saved = await widget.repository.importLocal(
              path: image.path,
              name: name.isEmpty ? '参考图' : name,
              game: game,
              category: _importCategory,
            );
            if (!mounted) return;
            _saved[saved.asset.id] = saved;
            imported++;
          } catch (error) {
            failed++;
            firstError ??= error;
          }
        }
        if (!mounted) return;
        if (imported > 0) {
          _savedFilters
            ..game = game
            ..category = _importCategory
            ..query.clear();
          _savedFilters.reconcile(_savedAssets);
        }
        final detail = firstError == null
            ? ''
            : '，$failed 张未导入。${_errorText(firstError, '请检查图片格式后重试。')}';
        _notice(context, '已导入 $imported 张参考图$detail');
      });

  Future<String?> _chooseImportGame(int count) {
    var game = '';
    return showStudioAlertDialog<String>(
      context: context,
      builder: (dialogContext) {
        void finish(String value) => Navigator.of(dialogContext)
            .pop(value.trim().isEmpty ? '其他' : value.trim());

        return StudioAlertDialog(
          title: const Text('导入角色参考图'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('已选 $count 张图片，角色名取自文件名。'),
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                child: TextField(
                  key: const ValueKey('reference-import-game'),
                  decoration:
                      const InputDecoration(labelText: '作品', hintText: '其他'),
                  textInputAction: TextInputAction.done,
                  onChanged: (value) => game = value,
                  onSubmitted: finish,
                ),
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => finish(game),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPreview(CharacterReferenceAsset asset) async {
    if (_editing || ModalRoute.of(context)?.isCurrent != true) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final canRemove = _tab == _LibraryTab.saved;

    final applied = await Navigator.of(context).push<bool>(
      studioPageRoute<bool>(
        name: '/character-reference-preview',
        context: context,
        builder: (context) => ValueListenableBuilder<_LibraryWork?>(
          valueListenable: _work,
          builder: (context, work, _) {
            final saved = _saved[asset.id];
            final precise = widget.onApplyPrecise;
            final vibe = widget.onApplyVibe;
            final canGoBack = work != _LibraryWork.editing;
            return PopScope<bool>(
              canPop: canGoBack,
              child: _ReferencePreview(
                asset: asset,
                saved: saved,
                repository: widget.repository,
                working: work != null,
                canGoBack: canGoBack,
                progress: _ReferenceProgress(
                  progress: _progress,
                  onCancel: _cancelDownload,
                ),
                onSave: saved == null ? () => _save(context, asset) : null,
                onApplyPrecise: precise == null
                    ? null
                    : () => _apply(context, asset, precise),
                onApplyVibe:
                    vibe == null ? null : () => _apply(context, asset, vibe),
                onRemove: canRemove && saved != null
                    ? () => _remove(context, saved)
                    : null,
                applyUnavailableReason: widget.applyUnavailableReason,
              ),
            );
          },
        ),
      ),
    );
    if (mounted &&
        applied == true &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _showSource() => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('目录来源'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(CharacterReferenceCatalogRepository.sourceName),
              for (final (title, link) in const [
                ('上游项目', CharacterReferenceCatalogRepository.sourceProject),
                ('图片资源库', CharacterReferenceCatalogRepository.sourceResources),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(title),
                  subtitle: SelectableText(link),
                  trailing: IconButton(
                    tooltip: '复制$title链接',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (dialogContext.mounted &&
                          ModalRoute.of(dialogContext)?.isCurrent == true) {
                        Navigator.of(dialogContext).pop();
                      }
                      if (mounted) _notice(context, '已复制$title链接');
                    },
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<_LibraryWork?>(
        valueListenable: _work,
        builder: (context, work, _) {
          final online = _tab == _LibraryTab.online;
          final filters = online ? _onlineFilters : _savedFilters;
          final assets = online ? _catalog : _savedAssets;
          final keyword = filters.query.text.trim();
          final visible = assets
              .where((asset) => filters.includes(asset, keyword))
              .toList(growable: false);
          final loading =
              online ? _loadingOnline : work == _LibraryWork.reading;
          final error = online ? _onlineError : _savedError;
          final VoidCallback reload =
              online ? () => _loadOnline(refresh: true) : _loadSaved;

          return StudioScaffold(
            appBar: AppBar(
              title: const Text('参考预设'),
              actions: [
                if (online)
                  IconButton(
                    tooltip: '目录来源',
                    onPressed: _showSource,
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                IconButton(
                  tooltip: online ? '刷新在线目录' : '刷新已保存',
                  onPressed: loading || (!online && _busy) ? null : reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<_LibraryTab>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _LibraryTab.online,
                            label: Text('在线目录'),
                          ),
                          ButtonSegment(
                            value: _LibraryTab.saved,
                            label: Text('已保存'),
                          ),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (selection) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() => _tab = selection.single);
                        },
                      ),
                    ),
                  ),
                  _ReferenceProgress(
                      progress: _progress, onCancel: _cancelDownload),
                  Expanded(
                    child: CustomScrollView(
                      key: PageStorageKey<String>(
                          'reference-library-${_tab.name}'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverToBoxAdapter(
                          child: _buildFilters(filters, assets, visible.length,
                              online: online),
                        ),
                        if (loading && assets.isNotEmpty)
                          const SliverToBoxAdapter(
                              child: LinearProgressIndicator()),
                        if (error != null && assets.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _ReferenceMessage(
                              icon: Icons.error_outline_rounded,
                              label: error,
                              onRetry: reload,
                            ),
                          ),
                        if (visible.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: loading && assets.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : _ReferenceMessage(
                                    icon: error != null
                                        ? Icons.error_outline_rounded
                                        : Icons.image_search_outlined,
                                    label: assets.isNotEmpty
                                        ? '没有符合条件的参考图'
                                        : error ??
                                            (online
                                                ? '在线目录暂无参考图'
                                                : '还没有已保存的参考图，可在线下载或从本机导入。'),
                                    onRetry: error != null && assets.isEmpty
                                        ? reload
                                        : null,
                                  ),
                          )
                        else
                          _buildGrid(visible, online: online),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _buildFilters(
    _LibraryFilters filters,
    List<CharacterReferenceAsset> assets,
    int count, {
    required bool online,
  }) {
    final game = filters.game;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: ValueKey('reference-search-${_tab.name}'),
            controller: filters.query,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索角色、作品或别名',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: filters.query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () => setState(filters.query.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ReferenceFilter(
                  key: const ValueKey('reference-game-filter'),
                  label: '全部作品',
                  value: game,
                  options: filters.games(assets),
                  onChanged: (value) => setState(() {
                    filters.game = value;
                    filters.reconcile(assets);
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReferenceFilter(
                  key: const ValueKey('reference-category-filter'),
                  label: '全部分类',
                  value: filters.category,
                  options: filters.categories(assets),
                  onChanged: (value) =>
                      setState(() => filters.category = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              if (assets.isNotEmpty)
                Text('$count 张角色参考图',
                    style: Theme.of(context).textTheme.labelMedium),
              if (online && game != null)
                TextButton.icon(
                  onPressed: _busy ? null : () => _downloadSeries(game),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('下载整部作品'),
                ),
              if (!online)
                TextButton.icon(
                  onPressed: _busy ? null : _importLocal,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('导入图片'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<CharacterReferenceAsset> assets,
      {required bool online}) {
    final textExtra = MediaQuery.textScalerOf(context).scale(56) - 56;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 198,
          mainAxisExtent: 218 + textExtra,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: assets.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = assets.indexWhere((asset) => asset.id == key.value);
          return index < 0 ? null : index;
        },
        itemBuilder: (_, index) {
          final asset = assets[index];
          final saved = _saved[asset.id];
          return _ReferenceCard(
            key: ValueKey(asset.id),
            repository: widget.repository,
            asset: asset,
            saved: saved,
            showSave: online,
            onOpen: _editing ? null : () => _openPreview(asset),
            onSave: _busy || saved != null ? null : () => _save(context, asset),
          );
        },
      ),
    );
  }
}

class _ReferenceFilter extends StatelessWidget {
  const _ReferenceFilter({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            isDense: true,
            value: value ?? '',
            onChanged: options.isEmpty
                ? null
                : (option) => onChanged(option == '' ? null : option),
            items: [
              DropdownMenuItem(value: '', child: Text(label)),
              for (final option in options)
                DropdownMenuItem(
                  value: option,
                  child: Text(option,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      );
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({
    super.key,
    required this.repository,
    required this.asset,
    required this.saved,
    required this.showSave,
    required this.onOpen,
    required this.onSave,
  });

  final CharacterReferenceCatalogRepository repository;
  final CharacterReferenceAsset asset;
  final SavedCharacterReference? saved;
  final bool showSave;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ReferenceImage(
                    repository: repository,
                    asset: asset,
                    localPath: saved?.path,
                    compact: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [asset.variant, asset.game]
                            .where((part) => part.isNotEmpty)
                            .join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showSave)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                key: ValueKey('reference-save-${asset.id}'),
                onPressed: onSave,
                tooltip: saved == null ? '保存参考图' : '已保存',
                icon: Icon(
                    saved == null
                        ? Icons.download_rounded
                        : Icons.download_done_rounded,
                    size: 20),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  backgroundColor: Colors.black54,
                  disabledBackgroundColor: Colors.black45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReferencePreview extends StatelessWidget {
  const _ReferencePreview({
    required this.asset,
    required this.saved,
    required this.repository,
    required this.working,
    required this.canGoBack,
    required this.progress,
    required this.onSave,
    required this.onApplyPrecise,
    required this.onApplyVibe,
    required this.onRemove,
    required this.applyUnavailableReason,
  });

  final CharacterReferenceAsset asset;
  final SavedCharacterReference? saved;
  final CharacterReferenceCatalogRepository repository;
  final bool working;
  final bool canGoBack;
  final Widget progress;
  final VoidCallback? onSave;
  final VoidCallback? onApplyPrecise;
  final VoidCallback? onApplyVibe;
  final VoidCallback? onRemove;
  final String? applyUnavailableReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [asset.game, asset.category, asset.variant]
        .where((part) => part.isNotEmpty)
        .join(' · ');
    final properties = [
      if (asset.width > 0 && asset.height > 0)
        '${asset.width} × ${asset.height}',
      if (asset.bytes > 0) _formatBytes(asset.bytes),
      if (saved != null) '已保存，可离线使用',
    ].join(' · ');

    return StudioScaffold(
      appBar: AppBar(
        title: Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: canGoBack
            ? null
            : const IconButton(
                onPressed: null,
                tooltip: '返回',
                icon: BackButtonIcon(),
              ),
        actions: [
          if (onRemove != null)
            IconButton(
              onPressed: working ? null : onRemove,
              tooltip: '移除已保存的参考图',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: (constraints.maxHeight * 0.64).clamp(180.0, 620.0),
                  child: _ReferenceImage(
                    repository: repository,
                    asset: asset,
                    localPath: saved?.path,
                    allowFullscreen: !working,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(subtitle, style: theme.textTheme.titleSmall),
              if (properties.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(properties, style: theme.textTheme.bodySmall),
                ),
              progress,
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (onSave != null)
                    OutlinedButton.icon(
                      onPressed: working ? null : onSave,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('保存参考图'),
                    ),
                  if (onApplyPrecise != null)
                    FilledButton.tonalIcon(
                      onPressed: working ? null : onApplyPrecise,
                      icon: const Icon(Icons.person_pin_outlined),
                      label: const Text('用作角色精确参考'),
                    ),
                  if (onApplyVibe != null)
                    FilledButton.tonalIcon(
                      onPressed: working ? null : onApplyVibe,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('用作氛围转移'),
                    ),
                ],
              ),
              if (onApplyPrecise == null &&
                  onApplyVibe == null &&
                  applyUnavailableReason != null)
                Text(applyUnavailableReason!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceImage extends StatefulWidget {
  const _ReferenceImage({
    required this.repository,
    required this.asset,
    required this.localPath,
    this.compact = false,
    this.allowFullscreen = false,
  });

  final CharacterReferenceCatalogRepository repository;
  final CharacterReferenceAsset asset;
  final String? localPath;
  final bool compact;
  final bool allowFullscreen;

  @override
  State<_ReferenceImage> createState() => _ReferenceImageState();
}

class _ReferenceImageState extends State<_ReferenceImage> {
  Future<String?>? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ReferenceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id ||
        !listEquals(
            oldWidget.asset.thumbnailUrls, widget.asset.thumbnailUrls) ||
        oldWidget.repository != widget.repository ||
        oldWidget.localPath != widget.localPath) {
      _load();
    }
  }

  void _load() {
    _preview = widget.localPath != null
        ? null
        : Future.sync(() => widget.repository.previewPath(widget.asset));
  }

  Widget _unavailable() => widget.compact
      ? const Center(child: Icon(Icons.image_not_supported_outlined))
      : _ReferenceMessage(
          icon: Icons.image_not_supported_outlined,
          label: '参考图预览加载失败',
          onRetry: widget.localPath == null ? () => setState(_load) : null,
        );

  Widget _image(String path) => LayoutBuilder(
        builder: (context, constraints) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final provider = ResizeImage(
            FileImage(File(path)),
            width: (constraints.maxWidth * ratio).round().clamp(64, 1600),
            height: (constraints.maxHeight * ratio).round().clamp(64, 1600),
            policy: ResizeImagePolicy.fit,
          );
          return Image(
            image: provider,
            fit: BoxFit.contain,
            semanticLabel: widget.asset.name,
            errorBuilder: (_, __, ___) => _unavailable(),
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (!widget.allowFullscreen || frame == null) return child;
              return Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: IconButton.filledTonal(
                      tooltip: '全屏预览',
                      onPressed: () =>
                          showFullscreenImagePreview(context, imagePath: path),
                      icon: const Icon(Icons.fullscreen_rounded),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: switch (widget.localPath) {
          final path? => _image(path),
          null => FutureBuilder<String?>(
              future: _preview,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final path = snapshot.data;
                return path == null ? _unavailable() : _image(path);
              },
            ),
        },
      );
}

class _ReferenceProgress extends StatelessWidget {
  const _ReferenceProgress({required this.progress, required this.onCancel});

  final ValueListenable<_Progress?> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<_Progress?>(
        valueListenable: progress,
        builder: (context, state, _) {
          if (state == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(state.label,
                            maxLines: 2, overflow: TextOverflow.ellipsis)),
                    if (state.canCancel)
                      TextButton(
                          onPressed: onCancel, child: const Text('取消下载')),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: state.value),
              ],
            ),
          );
        },
      );
}

class _ReferenceMessage extends StatelessWidget {
  const _ReferenceMessage(
      {required this.icon, required this.label, this.onRetry});

  final IconData icon;
  final String label;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String description,
  required String label,
  bool destructive = false,
}) async =>
    await showStudioAlertDialog<bool>(
      context: context,
      builder: (dialogContext) => StudioAlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: !destructive,
            isDestructiveAction: destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(label),
          ),
        ],
      ),
    ) ??
    false;

void _notice(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}

String _errorText(Object error, String fallback) => switch (error) {
      FormatException(:final message) when message.isNotEmpty => message,
      StateError(:final message) when message.toString().isNotEmpty =>
        message.toString(),
      _ => fallback,
    };

String _formatBytes(int bytes) {
  const kib = 1024;
  const mib = kib * kib;
  if (bytes < kib) return '$bytes B';
  if (bytes < mib) return '${(bytes / kib).toStringAsFixed(1)} KB';
  return '${(bytes / mib).toStringAsFixed(1)} MB';
}
