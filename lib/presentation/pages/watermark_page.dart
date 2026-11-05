import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/watermark_library_store.dart';
import 'package:nai_huishi/domain/entities/watermark.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/controllers/watermark_compositor.dart';
import 'package:nai_huishi/presentation/widgets/api_config_widgets.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/studio_scaffold.dart';
import 'package:nai_huishi/presentation/widgets/watermark_canvas.dart';
import 'package:uuid/uuid.dart';

class WatermarkPage extends StatefulWidget {
  final WatermarkLibraryStore? library;
  final ImagePicker? picker;
  final Future<bool> Function(Uint8List)? saveToGallery;

  const WatermarkPage(
      {super.key, this.library, this.picker, this.saveToGallery});

  @override
  State<WatermarkPage> createState() => _WatermarkPageState();
}

class _WatermarkPageState extends State<WatermarkPage> {
  late final WatermarkLibraryStore _store =
      widget.library ?? WatermarkLibraryStore();
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  final _images = <String, ui.Image>{};
  final _layers = <WatermarkLayer>[];
  final _panelScroll = ScrollController();
  List<WatermarkAsset> _library = [];
  ui.Image? _base;
  String? _selectedId;
  bool _busy = false;
  bool _toolsVisible = true;
  bool _loadingLibrary = true;
  String? _error;

  WatermarkLayer? get _selected {
    for (final layer in _layers) {
      if (layer.id == _selectedId) return layer;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      final assets = await _store.load();
      if (mounted) setState(() => _library = assets);
    } catch (_) {
      if (mounted) setState(() => _error = '水印库读取失败，请重试');
    } finally {
      if (mounted) setState(() => _loadingLibrary = false);
    }
  }

  @override
  void dispose() {
    _panelScroll.dispose();
    _base?.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBase() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final image = await WatermarkCompositor.decode(await file.readAsBytes());
      if (!mounted) {
        image.dispose();
        return;
      }
      final previous = _base;
      setState(() => _base = image);
      // Layer positions remain proportional when changing the base image.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
    } catch (_) {
      if (mounted) setState(() => _error = '图片导入失败，请重新选择');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importWatermarks() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var imported = 0;
    var failed = 0;
    try {
      final files = await _picker.pickMultiImage();
      for (final file in files) {
        if (!mounted) break;
        try {
          final asset = await _store.importFile(file.path);
          imported++;
          if (!mounted) break;
          setState(() => _library = [asset, ..._library]);
          if (files.length == 1 && _base != null) await _addLayer(asset);
        } catch (_) {
          failed++;
        }
      }
      if (mounted && imported > 0) {
        showFloatingToast(context, '已保存 $imported 张水印，可在水印库中重复使用');
      }
      if (mounted && failed > 0) {
        setState(() => _error = '$failed 张水印未能导入，请检查图片后重试');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法导入水印，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addLayer(WatermarkAsset asset) async {
    if (_base == null) {
      showFloatingToast(context, '请先导入底图');
      return;
    }
    var image = _images[asset.id];
    if (image == null) {
      image = await WatermarkCompositor.decode(
          await File(asset.path).readAsBytes());
      if (!mounted) {
        image.dispose();
        return;
      }
      _images[asset.id] = image;
    }
    final layer = WatermarkLayer(id: const Uuid().v4(), assetId: asset.id);
    setState(() {
      _layers.add(layer);
      _selectedId = layer.id;
    });
    if (_panelScroll.hasClients) _panelScroll.jumpTo(0);
  }

  Future<void> _useWatermark(WatermarkAsset asset) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _addLayer(asset);
    } catch (_) {
      if (mounted) setState(() => _error = '水印图片无法读取，请重新导入');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _updateLayer(WatermarkLayer layer) {
    final index = _layers.indexWhere((item) => item.id == layer.id);
    if (index >= 0) setState(() => _layers[index] = layer);
  }

  Future<void> _deleteAsset(WatermarkAsset asset) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => ApiConfigDialog(
              title: '删除这张水印？',
              content: const Text('会从水印库和当前图层中移除，原始图片保留。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store.remove(asset);
      if (!mounted) return;
      setState(() {
        _library.removeWhere((item) => item.id == asset.id);
        _layers.removeWhere((layer) => layer.assetId == asset.id);
        if (_selected == null) _selectedId = null;
      });
      final image = _images.remove(asset.id);
      WidgetsBinding.instance.addPostFrameCallback((_) => image?.dispose());
    } catch (_) {
      if (mounted) setState(() => _error = '删除失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final base = _base;
    if (base == null || _layers.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes =
          await WatermarkCompositor.exportPng(base, List.of(_layers), _images);
      if (!mounted) return;
      final saved = await (widget.saveToGallery?.call(bytes) ??
          sl<SaveImageUseCase>().savePngBytesToGallery(bytes));
      if (!saved) throw StateError('Save failed');
      if (mounted) {
        showFloatingToast(context, '已按原图尺寸保存 PNG 到相册',
            icon: CupertinoIcons.checkmark_circle);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请检查相册权限或可用空间后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    return PopScope(
      canPop: !_busy,
      child: StudioScaffold(
        appBar: AppBar(title: const Text('添加水印'), actions: [
          TextButton(
              onPressed: _busy ? null : _pickBase,
              child: Text(_base == null ? '导入底图' : '更换底图')),
        ]),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const ValueKey('watermark-export'),
            onPressed:
                _base == null || _layers.isEmpty || _busy ? null : _export,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(CupertinoIcons.square_arrow_down, size: 20),
            label: Text(_busy ? '处理中…' : '保存到相册'),
          ),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(builder: (context, constraints) {
            final stage = Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
              child: Column(children: [
                Expanded(child: _buildStage()),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text(
                      _base == null
                          ? '先导入底图，再从水印库添加图片图层。'
                          : '${_base!.width} × ${_base!.height} · 全图拖动，双指缩放旋转；拖动角点调整',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              ]),
            );
            final panel = ListView(
              key: const ValueKey('watermark-properties'),
              controller: _panelScroll,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      child: Text(_error!,
                          key: const ValueKey('watermark-error'),
                          style: TextStyle(color: theme.colorScheme.error))),
                if (selected != null) ...[
                  _buildControls(selected),
                  const SizedBox(height: 14),
                ],
                _buildLibrary(),
                if (_layers.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildLayers(),
                ],
              ],
            );
            if (constraints.maxWidth >= 720) {
              return Row(children: [
                Expanded(child: stage),
                SizedBox(width: 340, child: panel)
              ]);
            }
            return Column(children: [
              Expanded(child: stage),
              SizedBox(
                height: 40,
                child: TextButton.icon(
                  key: const ValueKey('watermark-toggle-tools'),
                  onPressed: () =>
                      setState(() => _toolsVisible = !_toolsVisible),
                  icon: Icon(
                      _toolsVisible ? Icons.expand_more : Icons.expand_less),
                  label: Text(_toolsVisible ? '收起工具 · 扩大画布' : '展开水印工具'),
                ),
              ),
              if (_toolsVisible)
                SizedBox(
                    height: math.min(210, constraints.maxHeight * .3),
                    child: panel),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _buildStage() => ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: ColoredBox(
          color: FrostedTheme.of(context).stage,
          child: SizedBox.expand(
            key: const ValueKey('watermark-workspace'),
            child: _base == null
                ? InkWell(
                    onTap: _busy ? null : _pickBase,
                    child: Center(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.photo_on_rectangle,
                            size: 44,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 14),
                        const Text('导入需要添加水印的图片'),
                      ],
                    )))
                : WatermarkCanvas(
                    base: _base!,
                    layers: List.of(_layers),
                    images: _images,
                    selectedId: _selectedId,
                    enabled: !_busy,
                    onSelected: (id) {
                      setState(() => _selectedId = id);
                      if (id != null && _panelScroll.hasClients) {
                        _panelScroll.jumpTo(0);
                      }
                    },
                    onChanged: _updateLayer),
          ),
        ),
      );
  Widget _buildControls(WatermarkLayer layer) => FrostedSurface(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text('调整水印',
                    style: Theme.of(context).textTheme.titleSmall)),
            TextButton(
                onPressed: _busy
                    ? null
                    : () => _updateLayer(
                        WatermarkLayer(id: layer.id, assetId: layer.assetId)),
                child: const Text('重置')),
          ]),
          _slider(
              '大小',
              '${(layer.widthFraction * 100).round()}%',
              layer.widthFraction,
              .02,
              1.5,
              (value) => _updateLayer(layer.copyWith(widthFraction: value)),
              'watermark-size'),
          _slider(
              '旋转',
              '${(layer.rotation * 180 / math.pi).round()}°',
              layer.rotation,
              -math.pi,
              math.pi,
              (value) => _updateLayer(layer.copyWith(rotation: value)),
              'watermark-rotation'),
          _slider(
              '不透明度',
              '${(layer.opacity * 100).round()}%',
              layer.opacity,
              0,
              1,
              (value) => _updateLayer(layer.copyWith(opacity: value)),
              'watermark-opacity'),
        ]),
      );

  Widget _slider(String title, String value, double number, double min,
          double max, ValueChanged<double> onChanged, String key) =>
      Column(children: [
        Row(children: [
          Text(title),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant))
        ]),
        Slider(
            key: ValueKey(key),
            value: number.clamp(min, max),
            min: min,
            max: max,
            onChanged: _busy ? null : onChanged),
      ]);

  Widget _buildLibrary() => FrostedSurface(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text('水印库 · ${_library.length}',
                    style: Theme.of(context).textTheme.titleSmall)),
            TextButton.icon(
                key: const ValueKey('watermark-import'),
                onPressed: _busy || _loadingLibrary ? null : _importWatermarks,
                icon: const Icon(CupertinoIcons.plus, size: 16),
                label: const Text('导入水印')),
          ]),
          Text('保存在应用内；点选添加图层，长按可删除。建议使用透明 PNG。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_loadingLibrary)
            const Center(child: CircularProgressIndicator())
          else if (_library.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('还没有水印，可一次导入多张签名或标志。'))
          else
            SizedBox(
                height: 116,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _library.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final asset = _library[index];
                    return SizedBox(
                        width: 100,
                        child: InkWell(
                          key: ValueKey('watermark-asset-${asset.id}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: _busy ? null : () => _useWatermark(asset),
                          onLongPress: _busy ? null : () => _deleteAsset(asset),
                          child: Column(children: [
                            Expanded(
                                child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: ColoredBox(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: SizedBox.expand(
                                          child: Image.file(File(asset.path),
                                              cacheWidth: 240,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                      CupertinoIcons.photo))),
                                    ))),
                            const SizedBox(height: 6),
                            Text(asset.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        ));
                  },
                )),
        ]),
      );

  Widget _buildLayers() => FrostedSurface(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('图层 · ${_layers.length}',
                  style: Theme.of(context).textTheme.titleSmall)),
          for (var i = _layers.length - 1; i >= 0; i--)
            ListTile(
              key: ValueKey('watermark-layer-${_layers[i].id}'),
              selected: _selectedId == _layers[i].id,
              leading: const Icon(CupertinoIcons.square_stack_3d_up, size: 20),
              title: Text('水印图层 ${i + 1}'),
              subtitle: Text(
                  _library.firstWhere((a) => a.id == _layers[i].assetId).name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              onTap: _busy
                  ? null
                  : () => setState(() => _selectedId = _layers[i].id),
              trailing: PopupMenuButton<String>(
                enabled: !_busy,
                tooltip: '图层操作',
                onSelected: (action) => _layerAction(i, action),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'duplicate', child: Text('复制图层')),
                  if (i < _layers.length - 1)
                    const PopupMenuItem(value: 'up', child: Text('上移一层')),
                  if (i > 0)
                    const PopupMenuItem(value: 'down', child: Text('下移一层')),
                  const PopupMenuItem(value: 'delete', child: Text('删除图层')),
                ],
              ),
            ),
        ]),
      );

  void _layerAction(int index, String action) {
    setState(() {
      final layer = _layers[index];
      if (action == 'delete') {
        _layers.removeAt(index);
        if (_selectedId == layer.id) {
          _selectedId = _layers.isEmpty ? null : _layers.last.id;
        }
      } else if (action == 'duplicate') {
        final copy = layer.copyWith(id: const Uuid().v4());
        _layers.insert(index + 1, copy);
        _selectedId = copy.id;
      } else {
        final target = action == 'up' ? index + 1 : index - 1;
        if (target < 0 || target >= _layers.length) return;
        _layers[index] = _layers[target];
        _layers[target] = layer;
      }
    });
  }
}
