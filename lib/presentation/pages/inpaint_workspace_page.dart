import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

/// 工作区顶部的选择模式。
enum InpaintUiMode {
  box, // 方框：图片固定，操作选择框
  image, // 图片：方框固定，操作图片
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
  const _RasterizeInput({
    required this.sourcePng,
    required this.strokes,
    required this.worldRect,
    required this.outputWidth,
    required this.outputHeight,
    required this.expandPixels,
  });
}

class _RasterizeResult {
  final Uint8List basePng;
  final Uint8List workspacePng;
  final Uint8List maskPng;
  const _RasterizeResult(this.basePng, this.workspacePng, this.maskPng);
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
  return _RasterizeResult(
    Uint8List.fromList(img.encodePng(result.image)),
    Uint8List.fromList(img.encodePng(composed)),
    rasterizer.encodeMask(result.mask),
  );
}

/// 候选应用：提取补丁 → 羽化合并 → 输出 PNG。
class _ApplyPatchInput {
  final Uint8List basePng;
  final Uint8List maskPng;
  final Uint8List generatedPng;
  final InpaintViewport worldRect;
  final int featherPixels;
  const _ApplyPatchInput({
    required this.basePng,
    required this.maskPng,
    required this.generatedPng,
    required this.worldRect,
    required this.featherPixels,
  });
}

Uint8List _applyPatchIsolate(_ApplyPatchInput input) {
  final base = img.decodePng(input.basePng);
  final mask = img.decodePng(input.maskPng);
  final generated = img.decodePng(input.generatedPng);
  if (base == null || mask == null || generated == null) {
    throw const FormatException('候选图片解码失败');
  }
  const rasterizer = InpaintRasterizer();
  final extracted = rasterizer.extractPatch(
    generated: generated,
    mask: mask,
    worldRect: input.worldRect,
    outwardFeatherPixels: input.featherPixels,
  );
  if (extracted == null) throw const FormatException('候选没有可提取的内容');
  final merged = rasterizer.mergePatch(
    base: base,
    patch: extracted.image,
    patchRect: extracted.worldRect,
    feather: InpaintFeather(
      top: input.featherPixels,
      right: input.featherPixels,
      bottom: input.featherPixels,
      left: input.featherPixels,
    ),
  );
  return Uint8List.fromList(img.encodePng(merged));
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
  const _MaskPreviewInput({
    required this.sourcePng,
    required this.strokes,
    required this.worldRect,
    required this.outputWidth,
    required this.outputHeight,
    required this.expandPixels,
  });
}

Uint8List _maskPreviewIsolate(_MaskPreviewInput input) {
  final source = img.decodePng(input.sourcePng);
  if (source == null) throw const FormatException('源图解码失败');
  const rasterizer = InpaintRasterizer();
  final mask = rasterizer
      .rasterize(
        source: source,
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
      // 蓝色遮罩预览（RGB 33,150,243）。
      preview.setPixelRgba(x, y, 33, 150, 243, selected ? 150 : 0);
    }
  }
  return Uint8List.fromList(img.encodePng(preview));
}

enum _GestureKind { none, draw, moveBox, panScene, moveGlobal, compareDrag }

/// 局部重绘工作区（嵌入生成页内的圆角卡片组件）。
class InpaintWorkspaceCard extends StatefulWidget {
  const InpaintWorkspaceCard({super.key});

  /// 工作区手势激活中（绘制遮罩/拖框/移动图片/对比拖动）。
  /// 生成页监听它来锁定页面滚动，避免涂抹遮罩时页面跟着移动。
  static final ValueNotifier<bool> gestureActive = ValueNotifier(false);

  @override
  State<InpaintWorkspaceCard> createState() => _InpaintWorkspaceCardState();
}

class _InpaintWorkspaceCardState extends State<InpaintWorkspaceCard> {
  static const double _boxMinSize = 48;
  static const double _compareHitExtent = 28;
  static const double _snapTolerancePx = 12;

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
  InpaintPaintTarget _target = InpaintPaintTarget.mask;
  double _brushSize = 32;
  int _expandPixels = 8;
  int _featherPixels = 8;
  double _inpaintStrength = 0.96;
  bool _showMask = false;
  bool _disabledOriginalImage = false;
  bool _colorCorrect = true;
  int _promptTab = 0;
  bool _promptExpanded = false;
  bool _paramsExpanded = false;
  bool _busy = false;
  InpaintStroke? _draft;
  List<InpaintCandidate> _candidates = [];
  int _activeCandidate = 0;
  double _comparePosition = 0.5;
  bool _compareDragging = false;
  bool _batchCancelled = false;
  int _batchCompleted = 0;
  int _batchTotal = 1;
  final Map<int, Offset> _pointers = {};
  _GestureKind _gesture = _GestureKind.none;
  Offset? _lastGestureCenter;
  double? _lastGestureDistance;
  String? _sessionSourcePath;
  String? _sessionMaskPath;
  int _generationRevision = 0;
  String? _activeRevision;
  bool _showBatchFinished = false;
  bool _officialUpscaling = false;
  bool _applying = false;

  /// 应用候选后合并出的整张图路径（保存相册的数据源）。
  String? _appliedResultPath;

  /// 是否存在已应用但尚未保存的整图（应用后 _loadImage 会把
  /// _appliedResultPath 置为新图本身，仍视为可保存）。
  bool get _hasUnsavedAppliedResult => _appliedResultPath != null;

  /// 遮罩预览：后台生成，签名匹配才显示（防抖 + 防错位）。
  String? _maskPreviewSignature;
  String _maskPreviewKey = '';
  Uint8List? _maskPreviewBytes;
  Timer? _maskPreviewDebounce;

  InpaintUiMode _uiMode = InpaintUiMode.box;

  /// 底部遮罩笔被点选后进入绘制模式（优先于方框/图片手势）。
  bool _drawToolActive = false;

  /// 笔刷形状：圆形（默认）或方形。
  bool _squareBrush = false;

  /// 长按遮罩笔上下滑动调节笔刷大小。
  /// 记录长按起点，滑动增量映射到笔刷值。
  double? _brushDragStartY;
  double? _brushDragStartValue;

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
    if (path == null || path == _sourcePath) return;
    if (_sessionSourcePath != null && path == _sessionSourcePath) return;
    if (_sessionMaskPath != null && path == _sessionMaskPath) return;
    if (!File(path).existsSync()) return;
    _loadImage(path);
  }

  @override
  void dispose() {
    _generation.removeListener(_onVmChanged);
    if (_generation.inpaintWorkspaceHandler == _prepareGeneration) {
      _generation.inpaintWorkspaceHandler = null;
    }
    _maskPreviewDebounce?.cancel();
    _promptController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  Future<void> _loadImage(
    String path, {
    bool resetSession = true,
  }) async {
    final file = File(path);
    if (!await file.exists()) return;
    // 后台解码大图，避免主线程阻塞。
    final result = await compute<_DecodeImageInput, _DecodeImageResult>(
      _decodeImageIsolate,
      _DecodeImageInput(await file.readAsBytes()),
    );
    if (!mounted) return;
    // 保留磁盘上的 PNG 字节供后台光栅化复用（RGBA 无损）。
    _sourcePngBytes = result.pngBytes;
    setState(() {
      _sourcePath = path;
      _sourceWidth = result.width;
      _sourceHeight = result.height;
      _transform = const InpaintTransform();
      _box = null;
      _strokes.clear();
      _undo.clear();
      _redo.clear();
      if (resetSession) {
        _candidates = [];
        _activeCandidate = 0;
        _comparePosition = 0.5;
        _sessionSourcePath = null;
        _sessionMaskPath = null;
        _appliedResultPath = null;
        _activeRevision = null;
        _showBatchFinished = false;
      }
    });
  }

  Future<void> _pickSource() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) await _loadImage(file.path);
  }

  void _saveHistory() {
    _undo.add(List.of(_strokes));
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  List<InpaintStroke> get _allStrokes => [
        ..._strokes,
        if (_draft != null) _draft!,
      ];

  void _clearAllStrokes() {
    if (_busy) return;
    if (_strokes.isEmpty) return;
    _saveHistory();
    setState(() => _strokes.clear());
  }

  void _undoStroke() {
    if (_undo.isEmpty || _busy) return;
    _redo.add(List.of(_strokes));
    final previous = _undo.removeLast();
    setState(() {
      _strokes
        ..clear()
        ..addAll(previous);
    });
  }

  void _redoStroke() {
    if (_redo.isEmpty || _busy) return;
    _undo.add(List.of(_strokes));
    final next = _redo.removeLast();
    setState(() {
      _strokes
        ..clear()
        ..addAll(next);
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

  /// 方框模式双指缩放：以捏合中心为锚点等比缩放选择框，图片保持固定。
  /// 框最大不超过图片在屏幕上的尺寸（不可选取图片以外区域）。
  void _zoomBox(double factor, Offset anchor) {
    final box = _box;
    if (box == null || _sourceWidth <= 0) return;
    final s = _transform.scale;
    if (s <= 0) return;
    // 上限 = 图片在屏幕上的尺寸。
    final maxScreenWidth = _sourceWidth * s;
    final maxScreenHeight = _sourceHeight * s;
    var width = (box.width * factor)
        .clamp(_boxMinSize, math.max(maxScreenWidth, _boxMinSize))
        .toDouble();
    var height = width / _boxAspect;
    if (height > maxScreenHeight) {
      height = math.max(maxScreenHeight, _boxMinSize);
      width = (height * _boxAspect).clamp(_boxMinSize, maxScreenWidth);
    }
    final centerX = anchor.dx + (box.x + box.width / 2 - anchor.dx) * factor;
    final centerY = anchor.dy + (box.y + box.height / 2 - anchor.dy) * factor;
    setState(() => _box = _snapBox(InpaintBox(
          x: centerX - width / 2,
          y: centerY - height / 2,
          width: width,
          height: height,
        )));
  }

  /// 候选预览时的同步缩放：场景与选择框围绕锚点一起缩放，保持对齐。
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

  /// 候选预览时的同步平移：框随场景一起移动，保持与生成区域对齐。
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

  /// 移动选择框：限制在图片范围内（世界坐标钳制），不可选取图片以外的区域。
  void _moveBox(Offset delta) {
    final box = _box;
    if (box == null || _sourceWidth <= 0) return;
    final s = _transform.scale;
    if (s <= 0) return;
    final next = box.translate(delta.dx, delta.dy);
    final maxWidth = (box.width / s).clamp(0.0, _sourceWidth.toDouble());
    final maxHeight = (box.height / s).clamp(0.0, _sourceHeight.toDouble());
    // 世界坐标范围：x ∈ [0, sourceW - boxW]，y 同理。
    final worldX = (next.x - _transform.offsetX) / s;
    final worldY = (next.y - _transform.offsetY) / s;
    final clampedX = worldX.clamp(0.0, _sourceWidth - maxWidth);
    final clampedY = worldY.clamp(0.0, _sourceHeight - maxHeight);
    setState(() => _box = InpaintBox(
          x: clampedX * s + _transform.offsetX,
          y: clampedY * s + _transform.offsetY,
          width: box.width,
          height: box.height,
        ));
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

  /// 边缘吸附：选择框边缘接近图片边缘时精确对齐（容差内强制归零缝隙）。
  /// 框超出图片边缘时钳回图片范围内，保证视觉上完全贴合。
  InpaintBox _snapBox(InpaintBox box) {
    if (_sourceWidth <= 0) return box;
    final s = _transform.scale;
    if (s <= 0) return box;
    final tolerance = _snapTolerancePx / s;
    const contentLeft = 0.0;
    const contentTop = 0.0;
    final contentRight = _sourceWidth.toDouble();
    final contentBottom = _sourceHeight.toDouble();
    final boxWorldWidth = box.width / s;
    final boxWorldHeight = box.height / s;

    // 屏幕坐标 → 世界坐标计算贴合，再换回屏幕坐标。
    final worldX = (box.x - _transform.offsetX) / s;
    final worldY = (box.y - _transform.offsetY) / s;
    final worldRight = worldX + boxWorldWidth;
    final worldBottom = worldY + boxWorldHeight;

    var snapX = worldX;
    var snapY = worldY;
    var snappedX = false;
    var snappedY = false;

    // 左边缘：接近图片左缘则对齐；框左缘已越出图片左缘则钳回。
    if ((worldX - contentLeft).abs() <= tolerance || worldX < contentLeft) {
      snapX = contentLeft;
      snappedX = true;
    }
    // 右边缘：接近或越出图片右缘则右缘对齐图片右缘。
    if ((worldRight - contentRight).abs() <= tolerance ||
        worldRight > contentRight) {
      snapX = contentRight - boxWorldWidth;
      snappedX = true;
    }
    if ((worldY - contentTop).abs() <= tolerance || worldY < contentTop) {
      snapY = contentTop;
      snappedY = true;
    }
    if ((worldBottom - contentBottom).abs() <= tolerance ||
        worldBottom > contentBottom) {
      snapY = contentBottom - boxWorldHeight;
      snappedY = true;
    }

    // 两侧同时触发（框比图片宽/高）时保证左上角不产生负偏移。
    if (snapX < contentLeft) snapX = contentLeft;
    if (snapY < contentTop) snapY = contentTop;

    if (!snappedX && !snappedY) return box;
    return InpaintBox(
      x: snapX * s + _transform.offsetX,
      y: snapY * s + _transform.offsetY,
      width: box.width,
      height: box.height,
    );
  }

  bool _hitCompareHandle(Offset point) {
    final box = _box;
    if (box == null || _currentCandidate == null) return false;
    final splitX = box.x + box.width * _comparePosition;
    return (point.dx - splitX).abs() <= _compareHitExtent &&
        point.dy >= box.y &&
        point.dy <= box.y + box.height;
  }

  void _startStroke(Offset point) {
    if (_sourceWidth <= 0 || _busy) return;
    final world = _screenToWorld(point);
    _saveHistory();
    setState(() {
      _draft = InpaintStroke(
        target: _target,
        mode: InpaintStrokeMode.paint,
        type: InpaintStrokeType.path,
        size: _brushSize,
        square: _squareBrush,
        points: [InpaintPoint(world.dx, world.dy)],
        start: InpaintPoint(world.dx, world.dy),
      );
    });
  }

  void _updateStroke(Offset point) {
    final draft = _draft;
    if (draft == null) return;
    final world = _screenToWorld(point);
    setState(() {
      _draft = InpaintStroke(
        target: draft.target,
        mode: draft.mode,
        type: draft.type,
        size: draft.size,
        color: draft.color,
        opacity: draft.opacity,
        points: [...draft.points, InpaintPoint(world.dx, world.dy)],
      );
    });
  }

  void _finishStroke() {
    final draft = _draft;
    if (draft == null) return;
    if (draft.type == InpaintStrokeType.path && draft.points.isEmpty) return;
    setState(() {
      _strokes.add(draft);
      _draft = null;
    });
  }

  // ---- 手势 ----

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      final point = event.localPosition;
      if (_currentCandidate != null) {
        _gesture = _hitCompareHandle(point)
            ? _GestureKind.compareDrag
            : _GestureKind.moveGlobal;
      } else if (_sourceWidth <= 0 || _busy) {
        _gesture = _GestureKind.none;
      } else if (_drawToolActive && _target == InpaintPaintTarget.mask) {
        _gesture = _GestureKind.draw;
        _startStroke(point);
      } else {
        switch (_uiMode) {
          case InpaintUiMode.box:
            // 方框模式：图片固定，单指始终移动选择框。
            _gesture = _GestureKind.moveBox;
          case InpaintUiMode.image:
            // 图片模式：方框固定，单指移动图片。
            _gesture = _GestureKind.panScene;
        }
      }
    } else if (_pointers.length == 2) {
      _draft = null;
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
        // 双指同向滑动：整体平移，语义与单指一致（方框模式移框，图片模式移图）。
        final oldCenter = _lastGestureCenter ?? center;
        final panDelta = center - oldCenter;
        if (_currentCandidate != null) {
          _moveGlobal(panDelta);
        } else if (_drawToolActive && _target == InpaintPaintTarget.mask) {
          _panScene(panDelta);
        } else {
          switch (_uiMode) {
            case InpaintUiMode.box:
              _moveBox(panDelta);
            case InpaintUiMode.image:
              _panScene(panDelta);
          }
        }
        // 双指张合：缩放。
        final distance = (points[0] - points[1]).distance;
        final oldDistance = _lastGestureDistance;
        if (oldDistance != null && oldDistance > 0 && distance > 0) {
          final factor = distance / oldDistance;
          if (_currentCandidate != null) {
            _zoomGlobal(factor, center);
          } else if (_drawToolActive && _target == InpaintPaintTarget.mask) {
            _zoomScene(factor, center);
          } else {
            switch (_uiMode) {
              case InpaintUiMode.box:
                _zoomBox(factor, center);
              case InpaintUiMode.image:
                _zoomScene(factor, center);
            }
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
      case _GestureKind.compareDrag:
        _updateComparePosition(event.localPosition);
      case _GestureKind.none:
        break;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      if (_gesture == _GestureKind.draw) _finishStroke();
      if (_box != null) {
        // 任一拖动结束后执行一次边缘吸附。
        setState(() => _box = _snapBox(_box!));
      }
      _gesture = _GestureKind.none;
      _lastGestureCenter = null;
      _lastGestureDistance = null;
      _compareDragging = false;
      // 手势结束，解除页面滚动锁定。
      InpaintWorkspaceCard.gestureActive.value = false;
    }
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _draft = null;
      _gesture = _GestureKind.none;
      _lastGestureCenter = null;
      _lastGestureDistance = null;
      _compareDragging = false;
      InpaintWorkspaceCard.gestureActive.value = false;
    }
    setState(() {});
  }

  void _updateComparePosition(Offset point) {
    final box = _box;
    if (box == null || box.width <= 0) return;
    _compareDragging = true;
    setState(() {
      _comparePosition =
          ((point.dx - box.x) / box.width).clamp(0.0, 1.0).toDouble();
    });
  }

  // ---- 生成（完整管线在工作区内：光栅化 → 队列 → 候选 → 对比）----
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
    final total = _generation.batchCount.clamp(1, 30);
    final revision = 'workspace-${++_generationRevision}';
    // 选择框（屏幕坐标）→ 图像世界坐标。
    final worldRect = InpaintViewport(
      x: (box.x - _transform.offsetX) / _transform.scale,
      y: (box.y - _transform.offsetY) / _transform.scale,
      width: box.width / _transform.scale,
      height: box.height / _transform.scale,
    );
    setState(() {
      _busy = true;
      _batchCancelled = false;
      _batchCompleted = 0;
      _batchTotal = total;
      _activeRevision = revision;
      _showBatchFinished = false;
      // 新一轮生成开始，旧的已应用结果不再是"当前修改后的图"。
      _appliedResultPath = null;
    });
    try {
      // 光栅化与 PNG 编码在后台 isolate 执行，避免大图阻塞主线程导致 ANR 闪退。
      final raster = await compute<_RasterizeInput, _RasterizeResult>(
        _rasterizeIsolate,
        _RasterizeInput(
          sourcePng: sourcePng,
          strokes: _allStrokes,
          worldRect: worldRect,
          outputWidth: _resolution.$1,
          outputHeight: _resolution.$2,
          expandPixels: _expandPixels,
        ),
      );
      final dir = await ImageUtils.getImageDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final basePath = '${dir.path}${Platform.pathSeparator}'
          'inpaint_${timestamp}_base.png';
      final workspacePath = '${dir.path}${Platform.pathSeparator}'
          'inpaint_${timestamp}_workspace.png';
      final maskPath = '${dir.path}${Platform.pathSeparator}'
          'inpaint_${timestamp}_mask.png';
      await File(basePath).writeAsBytes(raster.basePng, flush: true);
      await File(workspacePath).writeAsBytes(raster.workspacePng, flush: true);
      await File(maskPath).writeAsBytes(raster.maskPng, flush: true);
      _sessionSourcePath = basePath;
      _sessionMaskPath = maskPath;
      await _generation.updateInpaintPrompt(_promptController.text);
      await _generation.updateInpaintNegativePrompt(_negativeController.text);
      _generation.updateInpaintOptions(
        disabledOriginalImage: _disabledOriginalImage,
        colorCorrect: _colorCorrect,
      );
      _generation.updateInpaintStrength(_inpaintStrength);
      for (var index = 0; index < total; index++) {
        if (_batchCancelled) break;
        final task = _generation.buildInpaintTask(
          sourcePath: basePath,
          maskPath: maskPath,
          prompt: _promptController.text,
          negativePrompt: _negativeController.text,
          strength: _inpaintStrength,
          disabledOriginalImage: _disabledOriginalImage,
          colorCorrect: _colorCorrect,
        );
        final completed = await _queue.enqueueTransientAndWait(task);
        if (!mounted || revision != _activeRevision) return false;
        if (completed.status == 'success') {
          final path = await _saveImage.saveTransient(completed);
          final candidate = InpaintCandidate(
            id: completed.taskId,
            imagePath: path,
            baseImagePath: basePath,
            workspaceImagePath: workspacePath,
            maskImagePath: maskPath,
            worldRect: worldRect,
            seed: completed.seed,
          );
          setState(() {
            _candidates = [..._candidates, candidate];
            _activeCandidate = _candidates.length - 1;
            _comparePosition = 0.5;
            _batchCompleted++;
          });
        } else {
          showFloatingToast(context, completed.errorMessage ?? '候选生成失败');
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
          _showBatchFinished = true;
        });
      }
    }
  }

  InpaintCandidate? get _currentCandidate =>
      _candidates.isEmpty ? null : _candidates[_activeCandidate];


  void _selectCandidate(int offset) {
    if (_candidates.isEmpty) return;
    setState(() {
      _activeCandidate =
          (_activeCandidate + offset + _candidates.length) % _candidates.length;
      _comparePosition = 0.5;
    });
  }

  /// 保存整张图到相册：仅在应用候选后可用，保存的是当前工作区底图
  /// （已合并重绘结果的完整图片）。应用前没有"修改后的图"可保存。
  Future<void> _saveCandidateToGallery() async {
    final path = _appliedResultPath;
    if (path == null || !File(path).existsSync()) {
      showFloatingToast(context, '请先应用候选，再保存修改后的图片');
      return;
    }
    final gallerySaved = await _saveImage.saveToGallery(path);
    if (mounted) {
      showFloatingToast(
          context, gallerySaved ? '整张修改后的图已保存到相册' : '保存失败，请检查相册权限');
    }
  }

  Future<void> _applyCandidate() async {
    final candidate = _currentCandidate;
    if (candidate == null || _applying) return;
    setState(() => _applying = true);
    try {
      // 补丁提取 + 羽化合并 + PNG 编码全部在后台 isolate 执行。
      final mergedPng = await compute<_ApplyPatchInput, Uint8List>(
        _applyPatchIsolate,
        _ApplyPatchInput(
          basePng: await File(candidate.workspaceImagePath).readAsBytes(),
          maskPng: await File(candidate.maskImagePath).readAsBytes(),
          generatedPng: await File(candidate.imagePath).readAsBytes(),
          worldRect: candidate.worldRect,
          featherPixels: _featherPixels,
        ),
      );
      final dir = await ImageUtils.getImageDirectory();
      final path = '${dir.path}${Platform.pathSeparator}'
          'inpaint_applied_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(mergedPng, flush: true);
      // 应用后保留当前方框位置与尺寸，便于继续框选重绘。
      final keepBox = _box;
      final keepTransform = _transform;
      await _loadImage(path);
      if (!mounted) return;
      setState(() {
        _box = keepBox;
        _transform = keepTransform;
        // 记录合并后的整图，"保存相册"保存的就是它。
        _appliedResultPath = path;
      });
      showFloatingToast(context, '候选结果已应用，可继续局部重绘');
    } catch (error) {
      if (mounted) showFloatingToast(context, '应用候选失败：$error');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
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
    final colors = Theme.of(context).colorScheme;
    // 遮罩预览开启时调度后台生成（签名防抖）。
    if (_showMask) _scheduleMaskPreview();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        _buildHeader(colors),
        _buildStage(),
        _buildToolbar(colors),
      ]),
    );
  }

  /// 顶部：折叠的正负提示词栏 → 分辨率 + 方框/图片切换。
  Widget _buildHeader(ColorScheme colors) {
    return Column(children: [
      // 折叠提示词栏。
      Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
        child: InkWell(
          onTap: () => setState(() => _promptExpanded = !_promptExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(
                CupertinoIcons.textformat_abc,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
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
            CupertinoSlidingSegmentedControl<int>(
              groupValue: _promptTab,
              children: const {0: Text('正面'), 1: Text('负面')},
              onValueChanged: (value) =>
                  setState(() => _promptTab = value ?? 0),
            ),
            const SizedBox(height: 6),
            TextField(
              controller:
                  _promptTab == 0 ? _promptController : _negativeController,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: _promptTab == 0 ? '重绘正向提示词' : '重绘负向提示词',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (_promptTab == 0) {
                  _generation.updateInpaintPrompt(value);
                } else {
                  _generation.updateInpaintNegativePrompt(value);
                }
              },
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
                  _paramsExpanded ? '收起参数' : '重绘参数',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ]),
        ),
      ),
      // 分辨率 + 方框/图片切换。
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
        child: Row(children: [
          _resolutionButton(colors),
          const SizedBox(width: 10),
          Expanded(child: _buildModeSwitch(colors)),
        ]),
      ),
    ]);
  }

  Widget _resolutionButton(ColorScheme colors) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.45)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: _busy ? null : _chooseResolution,
      icon: Icon(CupertinoIcons.crop,
          size: 14, color: colors.primary),
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

  /// 方框/图片左右滑动切换按钮。
  Widget _buildModeSwitch(ColorScheme colors) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Stack(children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment:
              _uiMode == InpaintUiMode.box ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            width: 72,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        Row(children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _uiMode = InpaintUiMode.box;
                _drawToolActive = false;
              }),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.rectangle_dock,
                      size: 14,
                      color: _uiMode == InpaintUiMode.box
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '方框',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _uiMode == InpaintUiMode.box
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _uiMode = InpaintUiMode.image;
                _drawToolActive = false;
              }),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.photo,
                      size: 14,
                      color: _uiMode == InpaintUiMode.image
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '图片',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _uiMode == InpaintUiMode.image
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildStage() {
    final colors = Theme.of(context).colorScheme;
    final sourcePath = _sourcePath;
    final sourceWidth = _sourceWidth;
    if (sourcePath == null || sourceWidth <= 0) {
      return AspectRatio(
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
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
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
                  if (_box != null) _buildBoxDimmer(),
                  CustomPaint(
                    painter: _InpaintCanvasPainter(
                      transform: _transform,
                      strokes: _allStrokes,
                      squareBrush: _squareBrush,
                    ),
                  ),
                  if (_showMask &&
                      _box != null &&
                      !_busy &&
                      _maskPreviewKey == _maskPreviewSignature &&
                      _maskPreviewBytes != null)
                    _FinalMaskOverlay(
                      transform: _transform,
                      box: _box!,
                      bytes: _maskPreviewBytes!,
                    ),
                  if (_box != null) _buildBoxFrame(),
                  if (_currentCandidate != null && _box != null)
                    _CompareLayer(
                      box: _box!,
                      generatedPath: _currentCandidate!.imagePath,
                      basePath: _currentCandidate!.baseImagePath,
                      position: _comparePosition,
                      dragging: _compareDragging,
                    ),
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
                                  _generation.officialUpscaleStatus ?? '官方超分中…',
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

  /// 框外暗幕。
  Widget _buildBoxDimmer() {
    return Positioned.fromRect(
      rect: _box!.rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                spreadRadius: 9999,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选择框边框与分辨率标签。
  Widget _buildBoxFrame() {
    final box = _box!;
    final hasCandidate = _currentCandidate != null;
    final colors = Theme.of(context).colorScheme;
    final borderColor = hasCandidate ? colors.tertiary : colors.primary;
    return Positioned.fromRect(
      rect: box.rect,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(children: [
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
                Text('生成中 $_batchCompleted/$_batchTotal',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 工作区下边工具栏：遮罩/图像层、遮罩笔（长按上下滑调节大小）、
  /// 方形/圆形笔刷切换、撤销重做、遮罩预览。
  Widget _buildToolbar(ColorScheme colors) {
    final hasCandidate = _currentCandidate != null;
    final isMask = _target == InpaintPaintTarget.mask;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _layerChip(colors),
            const SizedBox(width: 4),
            if (isMask) ...[
              // 遮罩笔：点按启用绘制；长按后上下滑动调节笔刷大小。
              _maskBrushChip(colors, enabled: !hasCandidate),
              const SizedBox(width: 4),
              // 笔刷形状切换：方形 / 圆形。
              _brushShapeChip(colors, enabled: !hasCandidate),
            ],
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '撤销',
              onPressed: _undo.isEmpty || hasCandidate ? null : _undoStroke,
              icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 18),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '重做',
              onPressed: _redo.isEmpty || hasCandidate ? null : _redoStroke,
              icon: const Icon(CupertinoIcons.arrow_uturn_right, size: 18),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '最终遮罩预览',
              onPressed:
                  hasCandidate ? null : () => setState(() => _showMask = !_showMask),
              icon: Icon(
                _showMask ? CupertinoIcons.eye_fill : CupertinoIcons.eye,
                size: 18,
              ),
            ),
            // 当前笔刷大小指示（随长按调节实时刷新）。
            if (isMask)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_brushSize.round()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _drawToolActive ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ),
          ]),
        ),
        // 底部功能行：左下角菜单（重置视图 / 清空遮罩），右下角应用 + 保存相册。
        // 生成统一使用页面下方的悬浮生成按钮，工作区不再放生成入口。
        Row(children: [
          _cornerMenuButton(colors),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: hasCandidate && !_busy ? _applyCandidate : null,
            icon: const Icon(CupertinoIcons.checkmark_circle, size: 15),
            label: Text(
              _applying ? '应用中…' : '应用',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              side: BorderSide(
                  color: _appliedResultPath != null
                      ? colors.primary.withValues(alpha: 0.45)
                      : colors.onSurfaceVariant.withValues(alpha: 0.25)),
            ),
            onPressed: (_appliedResultPath != null ||
                    _hasUnsavedAppliedResult)
                ? _saveCandidateToGallery
                : null,
            icon: const Icon(CupertinoIcons.photo_on_rectangle, size: 15),
            label: const Text('保存相册', style: TextStyle(fontSize: 13)),
          ),
        ]),
        if (_candidates.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _selectCandidate(-1),
                icon: const Icon(CupertinoIcons.chevron_left, size: 16),
              ),
              Text(
                '${_activeCandidate + 1}/${_candidates.length}',
                style: const TextStyle(fontSize: 12),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _selectCandidate(1),
                icon: const Icon(CupertinoIcons.chevron_right, size: 16),
              ),
              if (_showBatchFinished)
                Expanded(
                  child: Text(
                    '生成完成 · 拖动框内分割线可对比结果',
                    style: TextStyle(fontSize: 11, color: colors.primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _layerChip(ColorScheme colors) {
    final isMask = _target == InpaintPaintTarget.mask;
    return GestureDetector(
      onTap: () => setState(() {
        _target =
            isMask ? InpaintPaintTarget.image : InpaintPaintTarget.mask;
        // 切换图层时退出绘制模式，避免误画。
        _drawToolActive = false;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isMask
              ? colors.primary.withValues(alpha: 0.14)
              : colors.tertiary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMask
                ? colors.primary.withValues(alpha: 0.4)
                : colors.tertiary.withValues(alpha: 0.4),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            CupertinoIcons.layers,
            size: 14,
            color: isMask ? colors.primary : colors.tertiary,
          ),
          const SizedBox(width: 4),
          Text(
            isMask ? '遮罩' : '图像',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isMask ? colors.primary : colors.tertiary,
            ),
          ),
        ]),
      ),
    );
  }

  /// 遮罩笔 chip：点按启用绘制；长按后上下滑动调节笔刷大小
  /// （上滑增大、下滑减小，松手结束）。
  Widget _maskBrushChip(ColorScheme colors, {required bool enabled}) {
    return GestureDetector(
      onTap: enabled
          ? () => setState(() => _drawToolActive = !_drawToolActive)
          : null,
      onLongPressStart: (details) {
        if (!enabled) return;
        _brushDragStartY = details.globalPosition.dy;
        _brushDragStartValue = _brushSize;
        setState(() => _drawToolActive = true);
      },
      onLongPressMoveUpdate: (details) {
        final startY = _brushDragStartY;
        final startValue = _brushDragStartValue;
        if (startY == null || startValue == null) return;
        // 上滑增大、下滑减小：1px ≈ 0.8 笔刷单位。
        final delta = (startY - details.globalPosition.dy) * 0.8;
        setState(() {
          _brushSize = (startValue + delta).clamp(1.0, 400.0).toDouble();
        });
      },
      onLongPressEnd: (_) {
        _brushDragStartY = null;
        _brushDragStartValue = null;
      },
      onLongPressCancel: () {
        _brushDragStartY = null;
        _brushDragStartValue = null;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _drawToolActive
              ? colors.primary.withValues(alpha: 0.16)
              : colors.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _drawToolActive
                ? colors.primary.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            CupertinoIcons.paintbrush,
            size: 14,
            color: _drawToolActive ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '遮罩笔',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  _drawToolActive ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ]),
      ),
    );
  }

  /// 笔刷形状切换 chip：方形 / 圆形两种笔刷。
  Widget _brushShapeChip(ColorScheme colors, {required bool enabled}) {
    final isSquare = _squareBrush;
    return GestureDetector(
      onTap: enabled
          ? () => setState(() => _squareBrush = !_squareBrush)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _drawToolActive
              ? colors.primary.withValues(alpha: 0.16)
              : colors.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _drawToolActive
                ? colors.primary.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // 形状示意：方形实心方块 / 圆形实心圆。
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color:
                  _drawToolActive ? colors.primary : colors.onSurfaceVariant,
              borderRadius:
                  isSquare ? BorderRadius.circular(2) : BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isSquare ? '方形' : '圆形',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  _drawToolActive ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ]),
      ),
    );
  }

  /// 左下角功能菜单：重置视图 / 清空全部遮罩 / 导入图片 / 放大图片。
  Widget _cornerMenuButton(ColorScheme colors) {
    return PopupMenuButton<String>(
      tooltip: '工作区菜单',
      padding: EdgeInsets.zero,
      icon: const Icon(CupertinoIcons.ellipsis_circle, size: 20),
      onSelected: (value) {
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
            Icon(CupertinoIcons.trash,
                size: 18, color: colors.error),
            const SizedBox(width: 8),
            Text('清空全部遮罩',
                style: TextStyle(
                    fontSize: 13,
                    color: _strokes.isNotEmpty ? colors.error : null)),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'pick',
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
          onChanged: (value) => setState(() {
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
          onChanged: (value) => setState(() {
            _colorCorrect = value ?? true;
            _generation.updateInpaintOptions(colorCorrect: _colorCorrect);
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
          onChanged: (v) => setState(() => onChanged(v)),
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
      box.x.toStringAsFixed(1),
      box.y.toStringAsFixed(1),
      box.width.toStringAsFixed(1),
      _transform.offsetX.toStringAsFixed(1),
      _transform.offsetY.toStringAsFixed(1),
      _transform.scale.toStringAsFixed(3),
      _expandPixels,
      _strokes.length,
      _generation.selectedResolution,
    ].join('|');
  }

  void _scheduleMaskPreview() {
    if (!_showMask) return;
    final signature = _maskPreviewCurrentSignature;
    if (signature.isEmpty || signature == _maskPreviewKey) return;
    _maskPreviewDebounce?.cancel();
    _maskPreviewDebounce = Timer(const Duration(milliseconds: 250), () async {
      final sourcePng = _sourcePngBytes;
      final box = _box;
      if (sourcePng == null || box == null || !mounted) return;
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
          ),
        );
        if (!mounted) return;
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

/// 候选对比层：框内左侧显示生成结果，右侧显示原图，分割线可拖动。
class _CompareLayer extends StatelessWidget {
  final InpaintBox box;
  final String generatedPath;
  final String basePath;
  final double position;
  final bool dragging;

  const _CompareLayer({
    required this.box,
    required this.generatedPath,
    required this.basePath,
    required this.position,
    required this.dragging,
  });

  @override
  Widget build(BuildContext context) {
    final splitX = box.width * position.clamp(0.0, 1.0);
    return Positioned.fromRect(
      rect: box.rect,
      child: Stack(
        children: [
          // 底层：原图铺满整框。
          Positioned.fill(
            child: Image.file(File(basePath), fit: BoxFit.fill),
          ),
          // 上层：生成结果，仅占分割线左侧区域；OverflowBox 让内部图片
          // 仍以整框尺寸铺满，再由外层宽度裁剪出左侧部分。
          Positioned(
            left: 0,
            top: 0,
            width: math.max(splitX, 0.001),
            height: box.height,
            child: ClipRect(
              child: OverflowBox(
                maxWidth: box.width,
                maxHeight: box.height,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: Image.file(File(generatedPath), fit: BoxFit.fill),
                ),
              ),
            ),
          ),
          // 分割线。
          Positioned(
            left: splitX - 1,
            top: 0,
            width: 2,
            height: box.height,
            child: const ColoredBox(
              color: Color(0xF2FFFFFF),
            ),
          ),
          // 拖动手柄。
          Positioned(
            left: splitX - 16,
            top: box.height / 2 - 16,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: dragging
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4),
                ],
              ),
              child: const Icon(
                CupertinoIcons.arrow_left_right,
                size: 16,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

class _InpaintCanvasPainter extends CustomPainter {
  final InpaintTransform transform;
  final List<InpaintStroke> strokes;

  /// 是否方形笔刷（false = 圆形）。
  final bool squareBrush;

  const _InpaintCanvasPainter({
    required this.transform,
    required this.strokes,
    this.squareBrush = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final color = stroke.target == InpaintPaintTarget.mask
          ? const Color(0x802196F3) // 蓝色遮罩（半透明）
          : Colors.amber.withValues(alpha: 0.65);
      final screenHalf = stroke.size * transform.scale / 2;
      if (squareBrush) {
        // 方形笔刷：沿路径逐点绘制方块并合并填充。
        final fill = Paint()..color = color;
        final path = Path();
        for (final point in stroke.points) {
          final screen = Offset(point.x * transform.scale + transform.offsetX,
              point.y * transform.scale + transform.offsetY);
          path.addRect(Rect.fromCenter(
            center: screen,
            width: screenHalf * 2,
            height: screenHalf * 2,
          ));
        }
        canvas.drawPath(path, fill);
        continue;
      }
      // 圆形笔刷：圆头线帽连线。
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.size * transform.scale
        ..color = color;
      final path = Path();
      for (var i = 0; i < stroke.points.length; i++) {
        final point = stroke.points[i];
        final screen = Offset(point.x * transform.scale + transform.offsetX,
            point.y * transform.scale + transform.offsetY);
        if (i == 0) {
          path.moveTo(screen.dx, screen.dy);
        } else {
          path.lineTo(screen.dx, screen.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InpaintCanvasPainter oldDelegate) => true;
}
