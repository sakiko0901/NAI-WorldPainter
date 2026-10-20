import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/inpaint_workspace.dart';
import 'package:nai_huishi/domain/services/inpaint_rasterizer.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_canvas_painter.dart';
import 'package:nai_huishi/presentation/widgets/inpaint_comparison.dart';

/// 工作区顶部的选择模式。
enum InpaintUiMode {
  view, // 整体移动：图片与输出框同步
  image, // 移动源图：输出框固定
  frame, // 移动输出框：源图固定
  brush, // 绘制当前图层
  erase, // 擦除当前图层
}

// ============================================================================
// 后台 isolate 图像处理（避免 UI 主线程长时间阻塞触发 ANR 闪退）。
// ============================================================================

/// 图片文件解码：返回 PNG 字节（RGBA）+ 宽高。
class _DecodeImageInput {
  final Uint8List fileBytes;
  const _DecodeImageInput(this.fileBytes);
}

class _DecodeImageResult {
  final Uint8List pngBytes;
  final int width;
  final int height;
  const _DecodeImageResult(this.pngBytes, this.width, this.height);
}

_DecodeImageResult _decodeImageIsolate(_DecodeImageInput input) {
  final decoded = img.decodeImage(input.fileBytes);
  if (decoded == null) {
    throw const FormatException('无法解码图片');
  }
  final rgba = decoded.convert(numChannels: 4);
  return _DecodeImageResult(
    Uint8List.fromList(img.encodePng(rgba)),
    rgba.width,
    rgba.height,
  );
}

/// 光栅化 + 编码：选择框世界坐标 → base 图 / 工作区图 / 遮罩 PNG。
class _RasterizeInput {
  final Uint8List sourcePng;
  final List<InpaintStroke> strokes;
  final InpaintViewport worldRect;
  final int outputWidth;
  final int outputHeight;
  final int expandPixels;
  final List<_CompositeLayerInput> comparisonLayers;
  const _RasterizeInput({
    required this.sourcePng,
    required this.strokes,
    required this.worldRect,
    required this.outputWidth,
    required this.outputHeight,
    required this.expandPixels,
    this.comparisonLayers = const [],
  });
}

class _RasterizeResult {
  final Uint8List basePng;
  final Uint8List maskPng;
  final Uint8List comparisonBasePng;
  const _RasterizeResult(this.basePng, this.maskPng, this.comparisonBasePng);
}

_RasterizeResult _rasterizeIsolate(_RasterizeInput input) {
  final source = img.decodePng(input.sourcePng);
  if (source == null) throw const FormatException('源图解码失败');
  const rasterizer = InpaintRasterizer();
  final composed = rasterizer.composeBase(
    source: source,
    strokes: input.strokes,
  );
  final result = rasterizer.rasterize(
    source: composed,
    worldRect: input.worldRect,
    outputWidth: input.outputWidth,
    outputHeight: input.outputHeight,
    strokes: input.strokes,
    expandPixels: input.expandPixels,
  );
  final comparisonBase = img.Image.from(result.image);
  for (final entry in input.comparisonLayers) {
    final layer = img.decodePng(entry.imagePng);
    if (layer == null) throw const FormatException('结果图层解码失败');
    final placed = rasterizer.rasterize(
      source: layer,
      sourceBounds: entry.worldRect,
      worldRect: input.worldRect,
      outputWidth: input.outputWidth,
      outputHeight: input.outputHeight,
      strokes: const [],
    );
    img.compositeImage(comparisonBase, placed.image);
  }
  return _RasterizeResult(
    Uint8List.fromList(img.encodePng(result.image)),
    rasterizer.encodeMask(result.mask),
    Uint8List.fromList(img.encodePng(comparisonBase)),
  );
}

/// 候选转为带蒙版透明度的独立结果图层。
class _MaskLayerInput {
  final Uint8List basePng;
  final Uint8List maskPng;
  final Uint8List generatedPng;
  final int featherPixels;
  const _MaskLayerInput({
    required this.basePng,
    required this.maskPng,
    required this.generatedPng,
    required this.featherPixels,
  });
}

class _CandidateImages {
  final Uint8List layerPng;
  final Uint8List comparisonPng;
  const _CandidateImages(this.layerPng, this.comparisonPng);
}

class _ReviewCandidate {
  final InpaintCandidate candidate;
  final String layerPath;
  final String comparisonPath;
  final String beforePath;
  final int width;
  final int height;
  const _ReviewCandidate(this.candidate, this.layerPath, this.comparisonPath,
      this.beforePath, this.width, this.height);
}

_CandidateImages _maskLayerIsolate(_MaskLayerInput input) {
  final base = img.decodePng(input.basePng);
  final mask = img.decodePng(input.maskPng);
  final generated = img.decodePng(input.generatedPng);
  if (base == null || mask == null || generated == null) {
    throw const FormatException('候选图片解码失败');
  }
  const rasterizer = InpaintRasterizer();
  final layer = rasterizer.maskGeneratedLayer(
    generated: generated,
    mask: mask,
    outwardFeatherPixels: input.featherPixels,
    base: base,
  );
  img.compositeImage(base, layer);
  return _CandidateImages(
    Uint8List.fromList(img.encodePng(layer)),
    Uint8List.fromList(img.encodePng(base)),
  );
}

class _CompositeLayerInput {
  final Uint8List imagePng;
  final InpaintViewport worldRect;

  const _CompositeLayerInput(this.imagePng, this.worldRect);
}

class _CompositeWorkspaceInput {
  final Uint8List sourcePng;
  final List<InpaintStroke> strokes;
  final List<_CompositeLayerInput> layers;

  const _CompositeWorkspaceInput(this.sourcePng, this.strokes, this.layers);
}

Uint8List _composeWorkspaceIsolate(_CompositeWorkspaceInput input) {
  final source = img.decodePng(input.sourcePng);
  if (source == null) throw const FormatException('原图解码失败');
  final layers = <InpaintRasterLayer>[];
  for (final layer in input.layers) {
    final image = img.decodePng(layer.imagePng);
    if (image == null) throw const FormatException('结果图层解码失败');
    layers.add(InpaintRasterLayer(image: image, worldRect: layer.worldRect));
  }
  final composite = const InpaintRasterizer().composeLayers(
    source: source,
    strokes: input.strokes,
    layers: layers,
  );
  return Uint8List.fromList(img.encodePng(composite));
}

/// 等比例放大图片分辨率。
class _ResizeImageInput {
  final Uint8List sourcePng;
  final int scale;
  const _ResizeImageInput(this.sourcePng, this.scale);
}

Uint8List _resizeImageIsolate(_ResizeImageInput input) {
  final source = img.decodePng(input.sourcePng);
  if (source == null) throw const FormatException('无法读取图片');
  final resized = img.copyResize(
    source,
    width: source.width * input.scale,
    height: source.height * input.scale,
    interpolation: img.Interpolation.cubic,
  );
  return Uint8List.fromList(img.encodePng(resized));
}

/// 遮罩预览：编码 → 解码 → 着色 → PNG（后台执行避免卡顿）。
class _MaskPreviewInput {
  final Uint8List sourcePng;
  final List<InpaintStroke> strokes;
  final InpaintViewport worldRect;
  final int outputWidth;
  final int outputHeight;
  final int expandPixels;
  final int borderPixels;
  const _MaskPreviewInput({
    required this.sourcePng,
    required this.strokes,
    required this.worldRect,
    required this.outputWidth,
    required this.outputHeight,
    required this.expandPixels,
    required this.borderPixels,
  });
}

Uint8List _maskPreviewIsolate(_MaskPreviewInput input) {
  final source = img.decodePng(input.sourcePng);
  if (source == null) throw const FormatException('源图解码失败');
  const rasterizer = InpaintRasterizer();
  final composed =
      rasterizer.composeBase(source: source, strokes: input.strokes);
  final mask = rasterizer
      .rasterize(
        source: composed,
        worldRect: input.worldRect,
        outputWidth: input.outputWidth,
        outputHeight: input.outputHeight,
        strokes: input.strokes,
        expandPixels: input.expandPixels,
      )
      .mask;
  final encoded = rasterizer.encodeMask(mask);
  final aligned = img.decodePng(encoded);
  if (aligned == null) {
    throw const FormatException('遮罩编码失败');
  }
  final preview = img.Image(
    width: aligned.width,
    height: aligned.height,
    numChannels: 4,
  );
  for (var y = 0; y < aligned.height; y++) {
    for (var x = 0; x < aligned.width; x++) {
      final selected = aligned.getPixel(x, y).r > 0;
      var edge = false;
      if (selected) {
        for (var distance = 1; distance <= input.borderPixels; distance++) {
          if (x - distance < 0 ||
              y - distance < 0 ||
              x + distance >= aligned.width ||
              y + distance >= aligned.height ||
              aligned.getPixel(x - distance, y).r == 0 ||
              aligned.getPixel(x + distance, y).r == 0 ||
              aligned.getPixel(x, y - distance).r == 0 ||
              aligned.getPixel(x, y + distance).r == 0) {
            edge = true;
            break;
          }
        }
      }
      if (edge) {
        preview.setPixelRgba(x, y, 128, 216, 255, 255);
      } else {
        preview.setPixelRgba(x, y, 33, 150, 243, selected ? 128 : 0);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(preview));
}

enum _GestureKind { none, draw, moveBox, panScene, moveGlobal }

/// 局部重绘工作区（嵌入生成页内的圆角卡片组件）。
class InpaintWorkspaceCard extends StatefulWidget {
  const InpaintWorkspaceCard({super.key});

  /// 工作区手势激活中（绘制遮罩/拖框/移动图片/对比拖动）。
  /// 生成页监听它来锁定页面滚动，避免涂抹遮罩时页面跟着移动。
  static final ValueNotifier<bool> gestureActive = ValueNotifier(false);

  @override
  State<InpaintWorkspaceCard> createState() => _InpaintWorkspaceCardState();
}

class _InpaintWorkspaceCardState extends State<InpaintWorkspaceCard>
    with AutomaticKeepAliveClientMixin<InpaintWorkspaceCard> {
  static const double _boxMinSize = 48;
  static const double _snapTolerancePx = 8;

  final _picker = ImagePicker();
  late final GenerationViewModel _generation;
  late final GenerationQueue _queue;
  late final SaveImageUseCase _saveImage;
  final _promptController = TextEditingController();
  final _negativeController = TextEditingController();

  String? _sourcePath;

  /// 源图 RGBA PNG 字节（后台 isolate 复用），以及宽高。
  Uint8List? _sourcePngBytes;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  InpaintTransform _transform = const InpaintTransform();

  /// 屏幕坐标下的选择框，宽高比固定为输出分辨率。
  InpaintBox? _box;
  Size _stageSize = Size.zero;

  final List<InpaintStroke> _strokes = [];
  final List<List<InpaintStroke>> _undo = [];
  final List<List<InpaintStroke>> _redo = [];
  final List<List<InpaintStroke>> _maskUndo = [];
  final List<List<InpaintStroke>> _maskRedo = [];
  final List<InpaintResultLayer> _resultLayers = [];
  final List<_ReviewCandidate> _candidates = [];
  String? _selectedCandidateId;
  bool _reviewOpen = false;
  InpaintPaintTarget _target = InpaintPaintTarget.mask;
  double _brushSize = 48;
  int _expandPixels = 8;
  int _featherPixels = 8;
  double _inpaintStrength = 0.96;
  bool _showMask = true;
  bool _disabledOriginalImage = false;
  bool _colorCorrect = true;
  bool _promptExpanded = true;
  bool _paramsExpanded = false;
  bool _busy = false;
  InpaintStroke? _draft;
  final List<InpaintPoint> _draftPoints = [];
  ui.Path _maskPath = ui.Path();
  final ValueNotifier<ui.Path?> _previewMaskPath = ValueNotifier(null);
  int _batchCompleted = 0;
  int _batchTotal = 1;
  final Map<int, Offset> _pointers = {};
  _GestureKind _gesture = _GestureKind.none;
  Offset? _lastGestureCenter;
  double? _lastGestureDistance;
  String? _sessionSourcePath;
  String? _sessionMaskPath;
  String? _loadingSourcePath;
  String? _failedSourcePath;
  int _sourceLoadRevision = 0;
  int _generationRevision = 0;
  String? _activeRevision;
  bool _officialUpscaling = false;
  bool _addingLayer = false;
  int _layerSequence = 0;

  /// 遮罩预览：后台生成，签名匹配才显示（防抖 + 防错位）。
  String? _maskPreviewSignature;
  String _maskPreviewKey = '';
  Uint8List? _maskPreviewBytes;
  Timer? _maskPreviewDebounce;

  InpaintUiMode _uiMode = InpaintUiMode.view;

  /// 笔刷形状：圆形（默认）或方形。
  bool _squareBrush = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _generation = sl<GenerationViewModel>();
    _queue = sl<GenerationQueue>();
    _saveImage = sl<SaveImageUseCase>();
    // 页面底部生成按钮触发时，由工作区执行完整生成本轮局部重绘。
    _generation.inpaintWorkspaceHandler = _prepareGeneration;
    // 生成页"局部重绘"按钮导入新图时（VM sourceImagePath 变化），重新加载。
    _generation.addListener(_onVmChanged);
    _promptController.text = _generation.inpaintPrompt;
    _negativeController.text = _generation.inpaintNegativePrompt;
    _inpaintStrength = _generation.inpaintStrength;
    _disabledOriginalImage = _generation.disabledOriginalImage;
    _colorCorrect = _generation.colorCorrect;
    final initial = _generation.sourceImagePath;
    if (initial != null && File(initial).existsSync()) {
      _loadImage(initial, resetSession: false);
    }
  }

  /// VM sourceImagePath 变化 → 新图导入，重新加载。
  /// 忽略工作区自己写回的 session 产物（base/mask），避免把方框裁剪图
  /// 误当新图加载造成"图片被裁切"。
  void _onVmChanged() {
    final path = _generation.sourceImagePath;
    if (path == null ||
        path == _sourcePath ||
        path == _loadingSourcePath ||
        path == _failedSourcePath) {
      return;
    }
    if (_sessionSourcePath != null && path == _sessionSourcePath) return;
    if (_sessionMaskPath != null && path == _sessionMaskPath) return;
    if (!File(path).existsSync()) return;
    _loadImage(path);
  }

  @override
  void dispose() {
    InpaintWorkspaceCard.gestureActive.value = false;
    _generation.removeListener(_onVmChanged);
    if (_generation.inpaintWorkspaceHandler == _prepareGeneration) {
      _generation.inpaintWorkspaceHandler = null;
    }
    _maskPreviewDebounce?.cancel();
    _promptController.dispose();
    _negativeController.dispose();
    _previewMaskPath.dispose();
    super.dispose();
  }

  Future<void> _loadImage(
    String path, {
    bool resetSession = true,
  }) async {
    final file = File(path);
    final revision = ++_sourceLoadRevision;
    _loadingSourcePath = path;
    _failedSourcePath = null;
    try {
      if (!await file.exists()) {
        throw FileSystemException('找不到图片文件', path);
      }
      // 后台解码大图，避免主线程阻塞。
      final fileBytes = await file.readAsBytes();
      final result = await compute<_DecodeImageInput, _DecodeImageResult>(
        _decodeImageIsolate,
        _DecodeImageInput(fileBytes),
      );
      if (!mounted || revision != _sourceLoadRevision) return;
      // 保留磁盘上的 PNG 字节供后台光栅化复用（RGBA 无损）。
      _sourcePngBytes = result.pngBytes;
      setState(() {
        _sourcePath = path;
        _sourceWidth = result.width;
        _sourceHeight = result.height;
        _transform = const InpaintTransform();
        _box = null;
        _strokes.clear();
        _draft = null;
        _draftPoints.clear();
        _maskPath = ui.Path();
        _previewMaskPath.value = null;
        _undo.clear();
        _redo.clear();
        _maskUndo.clear();
        _maskRedo.clear();
        _maskPreviewDebounce?.cancel();
        _maskPreviewSignature = null;
        _maskPreviewKey = '';
        _maskPreviewBytes = null;
        _showMask = true;
        _uiMode = InpaintUiMode.view;
        if (resetSession) {
          _resultLayers.clear();
          _candidates.clear();
          _selectedCandidateId = null;
          _reviewOpen = false;
          _layerSequence = 0;
          _sessionSourcePath = null;
          _sessionMaskPath = null;
          _activeRevision = null;
        }
      });
    } catch (error) {
      if (mounted && revision == _sourceLoadRevision) {
        _failedSourcePath = path;
        showFloatingToast(context, '图片加载失败：$error');
      }
    } finally {
      if (revision == _sourceLoadRevision) _loadingSourcePath = null;
    }
  }

  Future<void> _pickSource() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    // 先标记请求路径，避免 VM notify 与显式加载同时触发两次大图解码。
    _loadingSourcePath = file.path;
    _generation.setSourceImagePath(file.path);
    await _loadImage(file.path);
  }

  void _saveHistory() {
    _undo.add(List.of(_strokes));
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  List<InpaintStroke> get _maskStrokes => _strokes
      .where((stroke) => stroke.target == InpaintPaintTarget.mask)
      .toList(growable: false);

  void _saveMaskHistory() {
    _maskUndo.add(_maskStrokes);
    if (_maskUndo.length > 80) _maskUndo.removeAt(0);
    _maskRedo.clear();
  }

  List<InpaintStroke> get _allStrokes {
    final draft = _draft;
    if (draft == null) return List.of(_strokes);
    return [..._strokes, _strokeWithPoints(draft, _draftPoints)];
  }

  InpaintStroke _strokeWithPoints(
    InpaintStroke stroke,
    List<InpaintPoint> points,
  ) =>
      InpaintStroke(
        target: stroke.target,
        mode: stroke.mode,
        type: stroke.type,
        size: stroke.size,
        color: stroke.color,
        opacity: stroke.opacity,
        square: stroke.square,
        points: List<InpaintPoint>.unmodifiable(points),
        start: stroke.start,
        rectangle: stroke.rectangle,
      );

  void _rebuildMaskPath() {
    _maskPath =
        InpaintCanvasPainter.mergeMaskStrokes(_maskStrokes) ?? ui.Path();
  }

  void _clearActiveStrokePreview() {
    _draft = null;
    _draftPoints.clear();
    _previewMaskPath.value = null;
  }

  void _clearAllStrokes() {
    if (_busy) return;
    if (_strokes.isEmpty) return;
    _saveHistory();
    if (_maskStrokes.isNotEmpty) _saveMaskHistory();
    setState(() {
      _strokes.clear();
      _maskPath = ui.Path();
      _clearActiveStrokePreview();
    });
  }

  void _clearCurrentLayer() {
    if (_busy || !_strokes.any((stroke) => stroke.target == _target)) return;
    _saveHistory();
    if (_target == InpaintPaintTarget.mask) _saveMaskHistory();
    setState(() {
      _clearActiveStrokePreview();
      _strokes.removeWhere((stroke) => stroke.target == _target);
      if (_target == InpaintPaintTarget.mask) _maskPath = ui.Path();
    });
  }

  void _undoStroke() {
    if (_undo.isEmpty || _busy) return;
    _redo.add(List.of(_strokes));
    final previous = _undo.removeLast();
    final currentMasks = _maskStrokes;
    setState(() {
      _strokes
        ..clear()
        ..addAll(previous);
      _clearActiveStrokePreview();
      _rebuildMaskPath();
    });
    _recordGlobalMaskChange(currentMasks, _maskStrokes, undo: true);
  }

  void _redoStroke() {
    if (_redo.isEmpty || _busy) return;
    _undo.add(List.of(_strokes));
    final next = _redo.removeLast();
    final currentMasks = _maskStrokes;
    setState(() {
      _strokes
        ..clear()
        ..addAll(next);
      _clearActiveStrokePreview();
      _rebuildMaskPath();
    });
    _recordGlobalMaskChange(currentMasks, _maskStrokes, undo: false);
  }

  void _recordGlobalMaskChange(
    List<InpaintStroke> before,
    List<InpaintStroke> after, {
    required bool undo,
  }) {
    if (listEquals(before, after)) return;
    final from = undo ? _maskRedo : _maskUndo;
    final to = undo ? _maskUndo : _maskRedo;
    from.add(before);
    if (from.length > 80) from.removeAt(0);
    to.add(after);
    if (to.length > 80) to.removeAt(0);
  }

  void _undoMask() => _applyMaskHistory(_maskUndo, _maskRedo);

  void _redoMask() => _applyMaskHistory(_maskRedo, _maskUndo);

  void _applyMaskHistory(
    List<List<InpaintStroke>> from,
    List<List<InpaintStroke>> to,
  ) {
    if (_busy || from.isEmpty) return;
    final current = _maskStrokes;
    var target = from.removeLast();
    while (from.isNotEmpty && listEquals(current, target)) {
      target = from.removeLast();
    }
    if (listEquals(current, target)) return;
    to.add(current);
    if (to.length > 80) to.removeAt(0);
    setState(() {
      _strokes
        ..removeWhere((stroke) => stroke.target == InpaintPaintTarget.mask)
        ..addAll(target);
      _clearActiveStrokePreview();
      _rebuildMaskPath();
    });
  }

  Offset _screenToWorld(Offset point) => Offset(
        (point.dx - _transform.offsetX) / _transform.scale,
        (point.dy - _transform.offsetY) / _transform.scale,
      );

  double get _boxAspect {
    final resolution = _resolution;
    return resolution.$1 / resolution.$2;
  }

  void _panScene(Offset delta) {
    setState(() {
      _transform = _transform.copyWith(
        offsetX: _transform.offsetX + delta.dx,
        offsetY: _transform.offsetY + delta.dy,
      );
    });
  }

  void _zoomScene(double factor, Offset focalPoint) {
    final before = _screenToWorld(focalPoint);
    final scale = (_transform.scale * factor).clamp(0.05, 12.0).toDouble();
    setState(() {
      _transform = InpaintTransform(
        scale: scale,
        offsetX: focalPoint.dx - before.dx * scale,
        offsetY: focalPoint.dy - before.dy * scale,
      );
    });
  }

  /// 输出框双指缩放：以捏合中心为锚点等比缩放，允许框独立移出源图。
  void _zoomBox(double factor, Offset anchor) {
    final box = _box;
    if (box == null) return;
    final width = (box.width * factor).clamp(_boxMinSize, 8192.0).toDouble();
    var height = width / _boxAspect;
    final centerX = anchor.dx + (box.x + box.width / 2 - anchor.dx) * factor;
    final centerY = anchor.dy + (box.y + box.height / 2 - anchor.dy) * factor;
    setState(() => _box = InpaintBox(
          x: centerX - width / 2,
          y: centerY - height / 2,
          width: width,
          height: height,
        ));
  }

  /// 整体模式下源图与输出框围绕同一锚点缩放，保持相对位置。
  void _zoomGlobal(double factor, Offset anchor) {
    final before = _screenToWorld(anchor);
    final scale = (_transform.scale * factor).clamp(0.05, 12.0).toDouble();
    final box = _box;
    InpaintBox? nextBox;
    if (box != null) {
      final width = (box.width * factor).clamp(_boxMinSize, 8192.0).toDouble();
      final height = width / _boxAspect;
      final centerX = anchor.dx + (box.x + box.width / 2 - anchor.dx) * factor;
      final centerY = anchor.dy + (box.y + box.height / 2 - anchor.dy) * factor;
      nextBox = InpaintBox(
        x: centerX - width / 2,
        y: centerY - height / 2,
        width: width,
        height: height,
      );
    }
    setState(() {
      _transform = InpaintTransform(
        scale: scale,
        offsetX: anchor.dx - before.dx * scale,
        offsetY: anchor.dy - before.dy * scale,
      );
      if (nextBox != null) _box = nextBox;
    });
  }

  /// 整体模式下源图与输出框同步平移。
  void _moveGlobal(Offset delta) {
    final box = _box;
    setState(() {
      _transform = _transform.copyWith(
        offsetX: _transform.offsetX + delta.dx,
        offsetY: _transform.offsetY + delta.dy,
      );
      if (box != null) _box = box.translate(delta.dx, delta.dy);
    });
  }

  /// 移动输出框：允许框脱离源图，NovelAI 会将外侧区域作为待生成内容。
  void _moveBox(Offset delta) {
    final box = _box;
    if (box == null) return;
    setState(() => _box = box.translate(delta.dx, delta.dy));
  }

  void _fitStageToContent() {
    if (_sourceWidth <= 0 || _stageSize == Size.zero) return;
    final fitScale = _fitScale(_stageSize, _sourceWidth, _sourceHeight);
    _transform = InpaintTransform(
      scale: fitScale,
      offsetX: (_stageSize.width - _sourceWidth * fitScale) / 2,
      offsetY: (_stageSize.height - _sourceHeight * fitScale) / 2,
    );
    // 初始选择框：按输出分辨率 × 适应缩放，居中于图片。
    final resolution = _resolution;
    final width = resolution.$1 * fitScale;
    final height = resolution.$2 * fitScale;
    final centerX = _transform.offsetX + _sourceWidth * fitScale / 2;
    final centerY = _transform.offsetY + _sourceHeight * fitScale / 2;
    setState(() {
      _box = InpaintBox(
        x: centerX - width / 2,
        y: centerY - height / 2,
        width: width,
        height: height,
      );
    });
  }

  void _resetFrame() {
    if (_sourceWidth <= 0 || _sourceHeight <= 0) return;
    final resolution = _resolution;
    final width = resolution.$1 * _transform.scale;
    final height = resolution.$2 * _transform.scale;
    final centerX = _transform.offsetX + _sourceWidth * _transform.scale / 2;
    final centerY = _transform.offsetY + _sourceHeight * _transform.scale / 2;
    setState(() {
      _box = InpaintBox(
        x: centerX - width / 2,
        y: centerY - height / 2,
        width: width,
        height: height,
      );
    });
  }

  void _zoomWorkspace(double factor) {
    final anchor = _uiMode == InpaintUiMode.frame
        ? Offset(_box?.x ?? _stageSize.width / 2,
                _box?.y ?? _stageSize.height / 2) +
            Offset((_box?.width ?? 0) / 2, (_box?.height ?? 0) / 2)
        : Offset(_stageSize.width / 2, _stageSize.height / 2);
    switch (_uiMode) {
      case InpaintUiMode.view:
        _zoomGlobal(factor, anchor);
      case InpaintUiMode.frame:
        _zoomBox(factor, anchor);
      case InpaintUiMode.image:
      case InpaintUiMode.brush:
      case InpaintUiMode.erase:
        _zoomScene(factor, anchor);
    }
  }

  /// 切换分辨率后调整选择框：保持中心与宽度，重算高度。
  void _syncBoxToResolution() {
    final box = _box;
    if (box == null) return;
    final width = box.width;
    final height = width / _boxAspect;
    final centerX = box.x + box.width / 2;
    final centerY = box.y + box.height / 2;
    setState(() => _box = InpaintBox(
          x: centerX - width / 2,
          y: centerY - height / 2,
          width: width,
          height: height,
        ));
  }

  /// 在屏幕上将输出框边缘吸附到源图边缘；输出框可以独立移出源图。
  InpaintBox _snapBox(InpaintBox box) {
    final bounds = _imageScreenBounds;
    if (bounds == null) return box;
    final dx = _nearestSnap([
      bounds.left - box.x,
      bounds.right - (box.x + box.width),
      bounds.left - (box.x + box.width),
      bounds.right - box.x,
    ]);
    final dy = _nearestSnap([
      bounds.top - box.y,
      bounds.bottom - (box.y + box.height),
      bounds.top - (box.y + box.height),
      bounds.bottom - box.y,
    ]);
    return box.translate(dx ?? 0, dy ?? 0);
  }

  Rect? get _imageScreenBounds {
    if (_sourceWidth <= 0 || _sourceHeight <= 0) return null;
    return Rect.fromLTWH(
      _transform.offsetX,
      _transform.offsetY,
      _sourceWidth * _transform.scale,
      _sourceHeight * _transform.scale,
    );
  }

  double? _nearestSnap(List<double> offsets) {
    final eligible = offsets.where((value) => value.abs() <= _snapTolerancePx);
    if (eligible.isEmpty) return null;
    return eligible.reduce((a, b) => a.abs() <= b.abs() ? a : b);
  }

  void _snapImageToFrame() {
    final box = _box;
    final bounds = _imageScreenBounds;
    if (box == null || bounds == null) return;
    final dx = _nearestSnap([
      box.x - bounds.left,
      box.x + box.width - bounds.right,
      box.x - bounds.right,
      box.x + box.width - bounds.left,
    ]);
    final dy = _nearestSnap([
      box.y - bounds.top,
      box.y + box.height - bounds.bottom,
      box.y - bounds.bottom,
      box.y + box.height - bounds.top,
    ]);
    if (dx == null && dy == null) return;
    _transform = _transform.copyWith(
      offsetX: _transform.offsetX + (dx ?? 0),
      offsetY: _transform.offsetY + (dy ?? 0),
    );
  }

  void _startStroke(Offset point) {
    if (_sourceWidth <= 0 || _busy) return;
    final world = _screenToWorld(point);
    final firstPoint = InpaintPoint(world.dx, world.dy);
    _saveHistory();
    final draft = InpaintStroke(
      target: _target,
      mode: _uiMode == InpaintUiMode.erase
          ? InpaintStrokeMode.erase
          : InpaintStrokeMode.paint,
      type: InpaintStrokeType.path,
      size: _brushSize,
      square: _squareBrush,
      points: [firstPoint],
      start: firstPoint,
    );
    _draft = draft;
    _draftPoints
      ..clear()
      ..add(firstPoint);
    _previewMaskPath.value = null;
    if (draft.target == InpaintPaintTarget.mask) {
      _previewMaskPath.value = InpaintCanvasPainter.appendMaskPreviewPoint(
        ui.Path.from(_maskPath),
        draft,
        firstPoint,
      );
    }
  }

  void _updateStroke(Offset point) {
    final draft = _draft;
    if (draft == null) return;
    final world = _screenToWorld(point);
    final previous = _draftPoints.isEmpty ? null : _draftPoints.last;
    final next = InpaintPoint(world.dx, world.dy);
    _draftPoints.add(next);

    if (draft.target == InpaintPaintTarget.mask) {
      _previewMaskPath.value = InpaintCanvasPainter.appendMaskPreviewPoint(
        _previewMaskPath.value!,
        draft,
        next,
        previous: previous,
      );
      return;
    }

    setState(() {
      _draft = _strokeWithPoints(draft, _draftPoints);
    });
  }

  void _finishStroke() {
    final draft = _draft;
    if (draft == null) return;
    if (draft.type == InpaintStrokeType.path && _draftPoints.isEmpty) return;
    final completed = _strokeWithPoints(draft, _draftPoints);
    if (draft.target == InpaintPaintTarget.mask) {
      _saveMaskHistory();
      // The live preview is already the canonical result of every input
      // segment; reuse it instead of rebuilding the whole stroke on pointer-up.
      _maskPath = _previewMaskPath.value ?? ui.Path.from(_maskPath);
    }
    setState(() {
      _strokes.add(completed);
      _draft = null;
      _draftPoints.clear();
      _previewMaskPath.value = null;
    });
  }

  // ---- 手势 ----

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      if (_sourceWidth <= 0 || _busy) {
        _gesture = _GestureKind.none;
      } else if (_uiMode == InpaintUiMode.brush ||
          _uiMode == InpaintUiMode.erase) {
        _gesture = _GestureKind.draw;
        _startStroke(event.localPosition);
      } else {
        switch (_uiMode) {
          case InpaintUiMode.view:
            _gesture = _GestureKind.moveGlobal;
          case InpaintUiMode.frame:
            _gesture = _GestureKind.moveBox;
          case InpaintUiMode.image:
            _gesture = _GestureKind.panScene;
          case InpaintUiMode.brush:
          case InpaintUiMode.erase:
            _gesture = _GestureKind.draw;
        }
      }
    } else if (_pointers.length == 2) {
      _clearActiveStrokePreview();
      _gesture = _GestureKind.none;
      final points = _pointers.values.toList();
      _lastGestureCenter =
          points.reduce((a, b) => a + b) / points.length.toDouble();
      _lastGestureDistance = (points[0] - points[1]).distance;
    }
    // 通知生成页锁定页面滚动（工作区手势激活中）。
    InpaintWorkspaceCard.gestureActive.value = true;
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer];
    _pointers[event.pointer] = event.localPosition;
    if (previous == null) return;
    if (_pointers.length > 1) {
      if (_pointers.length == 2) {
        final points = _pointers.values.toList();
        final center =
            points.reduce((a, b) => a + b) / points.length.toDouble();
        // 双指同向滑动遵循当前工具的移动目标。
        final oldCenter = _lastGestureCenter ?? center;
        final panDelta = center - oldCenter;
        switch (_uiMode) {
          case InpaintUiMode.view:
            _moveGlobal(panDelta);
          case InpaintUiMode.frame:
            _moveBox(panDelta);
          case InpaintUiMode.image:
          case InpaintUiMode.brush:
          case InpaintUiMode.erase:
            _panScene(panDelta);
        }
        // 双指张合：缩放。
        final distance = (points[0] - points[1]).distance;
        final oldDistance = _lastGestureDistance;
        if (oldDistance != null && oldDistance > 0 && distance > 0) {
          final factor = distance / oldDistance;
          switch (_uiMode) {
            case InpaintUiMode.view:
              _zoomGlobal(factor, center);
            case InpaintUiMode.frame:
              _zoomBox(factor, center);
            case InpaintUiMode.image:
            case InpaintUiMode.brush:
            case InpaintUiMode.erase:
              _zoomScene(factor, center);
          }
        }
        _lastGestureDistance = distance;
        _lastGestureCenter = center;
      }
      return;
    }
    switch (_gesture) {
      case _GestureKind.draw:
        _updateStroke(event.localPosition);
      case _GestureKind.moveBox:
        _moveBox(event.delta);
      case _GestureKind.panScene:
        _panScene(event.delta);
      case _GestureKind.moveGlobal:
        _moveGlobal(event.delta);
      case _GestureKind.none:
        break;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      if (_gesture == _GestureKind.draw) _finishStroke();
      if (_uiMode == InpaintUiMode.frame && _box != null) {
        setState(() => _box = _snapBox(_box!));
      } else if (_uiMode == InpaintUiMode.image) {
        _snapImageToFrame();
      }
      _gesture = _GestureKind.none;
      _lastGestureCenter = null;
      _lastGestureDistance = null;
      // 手势结束，解除页面滚动锁定。
      InpaintWorkspaceCard.gestureActive.value = false;
    }
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _clearActiveStrokePreview();
      _gesture = _GestureKind.none;
      _lastGestureCenter = null;
      _lastGestureDistance = null;
      InpaintWorkspaceCard.gestureActive.value = false;
    }
    setState(() {});
  }

  // ---- 生成候选，确认后才加入结果图层 ----
  // 触发入口是页面底部的悬浮生成按钮（通过 VM 的钩子调用本方法）。

  /// 页面底部生成按钮触发：在工作区内完成本轮局部重绘生成。
  Future<bool> _prepareGeneration() async {
    final box = _box;
    final sourcePng = _sourcePngBytes;
    if (sourcePng == null ||
        _sourcePath == null ||
        box == null ||
        _busy ||
        _sourceWidth <= 0) {
      return false;
    }
    if (_generation.currentProvider != ImageProviderType.novelAi) {
      showFloatingToast(context, '局部重绘仅支持 NovelAI 渠道');
      return false;
    }
    _finishStroke();
    final total = _generation.batchCount.clamp(1, 30).toInt();
    final resolution = _resolution;
    final strokes = List<InpaintStroke>.of(_allStrokes);
    final expandPixels = _expandPixels;
    final featherPixels = _featherPixels;
    final prompt = _promptController.text;
    final negativePrompt = _negativeController.text;
    final strength = _inpaintStrength;
    final disabledOriginalImage = _disabledOriginalImage;
    final colorCorrect = _colorCorrect;
    final revision = 'workspace-${++_generationRevision}';
    var receivedCandidate = false;
    // 选择框（屏幕坐标）→ 图像世界坐标。
    final worldRect = InpaintViewport(
      x: (box.x - _transform.offsetX) / _transform.scale,
      y: (box.y - _transform.offsetY) / _transform.scale,
      width: box.width / _transform.scale,
      height: box.height / _transform.scale,
    );
    setState(() {
      _busy = true;
      _batchCompleted = 0;
      _batchTotal = total;
      _activeRevision = revision;
      _reviewOpen = false;
    });
    try {
      // 固定本轮模型、分辨率、提示词与采样选项，避免光栅化期间 UI/VM
      // 变化让同一批结果落入不同尺寸或使用不同提示词。
      final requestTemplates = List<GenerationTask>.generate(
        total,
        (_) => _generation.buildInpaintTask(
          sourcePath: _sourcePath!,
          maskPath: '',
          prompt: prompt,
          negativePrompt: negativePrompt,
          strength: strength,
          disabledOriginalImage: disabledOriginalImage,
          colorCorrect: colorCorrect,
        ),
        growable: false,
      );
      // 光栅化与 PNG 编码在后台 isolate 执行，避免大图阻塞主线程导致 ANR 闪退。
      final raster = await compute<_RasterizeInput, _RasterizeResult>(
        _rasterizeIsolate,
        _RasterizeInput(
          sourcePng: sourcePng,
          strokes: strokes,
          worldRect: worldRect,
          outputWidth: resolution.$1,
          outputHeight: resolution.$2,
          expandPixels: expandPixels,
          comparisonLayers: [
            for (final layer in _resultLayers.where((layer) => layer.visible))
              _CompositeLayerInput(
                await File(layer.imagePath).readAsBytes(),
                layer.worldRect,
              ),
          ],
        ),
      );
      final dir = await ImageUtils.getImageDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final basePath = '${dir.path}${Platform.pathSeparator}'
          'inpaint_${timestamp}_${revision}_base.png';
      final maskPath = '${dir.path}${Platform.pathSeparator}'
          'inpaint_${timestamp}_${revision}_mask.png';
      final beforePath = '${dir.path}${Platform.pathSeparator}'
          'inpaint_${timestamp}_${revision}_before.png';
      await File(basePath).writeAsBytes(raster.basePng, flush: true);
      await File(maskPath).writeAsBytes(raster.maskPng, flush: true);
      await File(beforePath)
          .writeAsBytes(raster.comparisonBasePng, flush: true);
      _sessionSourcePath = basePath;
      _sessionMaskPath = maskPath;
      for (var index = 0; index < total; index++) {
        if (_generation.isBatchCancelling) break;
        final task = requestTemplates[index].copyWith(
          sourceImagePath: basePath,
          maskImagePath: maskPath,
        );
        final completed = await _queue.enqueueTransientAndWait(task);
        if (!mounted || revision != _activeRevision) return false;
        if (completed.status == 'success') {
          final generatedPath = await _saveImage.saveTransient(completed);
          if (!mounted || revision != _activeRevision) return false;
          setState(() => _addingLayer = true);
          final candidateImages =
              await compute<_MaskLayerInput, _CandidateImages>(
            _maskLayerIsolate,
            _MaskLayerInput(
              basePng: raster.comparisonBasePng,
              maskPng: raster.maskPng,
              generatedPng: await File(generatedPath).readAsBytes(),
              featherPixels: featherPixels,
            ),
          );
          final dir = await ImageUtils.getImageDirectory();
          final layerPath = '${dir.path}${Platform.pathSeparator}'
              'inpaint_layer_${DateTime.now().millisecondsSinceEpoch}_'
              '${index + 1}.png';
          final comparisonPath = '${dir.path}${Platform.pathSeparator}'
              'inpaint_compare_${timestamp}_${revision}_${index + 1}.png';
          await File(layerPath)
              .writeAsBytes(candidateImages.layerPng, flush: true);
          await File(comparisonPath)
              .writeAsBytes(candidateImages.comparisonPng, flush: true);
          if (!mounted || revision != _activeRevision) return false;
          setState(() {
            if (!receivedCandidate) {
              _candidates.clear();
              receivedCandidate = true;
            }
            _candidates.add(_ReviewCandidate(
              InpaintCandidate(
                id: completed.taskId,
                imagePath: generatedPath,
                baseImagePath: basePath,
                workspaceImagePath: _sourcePath!,
                maskImagePath: maskPath,
                worldRect: worldRect,
                seed: completed.seed,
              ),
              layerPath,
              comparisonPath,
              beforePath,
              resolution.$1,
              resolution.$2,
            ));
            _selectedCandidateId = completed.taskId;
            _batchCompleted++;
            _addingLayer = false;
          });
        } else {
          showFloatingToast(context, completed.errorMessage ?? '重绘失败');
          break;
        }
      }
      return true;
    } catch (error) {
      if (mounted) showFloatingToast(context, '生成失败：$error');
      return false;
    } finally {
      if (mounted && revision == _activeRevision) {
        setState(() {
          _busy = false;
          _addingLayer = false;
          _reviewOpen = _candidates.isNotEmpty;
        });
      }
    }
  }

  _ReviewCandidate? get _selectedCandidate {
    for (final entry in _candidates) {
      if (entry.candidate.id == _selectedCandidateId) return entry;
    }
    return null;
  }

  bool _isApplied(_ReviewCandidate entry) =>
      _resultLayers.any((layer) => layer.id == entry.candidate.id);

  void _applySelectedCandidate() {
    final entry = _selectedCandidate;
    if (entry == null || _busy || _isApplied(entry)) return;
    final ids = _candidates.map((item) => item.candidate.id).toSet();
    final oldIndex =
        _resultLayers.indexWhere((layer) => ids.contains(layer.id));
    final name =
        oldIndex < 0 ? '重绘 ${++_layerSequence}' : _resultLayers[oldIndex].name;
    setState(() {
      // 同一批的候选只能有一个应用层；重新选择时替换该层。
      _resultLayers.removeWhere((layer) => ids.contains(layer.id));
      _resultLayers.insert(
        oldIndex < 0 ? _resultLayers.length : oldIndex,
        InpaintResultLayer(
          id: entry.candidate.id,
          name: name,
          imagePath: entry.layerPath,
          width: entry.width,
          height: entry.height,
          worldRect: entry.candidate.worldRect,
        ),
      );
      _reviewOpen = false;
      _showMask = false;
      _uiMode = InpaintUiMode.view;
    });
  }

  void _discardSelectedCandidate() {
    final entry = _selectedCandidate;
    if (entry == null || _busy || _isApplied(entry)) return;
    final index = _candidates.indexOf(entry);
    setState(() {
      _candidates.removeAt(index);
      _selectedCandidateId = _candidates.isEmpty
          ? null
          : _candidates[index.clamp(0, _candidates.length - 1)].candidate.id;
      if (_candidates.isEmpty) _reviewOpen = false;
    });
  }

  Future<void> _saveCompositeToGallery() async {
    final sourcePng = _sourcePngBytes;
    if (sourcePng == null || _addingLayer) return;
    try {
      final visibleLayers = _resultLayers.where((layer) => layer.visible);
      final input = _CompositeWorkspaceInput(
        sourcePng,
        List.of(_strokes),
        [
          for (final layer in visibleLayers)
            _CompositeLayerInput(
              await File(layer.imagePath).readAsBytes(),
              layer.worldRect,
            ),
        ],
      );
      final composite = await compute<_CompositeWorkspaceInput, Uint8List>(
        _composeWorkspaceIsolate,
        input,
      );
      final dir = await ImageUtils.getImageDirectory();
      final path = '${dir.path}${Platform.pathSeparator}'
          'inpaint_composite_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(composite, flush: true);
      final saved = await _saveImage.saveToGallery(path);
      if (mounted) {
        showFloatingToast(
          context,
          saved ? '合成图片已保存到相册' : '保存失败，请检查相册权限',
        );
      }
    } catch (error) {
      if (mounted) showFloatingToast(context, '合成保存失败：$error');
    }
  }

  void _toggleResultLayer(InpaintResultLayer layer) {
    setState(() {
      final index = _resultLayers.indexWhere((entry) => entry.id == layer.id);
      if (index >= 0) {
        _resultLayers[index] = layer.copyWith(visible: !layer.visible);
      }
    });
  }

  void _removeResultLayer(InpaintResultLayer layer) {
    setState(() => _resultLayers.removeWhere((entry) => entry.id == layer.id));
  }

  (int, int) get _resolution {
    final parts = _generation.selectedResolution.split('x');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 832, int.tryParse(parts[1]) ?? 1216);
    }
    return (832, 1216);
  }

  Future<void> _chooseResolution() async {
    final resolutions = _generation.availableResolutions;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final value in resolutions)
              ListTile(
                title: Text(_generation.resolutionLabel(value)),
                trailing: value == _generation.selectedResolution
                    ? const Icon(CupertinoIcons.checkmark)
                    : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected == _generation.selectedResolution) return;
    await _generation.updateSelectedResolution(selected);
    if (mounted) _syncBoxToResolution();
  }

  double _fitScale(Size size, int width, int height) {
    if (size.width <= 0 || size.height <= 0) return 1;
    return (size.width * 0.9 / width)
        .clamp(0.05, size.height * 0.9 / height)
        .toDouble();
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    // 遮罩预览开启时调度后台生成（签名防抖）。
    if (_showMask) _scheduleMaskPreview();
    return FrostedSurface(
      radius: 18,
      child: Column(children: [
        _buildHeader(colors),
        _buildStage(),
        if (_candidates.isNotEmpty) _buildCandidatePanel(colors),
        _buildToolbar(colors),
        _buildPromptPanel(colors),
      ]),
    );
  }

  /// 画布上方只保留紧凑的图片状态、换图和输出分辨率入口。
  Widget _buildHeader(ColorScheme colors) {
    return Padding(
      key: const ValueKey('inpaint-workspace-header'),
      padding: const EdgeInsets.fromLTRB(10, 2, 8, 4),
      child: Row(
        children: [
          const Icon(CupertinoIcons.photo, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _sourcePath == null
                  ? '选择原图'
                  : '${_sourceWidth} × ${_sourceHeight} px',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
          IconButton(
            tooltip: '更换图片',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : _pickSource,
            icon: const Icon(CupertinoIcons.photo_on_rectangle, size: 18),
          ),
          _resolutionButton(colors),
        ],
      ),
    );
  }

  /// 正负提示词并列提供独立编辑区；参数仍由同一面板展开。
  Widget _buildPromptPanel(ColorScheme colors) {
    return Column(
      key: const ValueKey('inpaint-prompt-panel'),
      children: [
        Material(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
          child: InkWell(
            onTap: () => setState(() => _promptExpanded = !_promptExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Icon(CupertinoIcons.textformat_abc,
                    size: 15, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '重绘提示词',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Icon(
                  _promptExpanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
              ]),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _promptExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(children: [
              _buildPromptField(
                controller: _promptController,
                label: '正向提示词',
                hint: '描述希望在框选区域生成的内容',
                onChanged: (value) => _generation.updateInpaintPrompt(value),
              ),
              const SizedBox(height: 8),
              _buildPromptField(
                controller: _negativeController,
                label: '负向提示词',
                hint: '描述希望排除的内容',
                onChanged: (value) =>
                    _generation.updateInpaintNegativePrompt(value),
              ),
              if (_paramsExpanded) ...[
                const SizedBox(height: 6),
                _buildParams(),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _paramsExpanded = !_paramsExpanded),
                  icon: Icon(
                    _paramsExpanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.slider_horizontal_3,
                    size: 14,
                  ),
                  label: Text(
                    _paramsExpanded ? '收起生成参数' : '生成参数',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildPromptField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      minLines: 3,
      maxLines: 6,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }

  Widget _resolutionButton(ColorScheme colors) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.45)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: _busy ? null : _chooseResolution,
      icon: Icon(CupertinoIcons.crop, size: 14, color: colors.primary),
      label: Text(
        _generation.selectedResolution,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }

  Widget _buildStage() {
    final colors = Theme.of(context).colorScheme;
    final sourcePath = _sourcePath;
    final sourceWidth = _sourceWidth;
    final review = _reviewOpen ? _selectedCandidate : null;
    final previewCurrent = !_busy &&
        _draft == null &&
        _maskPreviewSignature == _maskPreviewCurrentSignature &&
        _maskPreviewBytes != null;
    if (sourcePath == null || sourceWidth <= 0) {
      return AspectRatio(
        key: const ValueKey('inpaint-workspace-stage'),
        aspectRatio: 0.86,
        child: GestureDetector(
          onTap: _pickSource,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
              color: colors.surfaceContainerHighest.withValues(alpha: 0.2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.photo,
                  size: 44,
                  color: colors.outline,
                ),
                const SizedBox(height: 10),
                Text(
                  '点击选择图片',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return AspectRatio(
      key: const ValueKey('inpaint-workspace-stage'),
      aspectRatio: 0.86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: LayoutBuilder(builder: (context, constraints) {
            final stageSize = constraints.biggest;
            _stageSize = stageSize;
            final needsInit = _box == null &&
                _transform.scale == 1 &&
                _transform.offsetX == 0 &&
                _transform.offsetY == 0;
            if (needsInit) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fitStageToContent();
              });
            }
            return GestureDetector(
              // 吞掉拖动/捏合手势，避免外泄给外层 ListView 导致页面滚动。
              // dragStartBehavior 设为 down：手指按下即参与竞技并优先接管，
              // 确保涂抹遮罩/拖动方框时页面不跟着滚动。
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: (_) {},
              onPanUpdate: (_) {},
              onPanEnd: (_) {},
              onPanCancel: () {},
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: review == null ? _onPointerDown : null,
                onPointerMove: review == null ? _onPointerMove : null,
                onPointerUp: review == null ? _onPointerUp : null,
                onPointerCancel: review == null ? _onPointerCancel : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: _transform.offsetX,
                      top: _transform.offsetY,
                      width: _sourceWidth * _transform.scale,
                      height: _sourceHeight * _transform.scale,
                      child: Image.file(File(sourcePath), fit: BoxFit.fill),
                    ),
                    CustomPaint(
                      painter: InpaintCanvasPainter(
                        transform: _transform,
                        strokes: [
                          ..._strokes.where((stroke) =>
                              stroke.target == InpaintPaintTarget.image),
                          if (_draft?.target == InpaintPaintTarget.image)
                            _strokeWithPoints(_draft!, _draftPoints),
                        ],
                        showMask: false,
                      ),
                    ),
                    for (final layer
                        in _resultLayers.where((item) => item.visible))
                      Positioned(
                        left: _transform.offsetX +
                            layer.worldRect.x * _transform.scale,
                        top: _transform.offsetY +
                            layer.worldRect.y * _transform.scale,
                        width: layer.worldRect.width * _transform.scale,
                        height: layer.worldRect.height * _transform.scale,
                        child: IgnorePointer(
                          child: Image.file(File(layer.imagePath),
                              fit: BoxFit.fill),
                        ),
                      ),
                    if (_displayBox != null) _buildBoxDimmer(),
                    RepaintBoundary(
                      key: const ValueKey('inpaint-mask-repaint-boundary'),
                      child: CustomPaint(
                        key: const ValueKey('inpaint-live-mask'),
                        painter: InpaintCanvasPainter(
                          transform: _transform,
                          strokes: [
                            ..._maskStrokes,
                            if (_draft?.target == InpaintPaintTarget.mask)
                              _strokeWithPoints(_draft!, _draftPoints),
                          ],
                          showMask:
                              _showMask && review == null && !previewCurrent,
                          maskPath: _maskPath,
                          previewMaskPathListenable: _previewMaskPath,
                        ),
                      ),
                    ),
                    if (_showMask &&
                        _box != null &&
                        review == null &&
                        previewCurrent)
                      _FinalMaskOverlay(
                        transform: _transform,
                        box: _box!,
                        bytes: _maskPreviewBytes!,
                      ),
                    if (review != null)
                      Positioned.fromRect(
                        rect: _displayBox!.rect,
                        child: InpaintComparison(
                          key: ValueKey('inpaint-compare-$_activeRevision'),
                          beforePath: review.beforePath,
                          afterPath: review.comparisonPath,
                          onGestureActive: (active) =>
                              InpaintWorkspaceCard.gestureActive.value = active,
                        ),
                      ),
                    if (_displayBox != null) _buildBoxFrame(),
                    if (_busy) _buildBusyOverlay(),
                    if (_officialUpscaling)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black38,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 8),
                                  Text(
                                    _generation.officialUpscaleStatus ??
                                        '官方超分中…',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  InpaintBox? get _displayBox {
    final review = _reviewOpen ? _selectedCandidate : null;
    if (review == null) return _box;
    final rect = review.candidate.worldRect;
    return InpaintBox(
      x: _transform.offsetX + rect.x * _transform.scale,
      y: _transform.offsetY + rect.y * _transform.scale,
      width: rect.width * _transform.scale,
      height: rect.height * _transform.scale,
    );
  }

  /// 框外暗幕。
  Widget _buildBoxDimmer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _FrameDimmerPainter(_displayBox!.rect)),
      ),
    );
  }

  /// 选择框边框与分辨率标签。
  Widget _buildBoxFrame() {
    final box = _displayBox!;
    final review = _reviewOpen ? _selectedCandidate : null;
    final colors = Theme.of(context).colorScheme;
    const borderColor = Color(0xffffd27b);
    return Positioned.fromRect(
      rect: box.rect,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(children: [
            if (review == null)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_resolution.$1} × ${_resolution.$2}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
            if (review != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    child: Text(
                      '${review.width} × ${review.height}'
                      '${review.candidate.seed == null ? '' : ' · Seed ${review.candidate.seed}'}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildBusyOverlay() {
    final colors = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 10),
                Text(
                    _addingLayer
                        ? '准备候选…'
                        : '生成中 $_batchCompleted/$_batchTotal',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 工作区下边工具栏：五种操作模式、笔刷参数、历史与图层管理。
  Widget _buildToolbar(ColorScheme colors) {
    if (_reviewOpen) {
      return _resultLayers.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: _buildResultLayers(colors),
            );
    }
    final isDrawing =
        _uiMode == InpaintUiMode.brush || _uiMode == InpaintUiMode.erase;
    return Padding(
      key: const ValueKey('inpaint-workspace-toolbar'),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolstrip(colors),
          _buildToolContext(colors),
          if (isDrawing) _buildBrushControls(colors),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  tooltip: '撤销笔迹',
                  visualDensity: VisualDensity.compact,
                  onPressed: _undo.isEmpty || _busy ? null : _undoStroke,
                  icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 18),
                ),
                IconButton(
                  tooltip: '重做笔迹',
                  visualDensity: VisualDensity.compact,
                  onPressed: _redo.isEmpty || _busy ? null : _redoStroke,
                  icon: const Icon(CupertinoIcons.arrow_uturn_right, size: 18),
                ),
                IconButton(
                  tooltip: '撤销蒙版',
                  visualDensity: VisualDensity.compact,
                  onPressed: _maskUndo.isEmpty || _busy ? null : _undoMask,
                  icon: const Icon(Icons.undo, size: 19),
                ),
                IconButton(
                  tooltip: '重做蒙版',
                  visualDensity: VisualDensity.compact,
                  onPressed: _maskRedo.isEmpty || _busy ? null : _redoMask,
                  icon: const Icon(Icons.redo, size: 19),
                ),
                IconButton(
                  tooltip: _showMask ? '隐藏蒙版' : '显示蒙版',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showMask = !_showMask),
                  icon: Icon(
                    _showMask ? CupertinoIcons.eye_fill : CupertinoIcons.eye,
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip:
                      _target == InpaintPaintTarget.mask ? '清空蒙版' : '清空图像笔迹',
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : _clearCurrentLayer,
                  icon: const Icon(CupertinoIcons.trash, size: 18),
                ),
                _cornerMenuButton(colors),
                const SizedBox(width: 4),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _sourcePath == null || _busy || _addingLayer
                      ? null
                      : _saveCompositeToGallery,
                  icon: const Icon(CupertinoIcons.photo_on_rectangle, size: 15),
                  label: const Text('保存合成', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          if (_resultLayers.isNotEmpty) _buildResultLayers(colors),
        ],
      ),
    );
  }

  Widget _buildToolContext(ColorScheme colors) {
    final hint = switch (_uiMode) {
      InpaintUiMode.view => '整体平移 · 双指缩放',
      InpaintUiMode.image => '移动图像 · 靠近输出框边缘时吸附',
      InpaintUiMode.frame => '移动输出框 · 可移出原图 · 双指缩放',
      InpaintUiMode.brush => '绘制笔迹 · 双指移动与缩放原图',
      InpaintUiMode.erase => '擦除当前绘制图层',
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
        ),
        IconButton(
          tooltip: '缩小',
          visualDensity: VisualDensity.compact,
          onPressed: _sourcePath == null || _busy
              ? null
              : () => _zoomWorkspace(1 / 1.2),
          icon: const Icon(Icons.remove, size: 18),
        ),
        Text(
          (_transform.scale * 100).round().toString() + '%',
          style: const TextStyle(fontSize: 10),
        ),
        IconButton(
          tooltip: '放大',
          visualDensity: VisualDensity.compact,
          onPressed:
              _sourcePath == null || _busy ? null : () => _zoomWorkspace(1.2),
          icon: const Icon(Icons.add, size: 18),
        ),
        if (_uiMode == InpaintUiMode.frame)
          TextButton(
            onPressed: _busy ? null : _resetFrame,
            child: const Text('重置框', style: TextStyle(fontSize: 10)),
          )
        else
          IconButton(
            tooltip: '适应窗口',
            visualDensity: VisualDensity.compact,
            onPressed: _sourcePath == null || _busy ? null : _fitStageToContent,
            icon: const Icon(Icons.fit_screen, size: 17),
          ),
      ],
    );
  }

  Widget _buildToolstrip(ColorScheme colors) {
    const modes = [
      (InpaintUiMode.view, '整体', Icons.open_with),
      (InpaintUiMode.image, '图像', Icons.image_outlined),
      (InpaintUiMode.frame, '输出框', Icons.crop_free),
      (InpaintUiMode.brush, '画笔', Icons.brush_outlined),
      (InpaintUiMode.erase, '橡皮', Icons.auto_fix_off),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final mode in modes)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: _busy
                    ? null
                    : () => setState(() {
                          _uiMode = mode.$1;
                          if (mode.$1 == InpaintUiMode.brush ||
                              mode.$1 == InpaintUiMode.erase) {
                            _showMask = true;
                          }
                        }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                  decoration: BoxDecoration(
                    color: _uiMode == mode.$1
                        ? (mode.$1 == InpaintUiMode.erase
                            ? colors.error.withValues(alpha: 0.16)
                            : colors.primary.withValues(alpha: 0.16))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        mode.$3,
                        size: 18,
                        color: _uiMode == mode.$1
                            ? (mode.$1 == InpaintUiMode.erase
                                ? colors.error
                                : colors.primary)
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        mode.$2,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: _uiMode == mode.$1
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: _uiMode == mode.$1
                              ? (mode.$1 == InpaintUiMode.erase
                                  ? colors.error
                                  : colors.primary)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCandidatePanel(ColorScheme colors) {
    final selected = _selectedCandidate;
    if (selected == null) return const SizedBox.shrink();
    final applied = _isApplied(selected);
    return Padding(
      key: const ValueKey('inpaint-candidate-panel'),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '候选结果 ${_candidates.indexOf(selected) + 1} / ${_candidates.length}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() => _reviewOpen = !_reviewOpen),
                icon: Icon(
                  _reviewOpen ? Icons.edit_outlined : Icons.compare,
                  size: 16,
                ),
                label: Text(_reviewOpen ? '回到编辑' : '滑动对比'),
              ),
            ],
          ),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _candidates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final entry = _candidates[index];
                final active = entry.candidate.id == _selectedCandidateId;
                return Semantics(
                  button: true,
                  selected: active,
                  label: '候选 ${index + 1}${_isApplied(entry) ? '，已应用' : ''}',
                  child: InkWell(
                    key: ValueKey('inpaint-candidate-$index'),
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _selectedCandidateId = entry.candidate.id;
                              _reviewOpen = true;
                            }),
                    borderRadius: BorderRadius.circular(9),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 60,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color:
                              active ? colors.primary : colors.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(entry.comparisonPath),
                                fit: BoxFit.cover),
                            if (_isApplied(entry))
                              Align(
                                alignment: Alignment.bottomRight,
                                child: ColoredBox(
                                  color: colors.primary,
                                  child: Icon(Icons.check,
                                      size: 16, color: colors.onPrimary),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                key: const ValueKey('inpaint-discard-candidate'),
                onPressed: _busy || applied ? null : _discardSelectedCandidate,
                child: const Text('丢弃'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('inpaint-apply-candidate'),
                  onPressed: _busy || applied ? null : _applySelectedCandidate,
                  icon: const Icon(Icons.check, size: 17),
                  label: Text(applied ? '已应用此结果' : '应用此结果'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrushControls(ColorScheme colors) {
    final isErase = _uiMode == InpaintUiMode.erase;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              Text(
                '绘制',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('蒙版'),
                selected: _target == InpaintPaintTarget.mask,
                visualDensity: VisualDensity.compact,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _target = InpaintPaintTarget.mask),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('图像'),
                selected: _target == InpaintPaintTarget.image,
                visualDensity: VisualDensity.compact,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _target = InpaintPaintTarget.image),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.circle, size: 13),
                label: const Text('圆形'),
                selected: !_squareBrush,
                visualDensity: VisualDensity.compact,
                onSelected:
                    _busy ? null : (_) => setState(() => _squareBrush = false),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                avatar: const Icon(Icons.grid_4x4, size: 13),
                label: const Text('方格'),
                selected: _squareBrush,
                visualDensity: VisualDensity.compact,
                onSelected:
                    _busy ? null : (_) => setState(() => _squareBrush = true),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                isErase ? '橡皮' : '笔刷',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              Expanded(
                child: Slider(
                  value: _brushSize.clamp(8.0, 160.0),
                  min: 8,
                  max: 160,
                  divisions: 38,
                  label: _brushSize.round().toString(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _brushSize = value),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  _brushSize.round().toString() + ' px',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultLayers(ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                '结果图层 ' + _resultLayers.length.toString(),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          for (final layer in _resultLayers.reversed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child:
                          Image.file(File(layer.imagePath), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(layer.name,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                        Text(
                          layer.width.toString() +
                              ' × ' +
                              layer.height.toString(),
                          style: TextStyle(
                              fontSize: 9, color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        layer.visible ? '隐藏' + layer.name : '显示' + layer.name,
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => _toggleResultLayer(layer),
                    icon: Icon(
                      layer.visible
                          ? CupertinoIcons.eye_fill
                          : CupertinoIcons.eye_slash,
                      size: 17,
                    ),
                  ),
                  IconButton(
                    tooltip: '移除' + layer.name,
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => _removeResultLayer(layer),
                    icon: const Icon(CupertinoIcons.trash, size: 17),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cornerMenuButton(ColorScheme colors) {
    return PopupMenuButton<String>(
      tooltip: '工作区菜单',
      padding: EdgeInsets.zero,
      icon: const Icon(CupertinoIcons.ellipsis_circle, size: 20),
      onSelected: _busy
          ? null
          : (value) {
              switch (value) {
                case 'fit':
                  _fitStageToContent();
                case 'clear_mask':
                  _clearAllStrokes();
                case 'pick':
                  _pickSource();
                case 'upscale_px':
                  _upscalePixels();
              }
            },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'fit',
          child: Row(children: [
            Icon(CupertinoIcons.fullscreen, size: 18),
            SizedBox(width: 8),
            Text('重置视图', style: TextStyle(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'clear_mask',
          enabled: _strokes.isNotEmpty && !_busy,
          child: Row(children: [
            Icon(CupertinoIcons.trash, size: 18, color: colors.error),
            const SizedBox(width: 8),
            Text('清空全部遮罩',
                style: TextStyle(
                    fontSize: 13,
                    color: _strokes.isNotEmpty ? colors.error : null)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'pick',
          enabled: !_busy,
          child: Row(children: [
            Icon(CupertinoIcons.photo, size: 18),
            SizedBox(width: 8),
            Text('导入图片', style: TextStyle(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'upscale_px',
          enabled: _sourcePath != null && !_busy,
          child: Row(children: [
            const Icon(CupertinoIcons.arrow_up_right_square, size: 18),
            const SizedBox(width: 8),
            Text('放大图片分辨率', style: TextStyle(fontSize: 13)),
          ]),
        ),
      ],
    );
  }

  Future<void> _upscalePixels() async {
    final path = _sourcePath;
    if (path == null || _busy) return;
    final scale = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(CupertinoIcons.arrow_up_right_square),
            title: const Text('等比例放大 2x'),
            onTap: () => Navigator.pop(context, 2),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.arrow_up_right_square),
            title: const Text('等比例放大 3x'),
            onTap: () => Navigator.pop(context, 3),
          ),
        ]),
      ),
    );
    if (scale == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // 后台 isolate 放大，避免大图阻塞主线程。
      final resizedPng = await compute<_ResizeImageInput, Uint8List>(
        _resizeImageIsolate,
        _ResizeImageInput(await File(path).readAsBytes(), scale),
      );
      final dir = await ImageUtils.getImageDirectory();
      final output = File(
          '${dir.path}${Platform.pathSeparator}inpaint_${DateTime.now().millisecondsSinceEpoch}_${scale}x.png');
      await output.writeAsBytes(resizedPng, flush: true);
      await _loadImage(output.path);
      if (mounted) showFloatingToast(context, '图片已等比例放大 ${scale}x');
    } catch (error) {
      if (mounted) showFloatingToast(context, '图片放大失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildParams() {
    return Column(children: [
      _paramSlider('扩展', _expandPixels.toDouble(), 0, 32,
          (v) => _expandPixels = v.round()),
      _paramSlider('羽化', _featherPixels.toDouble(), 0, 32,
          (v) => _featherPixels = v.round()),
      _paramSlider(
        '强度',
        _inpaintStrength,
        0.01,
        1,
        (v) {
          _inpaintStrength = v;
          _generation.updateInpaintStrength(v);
        },
        divisions: 99,
      ),
      Row(children: [
        Checkbox(
          visualDensity: VisualDensity.compact,
          value: _disabledOriginalImage,
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    _disabledOriginalImage = value ?? false;
                    _generation.updateInpaintOptions(
                        disabledOriginalImage: _disabledOriginalImage);
                  }),
        ),
        const Text('忽略原图', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 12),
        Checkbox(
          visualDensity: VisualDensity.compact,
          value: _colorCorrect,
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    _colorCorrect = value ?? true;
                    _generation.updateInpaintOptions(
                        colorCorrect: _colorCorrect);
                  }),
        ),
        const Text('色彩校正', style: TextStyle(fontSize: 12)),
      ]),
    ]);
  }

  Widget _paramSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
  }) {
    return Row(children: [
      SizedBox(
          width: 36,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey))),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: label == '强度'
              ? value.toStringAsFixed(2)
              : value.round().toString(),
          onChanged: _busy ? null : (v) => setState(() => onChanged(v)),
        ),
      ),
    ]);
  }

  /// 遮罩预览签名：框位置/尺寸/笔迹/参数任一变化即重新生成（防抖 250ms）。
  String get _maskPreviewCurrentSignature {
    final box = _box;
    final sourcePng = _sourcePngBytes;
    if (box == null || sourcePng == null) return '';
    return [
      _sourceLoadRevision,
      box.x,
      box.y,
      box.width,
      box.height,
      _transform.offsetX,
      _transform.offsetY,
      _transform.scale,
      _expandPixels,
      Object.hashAll(_allStrokes),
      _generation.selectedResolution,
    ].join('|');
  }

  void _scheduleMaskPreview() {
    if (!_showMask || _reviewOpen) return;
    final pendingSignature = _maskPreviewCurrentSignature;
    if (pendingSignature.isEmpty || pendingSignature == _maskPreviewKey) return;
    _maskPreviewDebounce?.cancel();
    _maskPreviewDebounce = Timer(const Duration(milliseconds: 250), () async {
      final sourcePng = _sourcePngBytes;
      final box = _box;
      if (sourcePng == null || box == null || !mounted) return;
      final signature = _maskPreviewCurrentSignature;
      final worldRect = InpaintViewport(
        x: (box.x - _transform.offsetX) / _transform.scale,
        y: (box.y - _transform.offsetY) / _transform.scale,
        width: box.width / _transform.scale,
        height: box.height / _transform.scale,
      );
      _maskPreviewKey = signature;
      try {
        final bytes = await compute<_MaskPreviewInput, Uint8List>(
          _maskPreviewIsolate,
          _MaskPreviewInput(
            sourcePng: sourcePng,
            strokes: _allStrokes,
            worldRect: worldRect,
            outputWidth: _resolution.$1,
            outputHeight: _resolution.$2,
            expandPixels: _expandPixels,
            borderPixels: (2 * _resolution.$1 / box.width).ceil().clamp(1, 8),
          ),
        );
        if (!mounted ||
            _maskPreviewKey != signature ||
            _maskPreviewCurrentSignature != signature) {
          return;
        }
        setState(() {
          _maskPreviewSignature = signature;
          _maskPreviewBytes = bytes;
        });
      } catch (_) {
        // 预览失败静默忽略（下一次签名变化会重试）。
      }
    });
  }
}

/// 与请求一致的最终遮罩预览。
class _FinalMaskOverlay extends StatelessWidget {
  final InpaintTransform transform;
  final InpaintBox box;
  final Uint8List bytes;

  const _FinalMaskOverlay({
    required this.transform,
    required this.box,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: box.x,
      top: box.y,
      width: box.width,
      height: box.height,
      child: IgnorePointer(child: Image.memory(bytes, fit: BoxFit.fill)),
    );
  }
}

class _FrameDimmerPainter extends CustomPainter {
  final Rect frame;
  const _FrameDimmerPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final inside = frame.intersect(Offset.zero & size);
    if (!inside.isEmpty) outside.addRect(inside);
    canvas.drawPath(outside, Paint()..color = const Color(0x73000000));
  }

  @override
  bool shouldRepaint(_FrameDimmerPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
