import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';
import 'package:nai_huishi/presentation/widgets/fullscreen_image_preview.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/prompt_apply_parser.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';
import 'package:nai_huishi/presentation/widgets/prompt_capsule_sheet.dart';

class _MaskStroke {
  final List<Offset> points;
  final double strokeWidth;

  const _MaskStroke({required this.points, required this.strokeWidth});
}

class _MaskPainter extends CustomPainter {
  final List<_MaskStroke> strokes;
  final List<_MaskStroke>? erasedStrokes;
  final bool preview;

  const _MaskPainter(
      {required this.strokes, required this.preview, this.erasedStrokes});

  void _drawStrokes(
      Canvas canvas, Size size, List<_MaskStroke> strokeList, Paint paint) {
    for (final stroke in strokeList) {
      if (stroke.points.isEmpty) continue;
      final pixelStrokeWidth = stroke.strokeWidth * size.width;
      paint.strokeWidth = pixelStrokeWidth;

      if (stroke.points.length == 1) {
        final p = stroke.points.first;
        canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height),
          pixelStrokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx * size.width,
            stroke.points.first.dy * size.height);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 生成模式（非预览）：画纯黑背景 + 白色画笔笔迹 + 黑色橡皮擦笔迹
    if (!preview) {
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black;
      canvas.drawRect(Offset.zero & size, fillPaint);

      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white;
      _drawStrokes(canvas, size, strokes, strokePaint);

      if (erasedStrokes != null && erasedStrokes!.isNotEmpty) {
        final eraserPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black;
        _drawStrokes(canvas, size, erasedStrokes!, eraserPaint);
      }
      return;
    }

    // 预览模式：用 saveLayer + BlendMode 实现橡皮擦真正擦除红色遮罩
    canvas.saveLayer(Offset.zero & size, Paint());

    // 画红色遮罩（画笔笔迹）
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xAAFF3333);
    _drawStrokes(canvas, size, strokes, strokePaint);

    // 用 clear 混合模式擦除橡皮擦区域（红色消失，露出底图）
    if (erasedStrokes != null && erasedStrokes!.isNotEmpty) {
      final eraserPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.clear;
      _drawStrokes(canvas, size, erasedStrokes!, eraserPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.preview != preview ||
        oldDelegate.erasedStrokes != erasedStrokes;
  }
}

class _ChatFab extends StatelessWidget {
  final VoidCallback onTap;

  const _ChatFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            CupertinoIcons.wand_stars,
            size: 26,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _MaskEditor extends StatelessWidget {
  final String imagePath;
  final List<_MaskStroke> strokes;
  final List<_MaskStroke>? erasedStrokes;
  final double strokeWidth;
  final bool editable;
  final void Function(DragStartDetails, Size)? onPanStart;
  final void Function(DragUpdateDetails, Size)? onPanUpdate;
  final VoidCallback? onPanEnd;
  final double aspectRatio;

  const _MaskEditor({
    required this.imagePath,
    required this.strokes,
    this.erasedStrokes,
    required this.strokeWidth,
    this.editable = true,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    required this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        // 按原图真实比例计算画布尺寸
        double canvasWidth, canvasHeight;
        if (aspectRatio >= 1) {
          // 横向图
          canvasWidth = maxWidth;
          canvasHeight = maxWidth / aspectRatio;
        } else {
          // 纵向图
          canvasHeight = maxWidth / aspectRatio > constraints.maxHeight
              ? constraints.maxHeight
              : maxWidth / aspectRatio;
          canvasWidth = canvasHeight * aspectRatio;
        }
        final size = Size(canvasWidth, canvasHeight);

        Widget canvas = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(imagePath), fit: BoxFit.fill),
              CustomPaint(
                painter: _MaskPainter(
                    strokes: strokes,
                    preview: true,
                    erasedStrokes: erasedStrokes),
              ),
              if (editable)
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '笔刷 ${strokeWidth.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        if (editable &&
            onPanStart != null &&
            onPanUpdate != null &&
            onPanEnd != null) {
          canvas = Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              final details = DragStartDetails(
                globalPosition: event.position,
                localPosition: event.localPosition,
              );
              onPanStart!(details, size);
            },
            onPointerMove: (event) {
              final details = DragUpdateDetails(
                globalPosition: event.position,
                localPosition: event.localPosition,
                delta: event.delta,
              );
              onPanUpdate!(details, size);
            },
            onPointerUp: (_) => onPanEnd!(),
            child: canvas,
          );
        }

        return Center(
          child: SizedBox(
            width: canvasWidth,
            height: canvasHeight,
            child: canvas,
          ),
        );
      },
    );
  }
}

class GeneratePage extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  const GeneratePage({super.key, this.onNavigate});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  late final GenerationViewModel _vm;
  late final ImagePicker _imagePicker;
  late final ScrollController _scrollController;
  int _promptSegmentIndex = 0; // 0: 正面, 1: 负面
  bool _isDrawingMask = false; // 手绘遮罩时禁用 ListView 滚动
  bool _isPreparingImg2Img = false;

  @override
  void initState() {
    super.initState();
    _imagePicker = ImagePicker();
    _scrollController = ScrollController();
    _vm = sl<GenerationViewModel>();

    // 我们不再直接使用 TextEditingController 以避免频繁重绘导致光标丢失。我们只传 initialValue 并在 onChanged 派发事件。
    // 但是 prompt 和 negative prompt 由于需要切换 Tab，如果频繁注销重建会导致光标和焦点丢失，所以这两个主输入框保留 controller
    _promptController.text = _vm.prompt;
    _negativeController.text = _vm.negativePrompt;
    _inpaintPromptController.text = _vm.inpaintPrompt;
    _inpaintNegativeController.text = _vm.inpaintNegativePrompt;
    _vm.addListener(_onVmChanged);
    _vm.loadModels();
    _loadSourceImageAspect();
  }

  Future<void> _loadSourceImageAspect() async {
    if (_vm.sourceImagePath != null &&
        File(_vm.sourceImagePath!).existsSync()) {
      final bytes = await File(_vm.sourceImagePath!).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null && mounted) {
        setState(() => _sourceImageAspect = image.width / image.height);
      }
    }
  }

  late final TextEditingController _promptController = TextEditingController();
  late final TextEditingController _negativeController =
      TextEditingController();
  late final TextEditingController _inpaintPromptController =
      TextEditingController();
  late final TextEditingController _inpaintNegativeController =
      TextEditingController();
  final GlobalKey _maskPreviewKey = GlobalKey();
  final GlobalKey _resultSectionKey = GlobalKey();
  int _knownResultCount = 0;
  String? _shownGenerationError;
  bool _wasGenerating = false;
  bool _userScrolledDuringGeneration = false;

  void _syncPromptControllers() {
    _promptController.text = _vm.prompt;
    _negativeController.text = _vm.negativePrompt;
    _inpaintPromptController.text = _vm.inpaintPrompt;
    _inpaintNegativeController.text = _vm.inpaintNegativePrompt;
  }

  void _onVmChanged() {
    if (_promptController.text != _vm.prompt &&
        FocusManager.instance.primaryFocus?.context?.widget is! EditableText) {
      _promptController.text = _vm.prompt;
    }
    if (_negativeController.text != _vm.negativePrompt &&
        FocusManager.instance.primaryFocus?.context?.widget is! EditableText) {
      _negativeController.text = _vm.negativePrompt;
    }
    if (_inpaintPromptController.text != _vm.inpaintPrompt &&
        FocusManager.instance.primaryFocus?.context?.widget is! EditableText) {
      _inpaintPromptController.text = _vm.inpaintPrompt;
    }
    if (_inpaintNegativeController.text != _vm.inpaintNegativePrompt &&
        FocusManager.instance.primaryFocus?.context?.widget is! EditableText) {
      _inpaintNegativeController.text = _vm.inpaintNegativePrompt;
    }

    final resultArrived = _vm.sessionResults.length > _knownResultCount;
    final generationStarted = _vm.isGenerating && !_wasGenerating;
    if (generationStarted) {
      _userScrolledDuringGeneration = false;
    }
    _knownResultCount = _vm.sessionResults.length;
    _wasGenerating = _vm.isGenerating;

    final error = _vm.errorMessage;
    if (error != null && error.isNotEmpty && error != _shownGenerationError) {
      _shownGenerationError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showFloatingToast(context, error);
      });
    } else if (error == null) {
      _shownGenerationError = null;
    }

    if (mounted) setState(() {});
    if (resultArrived && !_userScrolledDuringGeneration) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _revealLatestResult());
    }
  }

  Future<void> _revealLatestResult() async {
    if (!mounted || _userScrolledDuringGeneration) return;
    final resultContext = _resultSectionKey.currentContext;
    if (resultContext == null) return;
    await Scrollable.ensureVisible(
      resultContext,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  final List<_MaskStroke> _maskStrokes = [];
  final List<_MaskStroke> _maskErasedStrokes = []; // 橡皮擦笔迹
  final List<bool> _strokeHistory = []; // true=画笔, false=橡皮擦, 用于撤销
  List<Offset> _activeStroke = [];
  double _maskBrushSize = 28;
  double _sourceImageAspect = 1.0; // 原图宽高比
  bool _isFullscreenMask = false; // 全屏涂抹模式
  bool _isEraserMode = false; // 橡皮擦模式
  int _activePointers = 0; // 当前触摸点数（用于区分单指画笔/双指缩放）
  String? _toastMessage; // 悬浮提示消息
  bool _toastVisible = false;
  bool _isChatDrawerOpen = false;

  void _startMaskStroke(DragStartDetails details, Size size) {
    final point = details.localPosition;
    if (point.dx < 0 ||
        point.dy < 0 ||
        point.dx > size.width ||
        point.dy > size.height) return;
    final normalized = Offset(point.dx / size.width, point.dy / size.height);
    final normalizedBrush = _maskBrushSize / size.width;
    setState(() {
      _isDrawingMask = true;
      _activeStroke = [normalized];
      final stroke =
          _MaskStroke(points: _activeStroke, strokeWidth: normalizedBrush);
      if (_isEraserMode) {
        _maskErasedStrokes.add(stroke);
        _strokeHistory.add(false);
      } else {
        _maskStrokes.add(stroke);
        _strokeHistory.add(true);
      }
    });
  }

  void _updateMaskStroke(DragUpdateDetails details, Size size) {
    final point = details.localPosition;
    if (point.dx < 0 ||
        point.dy < 0 ||
        point.dx > size.width ||
        point.dy > size.height) return;
    if (_activeStroke.isEmpty) return;
    final normalized = Offset(point.dx / size.width, point.dy / size.height);
    setState(() {
      _activeStroke = [..._activeStroke, normalized];
      final stroke = _MaskStroke(
          points: _activeStroke, strokeWidth: _maskBrushSize / size.width);
      if (_isEraserMode) {
        _maskErasedStrokes[_maskErasedStrokes.length - 1] = stroke;
      } else {
        _maskStrokes[_maskStrokes.length - 1] = stroke;
      }
    });
  }

  void _endMaskStroke() {
    _activeStroke = [];
    setState(() => _isDrawingMask = false);
  }

  void _cancelActiveStroke() {
    // 多指触摸时取消当前正在画的笔画
    if (_maskStrokes.isNotEmpty || _maskErasedStrokes.isNotEmpty) {
      if (_isEraserMode) {
        _maskErasedStrokes.removeLast();
      } else {
        if (_maskStrokes.isNotEmpty) _maskStrokes.removeLast();
      }
      if (_strokeHistory.isNotEmpty) _strokeHistory.removeLast();
    }
    _activeStroke = [];
    setState(() => _isDrawingMask = false);
  }

  /// 弹选择器，返回写入目标：
  /// null = 用户取消
  /// -1  = 全局提示词
  /// 0~N = 角色索引（不存在的槽会自动创建）
  Future<int?> _showApplyTargetPicker({required bool isNegative}) async {
    final characters = _vm.characters;
    final maxSlots = 6;
    // 已有N个角色时，再多显示一个「新建」槽（上限6）
    final showSlots = characters.length < maxSlots
        ? characters.length + 1
        : characters.length;

    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          decoration: BoxDecoration(
            color: Color(0xFF1C1C21),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isNegative ? '写入负向提示词到…' : '写入正向提示词到…',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 12),
                ListTile(
                  leading: Icon(CupertinoIcons.globe),
                  title: Text('全局提示词'),
                  onTap: () => Navigator.of(ctx).pop(-1),
                ),
                Divider(height: 1),
                for (int i = 0; i < showSlots; i++)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: i >= characters.length
                          ? Theme.of(ctx)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.2)
                          : null,
                      child: Text('${i + 1}', style: TextStyle(fontSize: 12)),
                    ),
                    title: i >= characters.length
                        ? Text('角色 ${i + 1}（新建）',
                            style: TextStyle(
                                color: Theme.of(ctx).colorScheme.primary))
                        : Text(
                            characters[i].prompt.isEmpty
                                ? '角色 ${i + 1}（空）'
                                : '角色 ${i + 1}：${characters[i].prompt.length > 20 ? '${characters[i].prompt.substring(0, 20)}…' : characters[i].prompt}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => Navigator.of(ctx).pop(i),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 判断标注是否为角色标签
  static bool _isCharacterLabelStr(String label) {
    return label.contains('角色');
  }

  /// 判断标注是否为负向标签
  static bool _isNegativeLabelStr(String label) {
    return label.contains('负向') || label.contains('负面');
  }

  void _showToast(String message) {
    setState(() {
      _toastMessage = message;
      _toastVisible = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _toastVisible = false);
      }
    });
  }

  void _clearMaskStroke() {
    setState(() {
      _maskStrokes.clear();
      _maskErasedStrokes.clear();
      _strokeHistory.clear();
      _activeStroke = [];
    });
    _vm.setMaskImagePath(null);
  }

  /// 撤销最近一次笔迹（画笔或橡皮擦）
  void _undoLastStroke() {
    if (_strokeHistory.isEmpty) return;
    setState(() {
      final wasBrush = _strokeHistory.removeLast();
      if (wasBrush) {
        if (_maskStrokes.isNotEmpty) _maskStrokes.removeLast();
      } else {
        if (_maskErasedStrokes.isNotEmpty) _maskErasedStrokes.removeLast();
      }
    });
  }

  Future<void> _applyDrawnMask() async {
    if (_vm.sourceImagePath == null ||
        (_maskStrokes.isEmpty && _maskErasedStrokes.isEmpty)) {
      return;
    }

    // 用 image 包解码原图获取尺寸（比 ui.instantiateImageCodec 更轻量）
    final sourceFile = File(_vm.sourceImagePath!);
    final sourceBytes = await sourceFile.readAsBytes();
    final sourceImage = img.decodeImage(sourceBytes);
    if (sourceImage == null) return;
    final sourceWidth = sourceImage.width;
    final sourceHeight = sourceImage.height;

    // 直接生成与原图同尺寸的遮罩
    // NovelAI: 白色=重绘区域，黑色=保留区域
    // GPT / Nano Banana: 透明(alpha=0)=重绘区域，不透明(alpha=255)=保留区域
    final transparentMaskProvider = _vm.isGptProvider || _vm.isNanoProvider;

    final retainColor = img.ColorRgba8(0, 0, 0, 255);
    final repaintColor = transparentMaskProvider
        ? img.ColorRgba8(0, 0, 0, 0)
        : img.ColorRgba8(255, 255, 255, 255);

    final mask =
        img.Image(width: sourceWidth, height: sourceHeight, numChannels: 4);
    img.fill(mask, color: retainColor); // 初始全部保留区域

    // 画重绘区域——画笔笔迹
    for (final stroke in _maskStrokes) {
      if (stroke.points.isEmpty) continue;
      final pixelStrokeWidth = (stroke.strokeWidth * sourceWidth).round();

      if (stroke.points.length == 1) {
        final p = stroke.points.first;
        final cx = (p.dx * sourceWidth).round();
        final cy = (p.dy * sourceHeight).round();
        img.fillCircle(mask,
            x: cx, y: cy, radius: pixelStrokeWidth ~/ 2, color: repaintColor);
        continue;
      }

      for (int i = 0; i < stroke.points.length - 1; i++) {
        final p1 = stroke.points[i];
        final p2 = stroke.points[i + 1];
        final x1 = (p1.dx * sourceWidth).round();
        final y1 = (p1.dy * sourceHeight).round();
        final x2 = (p2.dx * sourceWidth).round();
        final y2 = (p2.dy * sourceHeight).round();
        img.drawLine(mask,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            color: repaintColor,
            thickness: pixelStrokeWidth);
      }
    }

    // 橡皮擦笔迹——恢复为保留区域
    for (final stroke in _maskErasedStrokes) {
      if (stroke.points.isEmpty) continue;
      final pixelStrokeWidth = (stroke.strokeWidth * sourceWidth).round();

      if (stroke.points.length == 1) {
        final p = stroke.points.first;
        final cx = (p.dx * sourceWidth).round();
        final cy = (p.dy * sourceHeight).round();
        img.fillCircle(mask,
            x: cx, y: cy, radius: pixelStrokeWidth ~/ 2, color: retainColor);
        continue;
      }

      for (int i = 0; i < stroke.points.length - 1; i++) {
        final p1 = stroke.points[i];
        final p2 = stroke.points[i + 1];
        final x1 = (p1.dx * sourceWidth).round();
        final y1 = (p1.dy * sourceHeight).round();
        final x2 = (p2.dx * sourceWidth).round();
        final y2 = (p2.dy * sourceHeight).round();
        img.drawLine(mask,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            color: retainColor,
            thickness: pixelStrokeWidth);
      }
    }

    final pngBytes = img.encodePng(mask);

    // 统计 mask 中白色像素数量
    int whitePixelCount = 0;
    for (int y = 0; y < mask.height; y++) {
      for (int x = 0; x < mask.width; x++) {
        final pixel = mask.getPixel(x, y);
        if (pixel.r == 255 && pixel.a == 255) {
          whitePixelCount++;
        }
      }
    }
    final totalPixels = mask.width * mask.height;
    print(
        '[NAI] mask: ${mask.width}x${mask.height}, white pixels: $whitePixelCount / $totalPixels (${(whitePixelCount / totalPixels * 100).toStringAsFixed(2)}%)');
    print('[NAI] mask PNG size: ${pngBytes.length} bytes');

    final dir = await Directory.systemTemp.createTemp('nai_mask_');
    final file = File('${dir.path}${Platform.pathSeparator}mask.png');
    await file.writeAsBytes(pngBytes, flush: true);
    _vm.setMaskImagePath(file.path);
    if (!mounted) return;
    _showToast('已生成手绘遮罩');
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _promptController.dispose();
    _negativeController.dispose();
    _inpaintPromptController.dispose();
    _inpaintNegativeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              title: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.sparkles, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '创作',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: _ChatFab(
                      onTap: () => setState(() => _isChatDrawerOpen = true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (_vm.isGenerating &&
                  notification is UserScrollNotification &&
                  notification.direction != ScrollDirection.idle) {
                _userScrolledDuringGeneration = true;
              }
              return false;
            },
            child: ListView(
              controller: _scrollController,
              physics:
                  _isDrawingMask ? const NeverScrollableScrollPhysics() : null,
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + kToolbarHeight + 16,
                bottom:
                    120 + MediaQuery.paddingOf(context).bottom, // 给底部悬浮栏留出空间
                left: 16,
                right: 16,
              ),
              children: [
                _buildModeSection(),
                SizedBox(height: 16),

                // 提示词区域
                _vm.generationMode == GenerationMode.inpainting
                    ? _buildInpaintPromptSection()
                    : _buildPromptSection(),
                SizedBox(height: 16),

                if (_vm.generationMode == GenerationMode.inpainting) ...[
                  _buildInpaintingSection(),
                  SizedBox(height: 16),
                ],

                // GPT / Nano 文生图参考图（可选）
                if (_vm.isNonNovelAiProvider &&
                    _vm.generationMode == GenerationMode.textToImage) ...[
                  _buildGptReferenceImageSection(),
                  SizedBox(height: 16),
                ],

                // 模型与基础参数
                _buildModelSection(),
                SizedBox(height: 16),

                if (!_vm.isNonNovelAiProvider &&
                    _vm.generationMode == GenerationMode.textToImage) ...[
                  // 角色控制
                  _CharacterControlSection(vm: _vm),
                  SizedBox(height: 16),
                  if (_vm.isIkunEndpoint) ...[
                    _CharacterReferenceSection(
                      vm: _vm,
                      onShowMessage: _showToast,
                    ),
                    SizedBox(height: 16),
                  ],
                ],

                // 最新结果卡片
                _buildResultSection(),
              ],
            ),
          ),

          // 悬浮底部生成栏
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingBottomBar(),
          ),

          // 全屏涂抹模式
          if (_isFullscreenMask && _vm.sourceImagePath != null)
            _buildFullscreenMaskEditor(),

          if (_isChatDrawerOpen)
            ChatDrawer(
              onClose: () => setState(() => _isChatDrawerOpen = false),
            ),

          // 悬浮提示
          if (_toastVisible && _toastMessage != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _toastVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Builder(
                    builder: (ctx) {
                      final isDark =
                          Theme.of(ctx).brightness == Brightness.dark;
                      final bgColor = isDark
                          ? Colors.black.withValues(alpha: 0.75)
                          : Colors.black.withValues(alpha: 0.72);
                      final borderColor = isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.12);
                      final textColor = Colors.white;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.checkmark_circle,
                                size: 18,
                                color: Theme.of(ctx).colorScheme.primary),
                            SizedBox(width: 8),
                            Text(
                              _toastMessage!,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: textColor,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFullscreenMaskEditor() {
    final screenSize = MediaQuery.sizeOf(context);
    final canvasW = screenSize.width;
    final canvasH = canvasW / _sourceImageAspect;
    final canvasSize = Size(canvasW, canvasH);
    final hasStrokes = _maskStrokes.isNotEmpty || _maskErasedStrokes.isNotEmpty;

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // 顶部工具栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() => _isFullscreenMask = false),
                    icon: Icon(CupertinoIcons.xmark_circle_fill,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 28),
                  ),
                  // 画笔/橡皮擦切换
                  SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => setState(() => _isEraserMode = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: !_isEraserMode
                            ? const Color(0xAAFF3333).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: !_isEraserMode
                              ? const Color(0xAAFF3333)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.paintbrush,
                              size: 14,
                              color: !_isEraserMode
                                  ? const Color(0xAAFF3333)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                          SizedBox(width: 4),
                          Text('画笔',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: !_isEraserMode
                                      ? const Color(0xAAFF3333)
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _isEraserMode = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isEraserMode
                            ? const Color(0xAA3399FF).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isEraserMode
                              ? const Color(0xAA3399FF)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.pencil_ellipsis_rectangle,
                              size: 14,
                              color: _isEraserMode
                                  ? const Color(0xAA3399FF)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                          SizedBox(width: 4),
                          Text('橡皮擦',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _isEraserMode
                                      ? const Color(0xAA3399FF)
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 撤销按钮
                  IconButton(
                    onPressed: hasStrokes ? _undoLastStroke : null,
                    icon: Icon(CupertinoIcons.arrow_uturn_left,
                        color: hasStrokes
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.25),
                        size: 20),
                  ),
                  IconButton(
                    onPressed: _clearMaskStroke,
                    icon: Icon(CupertinoIcons.trash,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20),
                  ),
                  SizedBox(width: 4),
                  FilledButton(
                    onPressed: hasStrokes
                        ? () async {
                            await _applyDrawnMask();
                            if (mounted)
                              setState(() => _isFullscreenMask = false);
                          }
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('应用遮罩'),
                  ),
                ],
              ),
            ),
            // 笔刷大小
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text('笔刷 ',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  for (final size in [8.0, 16.0, 28.0, 40.0, 60.0])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _maskBrushSize = size),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: (_maskBrushSize - size).abs() < 0.1
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (_maskBrushSize - size).abs() < 0.1
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: size / 3,
                              height: size / 3,
                              decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  shape: BoxShape.circle),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 可缩放的涂抹画布
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                constrained: false,
                panEnabled: _activePointers >= 2,
                scaleEnabled: _activePointers >= 2,
                child: SizedBox(
                  width: canvasW,
                  height: canvasH,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      _activePointers++;
                      if (_activePointers == 1) {
                        final details = DragStartDetails(
                          globalPosition: event.position,
                          localPosition: event.localPosition,
                        );
                        _startMaskStroke(details, canvasSize);
                      } else {
                        // 第二根手指按下，取消当前笔画，切换到缩放模式
                        _cancelActiveStroke();
                        setState(() {}); // 触发重建以更新 panEnabled/scaleEnabled
                      }
                    },
                    onPointerMove: (event) {
                      if (_activePointers == 1) {
                        final details = DragUpdateDetails(
                          globalPosition: event.position,
                          localPosition: event.localPosition,
                          delta: event.delta,
                        );
                        _updateMaskStroke(details, canvasSize);
                      }
                    },
                    onPointerUp: (event) {
                      if (_activePointers > 0) _activePointers--;
                      if (_activePointers == 0) {
                        _endMaskStroke();
                      } else {
                        setState(() {}); // 指针数变化，更新 panEnabled/scaleEnabled
                      }
                    },
                    onPointerCancel: (event) {
                      if (_activePointers > 0) _activePointers--;
                      setState(() {});
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_vm.sourceImagePath!),
                            fit: BoxFit.fill),
                        CustomPaint(
                          painter: _MaskPainter(
                              strokes: _maskStrokes,
                              preview: true,
                              erasedStrokes: _maskErasedStrokes),
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
  }

  Widget _buildModeSection() {
    // 局部重绘仅 NovelAI 和 GPT 可用
    final allowInpainting = !_vm.isNanoProvider;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: allowInpainting
          ? CupertinoSlidingSegmentedControl<GenerationMode>(
              groupValue: _vm.generationMode,
              backgroundColor: Colors.black.withValues(alpha: 0.2),
              thumbColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.8),
              children: {
                GenerationMode.textToImage: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Text(
                    '文生图',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _vm.generationMode == GenerationMode.textToImage
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                GenerationMode.inpainting: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Text(
                    '局部重绘',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _vm.generationMode == GenerationMode.inpainting
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              },
              onValueChanged: (value) {
                if (value != null) {
                  _vm.setGenerationMode(value);
                }
              },
            )
          : Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '文生图',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
    );
  }

  Widget _buildInpaintingSection() {
    final hasSourceImage =
        _vm.sourceImagePath != null && File(_vm.sourceImagePath!).existsSync();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('局部重绘',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(
            '选择原图，用手指涂抹需要重绘的区域（红色标记区域将被重绘）。',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5),
          ),
          SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _pickImage(isMask: false),
            icon: Icon(CupertinoIcons.photo, size: 16),
            label: Text(_vm.sourceImagePath == null ? '选择原图' : '更换原图'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          if (hasSourceImage) ...[
            SizedBox(height: 16),
            Row(
              children: [
                Text('手绘遮罩',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _isFullscreenMask = true),
                  icon: Icon(CupertinoIcons.fullscreen, size: 16),
                  label: Text('放大涂抹', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            SizedBox(height: 8),
            RepaintBoundary(
              key: _maskPreviewKey,
              child: _MaskEditor(
                imagePath: _vm.sourceImagePath!,
                strokes: _maskStrokes,
                erasedStrokes: _maskErasedStrokes,
                strokeWidth: _maskBrushSize,
                editable: false,
                aspectRatio: _sourceImageAspect,
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearMaskStroke,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('清空手绘'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        (_maskStrokes.isEmpty && _maskErasedStrokes.isEmpty)
                            ? null
                            : _applyDrawnMask,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('应用手绘遮罩'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Text('笔刷大小',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const Spacer(),
                for (final size in [8.0, 16.0, 28.0, 40.0, 60.0])
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _maskBrushSize = size),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: (_maskBrushSize - size).abs() < 0.1
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.2)
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (_maskBrushSize - size).abs() < 0.1
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: size / 3,
                            height: size / 3,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 16),
          ],
          _PremiumSlider(
            label: '重绘强度',
            value: _vm.inpaintStrength,
            min: 0.01,
            max: 1.0,
            divisions: 99,
            onChanged: _vm.updateInpaintStrength,
          ),
        ],
      ),
    );
  }

  Widget _buildGptReferenceImageSection() {
    final images = _vm.gptImagePaths;
    final canAdd = images.length < 16;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.photo_on_rectangle,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              SizedBox(width: 8),
              Text(
                '参考图（可选，${images.length}/16）',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (images.isNotEmpty)
                TextButton.icon(
                  onPressed: _vm.clearGptImages,
                  icon: Icon(CupertinoIcons.xmark_circle, size: 14),
                  label: Text('清空', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            '上传参考图后走图像编辑接口，提示词描述修改意图。最多16张。',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.5),
                height: 1.5),
          ),
          if (images.isNotEmpty) ...[
            SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(images[index]), fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _vm.removeGptImage(index),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(CupertinoIcons.xmark,
                              size: 12,
                              color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          SizedBox(height: 12),
          if (canAdd)
            OutlinedButton.icon(
              onPressed: () async {
                final file =
                    await _imagePicker.pickImage(source: ImageSource.gallery);
                if (file != null) _vm.addGptImage(file.path);
              },
              icon: Icon(CupertinoIcons.plus, size: 16),
              label: Text('添加参考图'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickImg2ImgSource() async {
    if (_isPreparingImg2Img) return;
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _isPreparingImg2Img = true);
    try {
      final path = await ImageUtils.normalizeImg2ImgSource(File(picked.path));
      if (!mounted) return;
      _vm.setImg2ImgSourceImagePath(path);
      final decoded = img.decodeImage(await File(path).readAsBytes());
      _showToast(decoded == null
          ? '源图已压缩'
          : '源图已压缩为 ${decoded.width}×${decoded.height}');
    } catch (error) {
      if (mounted) _showToast('图片处理失败：$error');
    } finally {
      if (mounted) setState(() => _isPreparingImg2Img = false);
    }
  }

  Future<void> _pickImage({required bool isMask}) async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    if (isMask) {
      _vm.setMaskImagePath(file.path);
    } else {
      _vm.setSourceImagePath(file.path);
      // 读取原图宽高比
      final bytes = await File(file.path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) {
        _sourceImageAspect = image.width / image.height;
      }
    }
  }

  Future<void> _openPromptCapsule({
    required bool isInpaint,
    required bool isNegative,
  }) async {
    final title = isInpaint
        ? (isNegative ? '灵感胶囊 · 重绘负面' : '灵感胶囊 · 重绘正面')
        : (isNegative ? '灵感胶囊 · 负面提示词' : '灵感胶囊 · 正面提示词');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PromptCapsuleSheet(
        title: title,
        onSelect: (tag) async {
          if (isNegative) {
            await _vm.appendToNegativePrompt(tag.promptText);
          } else {
            await _vm.appendToPrompt(tag.promptText);
          }
          if (!mounted) return;
          showFloatingToast(
            context,
            '已插入 ${tag.zh}',
            icon: CupertinoIcons.sparkles,
          );
        },
      ),
    );
  }

  Future<void> _openExpandedPromptEditor({
    required String title,
    required String initialValue,
    required Future<void> Function(String value) onSubmitted,
  }) async {
    final controller = TextEditingController(text: initialValue);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
            ),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(CupertinoIcons.xmark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: null,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: 15, height: 1.6),
                      decoration: const InputDecoration(
                        hintText: '请输入提示词...',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await onSubmitted(controller.text);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                      },
                      icon: const Icon(CupertinoIcons.check_mark),
                      label: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    controller.dispose();
  }

  Widget _buildPromptCapsuleButton({
    required bool isInpaint,
    required bool isNegative,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3),
          ),
        ),
        child: InkWell(
          onTap: () => _openPromptCapsule(
            isInpaint: isInpaint,
            isNegative: isNegative,
          ),
          borderRadius: BorderRadius.circular(14),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.sparkles, size: 16),
                SizedBox(width: 8),
                Text('灵感胶囊'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptField({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
    required Color textColor,
    required String editorTitle,
    required Future<void> Function(String value) onExpandedSubmit,
  }) {
    return Stack(
      children: [
        TextField(
          controller: controller,
          minLines: 7,
          maxLines: 14,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: textColor,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.55),
            ),
            fillColor: Colors.transparent,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.only(right: 36),
          ),
          onChanged: onChanged,
        ),
        Positioned(
          top: 0,
          right: -4,
          child: IconButton(
            onPressed: () => _openExpandedPromptEditor(
              title: editorTitle,
              initialValue: controller.text,
              onSubmitted: onExpandedSubmit,
            ),
            tooltip: '放大编辑',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              CupertinoIcons.arrow_up_left_arrow_down_right,
              size: 15,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPromptSection() {
    if (_vm.isNonNovelAiProvider) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.08), width: 0.5),
        ),
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _promptController,
          minLines: 7,
          maxLines: 14,
          style: TextStyle(fontSize: 14, height: 1.5),
          decoration: InputDecoration(
            hintText: '描述你想要的画面...',
            hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.55)),
            fillColor: Colors.transparent,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: _vm.updatePrompt,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _promptSegmentIndex,
              backgroundColor: Colors.black.withValues(alpha: 0.2),
              thumbColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.8),
              children: {
                0: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '正面提示词',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _promptSegmentIndex == 0
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                1: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '负面提示词',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _promptSegmentIndex == 1
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              },
              onValueChanged: (v) {
                if (v != null) setState(() => _promptSegmentIndex = v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: IndexedStack(
              index: _promptSegmentIndex,
              children: [
                _buildPromptField(
                  controller: _promptController,
                  hintText: '描述你想要的画面...',
                  onChanged: _vm.updatePrompt,
                  textColor: Theme.of(context).colorScheme.onSurface,
                  editorTitle: '编辑正面提示词',
                  onExpandedSubmit: _vm.updatePrompt,
                ),
                _buildPromptField(
                  controller: _negativeController,
                  hintText: '描述你不想要的画面...',
                  onChanged: _vm.updateNegativePrompt,
                  textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  editorTitle: '编辑负面提示词',
                  onExpandedSubmit: _vm.updateNegativePrompt,
                ),
              ],
            ),
          ),
          _buildPromptCapsuleButton(
            isInpaint: false,
            isNegative: _promptSegmentIndex == 1,
          ),
        ],
      ),
    );
  }

  int _inpaintPromptSegmentIndex = 0;

  Widget _buildInpaintPromptSection() {
    if (_vm.isNonNovelAiProvider) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.08), width: 0.5),
        ),
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _inpaintPromptController,
          minLines: 7,
          maxLines: 14,
          style: TextStyle(fontSize: 14, height: 1.5),
          decoration: InputDecoration(
            hintText: '描述编辑后想要的画面...',
            hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.55)),
            fillColor: Colors.transparent,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: _vm.updateInpaintPrompt,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(CupertinoIcons.paintbrush,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                SizedBox(width: 8),
                Text('重绘提示词',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _inpaintPromptSegmentIndex,
              backgroundColor: Colors.black.withValues(alpha: 0.2),
              thumbColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.8),
              children: {
                0: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '正面提示词',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _inpaintPromptSegmentIndex == 0
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                1: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '负面提示词',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _inpaintPromptSegmentIndex == 1
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              },
              onValueChanged: (v) {
                if (v != null) setState(() => _inpaintPromptSegmentIndex = v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: IndexedStack(
              index: _inpaintPromptSegmentIndex,
              children: [
                _buildPromptField(
                  controller: _inpaintPromptController,
                  hintText: '描述重绘区域想要的画面...',
                  onChanged: _vm.updateInpaintPrompt,
                  textColor: Theme.of(context).colorScheme.onSurface,
                  editorTitle: '编辑重绘正面提示词',
                  onExpandedSubmit: _vm.updateInpaintPrompt,
                ),
                _buildPromptField(
                  controller: _inpaintNegativeController,
                  hintText: '描述重绘区域不想要的画面...',
                  onChanged: _vm.updateInpaintNegativePrompt,
                  textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  editorTitle: '编辑重绘负面提示词',
                  onExpandedSubmit: _vm.updateInpaintNegativePrompt,
                ),
              ],
            ),
          ),
          _buildPromptCapsuleButton(
            isInpaint: true,
            isNegative: _inpaintPromptSegmentIndex == 1,
          ),
        ],
      ),
    );
  }

  BoxDecoration _selectBoxDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFFD8E3F3),
        width: 1,
      ),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: const Color(0xFF94A3B8).withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
    );
  }

  Color _dropdownColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1C1C21)
        : Colors.white;
  }

  TextStyle _dropdownTextStyle(BuildContext context) {
    return TextStyle(
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  Widget _dropdownShell({required Widget child}) {
    return Container(
      decoration: _selectBoxDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    );
  }

  Widget _buildImg2ImgSourceField() {
    final path = _vm.img2imgSourceImagePath;
    final file = path == null ? null : File(path);
    final hasImage = file?.existsSync() ?? false;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('图生图源图',
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: hasImage
              ? Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(file!,
                          width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('已启用图生图',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('已自动压缩至 1M 像素以内并按 64px 对齐',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            children: [
                              TextButton(
                                onPressed: _isPreparingImg2Img
                                    ? null
                                    : _pickImg2ImgSource,
                                child: const Text('替换'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _vm.setImg2ImgSourceImagePath(null),
                                child: const Text('移除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : OutlinedButton.icon(
                  onPressed: _isPreparingImg2Img ? null : _pickImg2ImgSource,
                  icon: _isPreparingImg2Img
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.photo_on_rectangle, size: 17),
                  label: Text(_isPreparingImg2Img ? '正在压缩图片…' : '上传图生图源图'),
                ),
        ),
        if (hasImage) ...[
          const SizedBox(height: 12),
          _PremiumSlider(
            label: '图生图强度',
            value: _vm.img2imgStrength,
            min: 0.01,
            max: 1.0,
            divisions: 99,
            onChanged: _vm.updateImg2ImgStrength,
          ),
          Text('数值越高，生成结果越偏离原图。',
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }

  Widget _buildModelSection() {
    return _PremiumAccordion(
      title: '模型与基础参数',
      icon: CupertinoIcons.cube_box,
      initiallyExpanded: true,
      children: [
        Text('AI 模型',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        SizedBox(height: 8),
        _dropdownShell(
          child: Builder(
            builder: (context) {
              final uniqueOptions = <String, ImageModelOption>{};
              for (final opt in _vm.imageModelOptions) {
                uniqueOptions.putIfAbsent(opt.modelId, () => opt);
              }
              final modelOptions = uniqueOptions.values.toList();
              final modelIds = modelOptions.map((opt) => opt.modelId).toList();
              final selectedModel = modelIds.contains(_vm.selectedModel)
                  ? _vm.selectedModel
                  : (modelIds.isNotEmpty ? modelIds.first : null);

              return DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(22),
                  value: selectedModel,
                  icon: Icon(CupertinoIcons.chevron_down, size: 16),
                  dropdownColor: _dropdownColor(context),
                  style: _dropdownTextStyle(context),
                  items: modelOptions.map((opt) {
                    String tag;
                    switch (opt.provider) {
                      case ImageProviderType.gpt:
                        tag = '[GPT] ';
                      case ImageProviderType.nanoBanana:
                        tag = '[Nano] ';
                      case ImageProviderType.novelAi:
                        tag = '';
                    }
                    final epName = (opt.endpointName != null &&
                            opt.endpointName!.isNotEmpty)
                        ? '[${opt.endpointName}] '
                        : '';
                    return DropdownMenuItem(
                      value: opt.modelId,
                      child: Text('$tag$epName${opt.displayName}',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) _vm.updateSelectedModel(v);
                  },
                ),
              );
            },
          ),
        ),
        SizedBox(height: 20),
        Row(
          children: [
            Text('图像尺寸',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text(_vm.selectedResolution,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: 8),
        _dropdownShell(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              borderRadius: BorderRadius.circular(22),
              value: _vm.selectedResolution,
              icon: Icon(CupertinoIcons.chevron_down, size: 16),
              dropdownColor: _dropdownColor(context),
              style: _dropdownTextStyle(context),
              items: _vm.availableResolutions
                  .map((r) => DropdownMenuItem(
                      value: r, child: Text(_vm.resolutionLabel(r))))
                  .toList(),
              onChanged: (v) {
                if (v != null) _vm.updateSelectedResolution(v);
              },
            ),
          ),
        ),
        if (_vm.isNanoProvider) ...[
          SizedBox(height: 16),
          Row(
            children: [
              Text('图片质量',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text(_vm.selectedNanoImageSize,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          _dropdownShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                borderRadius: BorderRadius.circular(22),
                value: _vm.selectedNanoImageSize,
                icon: Icon(CupertinoIcons.chevron_down, size: 16),
                dropdownColor: _dropdownColor(context),
                style: _dropdownTextStyle(context),
                items: ApiConstants.nanoImageSizes
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(_vm.nanoImageSizeLabel(s))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) _vm.updateSelectedNanoImageSize(v);
                },
              ),
            ),
          ),
        ],
        if ((_vm.is7877Endpoint || _vm.isIkunEndpoint) &&
            _vm.generationMode == GenerationMode.textToImage) ...[
          SizedBox(height: 20),
          _buildImg2ImgSourceField(),
        ],
        if (_vm.is7877Endpoint)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '7877 渠道固定 28 步，仅支持普通尺寸；高级参数请从左上角进入。',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        SizedBox(height: 20),
        Row(
          children: [
            Text('批量生成',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text(
              '${_vm.batchCount} 张',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.black.withValues(alpha: 0.3),
            thumbColor: Colors.white,
            overlayColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: _vm.batchCount.toDouble().clamp(1.0, 15.0),
            min: 1,
            max: 15,
            divisions: 14,
            onChanged: _vm.isGenerating
                ? null
                : (v) => _vm.updateBatchCount(v.round()),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            '同一组提示词连续出图，每张间隔 1 秒',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildResultSection() {
    final displayTask = _vm.selectedResult ?? _vm.lastCompletedTask;
    if (displayTask == null && _vm.errorMessage == null)
      return const SizedBox.shrink();

    final results = _vm.sessionResults;
    final showStrip = results.length > 1;
    final headerLabel =
        results.length > 1 ? '本次结果 (${results.length})' : '最新结果';

    return KeyedSubtree(
      key: _resultSectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(headerLabel,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08), width: 0.5),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_vm.errorMessage != null)
                  Text(_vm.errorMessage!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13))
                else if (displayTask != null) ...[
                  if (displayTask.imagePath != null &&
                      File(displayTask.imagePath!).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: GestureDetector(
                        onTap: () => _openImagePreview(
                          context,
                          imagePath: displayTask.imagePath,
                          imageUrl: displayTask.imageUrl,
                        ),
                        child: Image.file(File(displayTask.imagePath!),
                            fit: BoxFit.cover),
                      ),
                    )
                  else if (displayTask.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: GestureDetector(
                        onTap: () => _openImagePreview(
                          context,
                          imagePath: displayTask.imagePath,
                          imageUrl: displayTask.imageUrl,
                        ),
                        child: Image.network(displayTask.imageUrl!,
                            fit: BoxFit.cover),
                      ),
                    ),
                  if (showStrip) ...[
                    SizedBox(height: 12),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final t = results[index];
                          final isSelected = t.taskId ==
                              (_vm.selectedResultTaskId ??
                                  _vm.lastCompletedTask?.taskId);
                          Widget thumb;
                          if (t.imagePath != null &&
                              File(t.imagePath!).existsSync()) {
                            thumb = Image.file(File(t.imagePath!),
                                fit: BoxFit.cover, width: 64, height: 64);
                          } else if (t.imageUrl != null) {
                            thumb = Image.network(t.imageUrl!,
                                fit: BoxFit.cover, width: 64, height: 64);
                          } else {
                            thumb = Container(
                              width: 64,
                              height: 64,
                              color: Colors.black26,
                              child: Icon(CupertinoIcons.photo,
                                  size: 24,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.25)),
                            );
                          }
                          return GestureDetector(
                            onTap: () => _vm.selectResult(t.taskId),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white.withValues(alpha: 0.15),
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.35),
                                          blurRadius: 10,
                                          spreadRadius: 0,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    thumb,
                                    Positioned(
                                      right: 2,
                                      bottom: 2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  SizedBox(height: 16),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final filePath = await _vm.saveImage(displayTask);
                        if (!context.mounted || filePath == null) return;
                        _showToast('已保存到相册');
                      },
                      icon: Icon(CupertinoIcons.square_arrow_down, size: 18),
                      label: Text('保存到相册',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.3),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openImagePreview(BuildContext context,
      {String? imagePath, String? imageUrl}) {
    showFullscreenImagePreview(
      context,
      imagePath: imagePath,
      imageUrl: imageUrl,
    );
  }

  Widget _buildFloatingBottomBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final barColor = isDark
        ? const Color(0xFF0A0A0C).withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.82);
    final barBorder = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFBBD7FF).withValues(alpha: 0.9);
    final idleButtonColors = isDark
        ? [const Color(0xFFF5D57A), const Color(0xFFD4A373)]
        : [const Color(0xFF60A5FA), const Color(0xFF2563EB)];
    final buttonTextColor = isDark ? Colors.black87 : Colors.white;
    final navIconColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: barColor,
            border: Border(top: BorderSide(color: barBorder, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                if (widget.onNavigate != null) ...[
                  IconButton(
                    icon: Icon(CupertinoIcons.clock, color: navIconColor),
                    onPressed: () => widget.onNavigate!(0),
                  ),
                  SizedBox(width: 8),
                ],
                Expanded(
                  child: GestureDetector(
                    onTap: _vm.isGenerating
                        ? () => _vm.cancelBatch()
                        : () => _vm.generate(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _vm.isGenerating
                              ? [
                                  primary.withValues(alpha: 0.28),
                                  primary.withValues(alpha: 0.16)
                                ]
                              : idleButtonColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: _vm.isGenerating
                            ? null
                            : [
                                BoxShadow(
                                  color: primary.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                      ),
                      child: Center(
                        child: _vm.isGenerating
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface)),
                                  SizedBox(width: 12),
                                  Text(
                                    _vm.isBatchCancelling
                                        ? '取消中…'
                                        : (_vm.batchCount > 1
                                            ? '取消生成 ${(_vm.batchCount - _vm.batchRemaining + 1).clamp(1, _vm.batchCount)}/${_vm.batchCount}'
                                            : '取消生成'),
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.wand_rays,
                                      color: buttonTextColor, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Generate',
                                    style: TextStyle(
                                      color: buttonTextColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  if (_vm.pendingCount > 0) ...[
                                    SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                            alpha: isDark ? 0.2 : 0.16),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${_vm.pendingCount} in queue',
                                        style: TextStyle(
                                            color: buttonTextColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                if (widget.onNavigate != null) ...[
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(CupertinoIcons.settings, color: navIconColor),
                    onPressed: () => widget.onNavigate!(2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumAccordion extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _PremiumAccordion({
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<_PremiumAccordion> createState() => _PremiumAccordionState();
}

class _PremiumAccordionState extends State<_PremiumAccordion>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this);
    _iconTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic));
    if (_isExpanded) _controller.value = 1.0;
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(widget.icon,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(CupertinoIcons.chevron_down,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }
}

class _PremiumSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _PremiumSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text(value.toStringAsFixed(2),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.black.withValues(alpha: 0.3),
            thumbColor: Colors.white,
            overlayColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            showValueIndicator: ShowValueIndicator.never, // 移除丑陋气泡
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _CharacterReferenceSection extends StatefulWidget {
  final GenerationViewModel vm;
  final ValueChanged<String> onShowMessage;

  const _CharacterReferenceSection({
    required this.vm,
    required this.onShowMessage,
  });

  @override
  State<_CharacterReferenceSection> createState() =>
      _CharacterReferenceSectionState();
}

class _CharacterReferenceSectionState
    extends State<_CharacterReferenceSection> {
  int _mode = 0;

  GenerationViewModel get vm => widget.vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumAccordion(
      title: '氛围转移与精密参照图像',
      icon: CupertinoIcons.photo_on_rectangle,
      initiallyExpanded: false,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('氛围转移'),
              icon: Icon(CupertinoIcons.photo),
            ),
            ButtonSegment(
              value: 1,
              label: Text('精密参照图像'),
              icon: Icon(CupertinoIcons.person_crop_rectangle),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (value) => setState(() => _mode = value.first),
        ),
        const SizedBox(height: 14),
        if (_mode == 0) ...[
          Text(
            '最多使用一张全局参考图，影响整张图的画风与视觉特征。添加后会清除精密参照图像。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final image =
                  await ImagePicker().pickImage(source: ImageSource.gallery);
              if (image == null) return;
              final cleared = vm.preciseReferences.isNotEmpty;
              await vm.setVibeReference(image.path);
              if (cleared) widget.onShowMessage('已切换为氛围转移并清除精密参照图像');
            },
            icon: Icon(
              vm.vibeReferences.isEmpty
                  ? CupertinoIcons.photo
                  : CupertinoIcons.arrow_2_circlepath,
              size: 17,
            ),
            label: Text(
              vm.vibeReferences.isEmpty ? '选择氛围参考图' : '替换氛围参考图',
            ),
          ),
          if (vm.vibeReferences.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _ReferenceImageCard(
                image: vm.vibeReferences.first,
                onReplace: () async {
                  final picked = await ImagePicker()
                      .pickImage(source: ImageSource.gallery);
                  if (picked != null) await vm.setVibeReference(picked.path);
                },
                onUpdate: vm.updateVibeReference,
                onDelete: vm.removeVibeReference,
              ),
            ),
        ] else ...[
          Row(
            children: [
              Icon(CupertinoIcons.photo_on_rectangle,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('精密参照图像',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      '使用特定图像精密控制生成结果',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '导入参照图像',
                onPressed: _addPreciseReference,
                icon: const Icon(CupertinoIcons.arrow_up_square, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '参照图与角色卡相互独立，支持 NovelAI V4/V4.5（不含 -limit）；每张参考图、每个样本加 5 Anlas。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final entry in vm.preciseReferences.asMap().entries)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _PreciseReferenceCard(
                image: entry.value,
                onReplace: () => _replacePreciseReference(entry.key),
                onUpdate: (reference) =>
                    vm.updatePreciseReference(entry.key, reference),
                onDelete: () => vm.removePreciseReference(entry.key),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _addPreciseReference() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final clearedVibe = vm.vibeReferences.isNotEmpty;
    await vm.addPreciseReference(picked.path);
    if (clearedVibe) widget.onShowMessage('已切换为精密参照图像并清除氛围图');
  }

  Future<void> _replacePreciseReference(int index) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) await vm.replacePreciseReference(index, picked.path);
  }
}

String _characterLabel(int index, CharacterSpec character) {
  final prompt = character.prompt.trim();
  if (prompt.isEmpty) return '角色 ${index + 1}';
  final summary = prompt.length > 18 ? '${prompt.substring(0, 18)}…' : prompt;
  return '角色 ${index + 1} · $summary';
}

class _ReferenceImageCard extends StatelessWidget {
  final CharacterReferenceImage image;
  final VoidCallback onReplace;
  final ValueChanged<CharacterReferenceImage> onUpdate;
  final VoidCallback onDelete;

  const _ReferenceImageCard({
    required this.image,
    required this.onReplace,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onReplace,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(image.path),
                    width: 82,
                    height: 108,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 82,
                      height: 108,
                      color: theme.colorScheme.errorContainer,
                      child: Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _ReferenceSlider(
                      label: '参考强度',
                      value: image.strength,
                      onChanged: (value) =>
                          onUpdate(image.copyWith(strength: value)),
                    ),
                    _ReferenceSlider(
                      label: '信息提取',
                      value: image.informationExtracted,
                      onChanged: (value) => onUpdate(
                        image.copyWith(informationExtracted: value),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: onReplace,
                          icon: const Icon(CupertinoIcons.arrow_2_circlepath,
                              size: 15),
                          label: const Text('替换'),
                        ),
                        IconButton(
                          tooltip: '删除参考图',
                          onPressed: onDelete,
                          icon: const Icon(CupertinoIcons.trash, size: 17),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreciseReferenceCard extends StatelessWidget {
  final PreciseReferenceImage image;
  final VoidCallback onReplace;
  final ValueChanged<PreciseReferenceImage> onUpdate;
  final VoidCallback onDelete;

  const _PreciseReferenceCard({
    required this.image,
    required this.onReplace,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: '删除参照图像',
                onPressed: onDelete,
                icon: const Icon(CupertinoIcons.trash, size: 17),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('有效', style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(width: 6),
                    Icon(CupertinoIcons.check_mark, size: 16),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: image.referenceType,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(
                      value: 'character&style',
                      child: Text('角色与画风'),
                    ),
                    DropdownMenuItem(
                      value: 'character',
                      child: Text('角色'),
                    ),
                    DropdownMenuItem(
                      value: 'style',
                      child: Text('画风'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onUpdate(image.copyWith(referenceType: value));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onReplace,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(image.path),
                    width: 106,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 106,
                      height: 160,
                      color: theme.colorScheme.errorContainer,
                      child: Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    _PreciseReferenceSlider(
                      label: '强度',
                      value: image.strength,
                      onChanged: (value) =>
                          onUpdate(image.copyWith(strength: value)),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '忠实度固定为 1.0，请通过强度调节参考效果。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onReplace,
                        icon: const Icon(CupertinoIcons.arrow_2_circlepath,
                            size: 15),
                        label: const Text('替换图片'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreciseReferenceSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _PreciseReferenceSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$label: ${value.toStringAsFixed(1)}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(
            value: value.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            onChanged: onChanged,
          ),
        ],
      );
}

class _ReferenceSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _ReferenceSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
}

class _CharacterControlSection extends StatefulWidget {
  final GenerationViewModel vm;

  const _CharacterControlSection({required this.vm});

  @override
  State<_CharacterControlSection> createState() =>
      _CharacterControlSectionState();
}

class _CharacterControlSectionState extends State<_CharacterControlSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _controller;
  late Animation<double> _iconTurns;
  final Set<int> _expandedCards = {};
  bool _autoPositionDefault = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this);
    _iconTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic));
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final characters = widget.vm.characters;
    final enabledCount = characters.where((c) => c.enabled).length;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(CupertinoIcons.person_3,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: 12),
                  const Expanded(
                    child: Text('角色控制',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  if (enabledCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$enabledCount',
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold)),
                    ),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(CupertinoIcons.chevron_down,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '精确定义图像中人物的外观、表情和姿势，最多支持 6 个角色。',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.5),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: characters.length >= 6
                              ? null
                              : () {
                                  widget.vm.addCharacter();
                                  final newIndex =
                                      widget.vm.characters.length - 1;
                                  if (_autoPositionDefault)
                                    widget.vm
                                        .setCharacterPositionAuto(newIndex);
                                  setState(() => _expandedCards.add(newIndex));
                                },
                          icon: Icon(CupertinoIcons.add, size: 16),
                          label: Text('添加角色'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                            side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.45)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => setState(
                            () => _autoPositionDefault = !_autoPositionDefault),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _autoPositionDefault
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.2)
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _autoPositionDefault
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.5)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                  _autoPositionDefault
                                      ? CupertinoIcons.checkmark_square_fill
                                      : CupertinoIcons.square,
                                  size: 16,
                                  color: _autoPositionDefault
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                              SizedBox(width: 6),
                              Text('AI位置',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: _autoPositionDefault
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  if (characters.isNotEmpty)
                    for (final entry in characters.asMap().entries)
                      _CharacterCard(
                        key: ValueKey('character_${entry.key}'),
                        index: entry.key,
                        character: entry.value,
                        expanded: _expandedCards.contains(entry.key),
                        onToggleExpanded: () {
                          setState(() {
                            if (_expandedCards.contains(entry.key)) {
                              _expandedCards.remove(entry.key);
                            } else {
                              _expandedCards.add(entry.key);
                            }
                          });
                        },
                        onMoveUp: entry.key == 0
                            ? null
                            : () => widget.vm.moveCharacterUp(entry.key),
                        onMoveDown: entry.key == characters.length - 1
                            ? null
                            : () => widget.vm.moveCharacterDown(entry.key),
                        onToggleEnabled: () =>
                            widget.vm.toggleCharacterEnabled(entry.key),
                        onDelete: () {
                          widget.vm.removeCharacter(entry.key);
                          setState(() => _expandedCards.remove(entry.key));
                        },
                        onChanged: (character) =>
                            widget.vm.updateCharacter(entry.key, character),
                        onAutoPosition: () =>
                            widget.vm.setCharacterPositionAuto(entry.key),
                        onGridPosition: (row, col) => widget.vm
                            .setCharacterGridPosition(entry.key, row, col),
                        onOpenExpandedEditor: ({
                          required title,
                          required initialValue,
                          required onSubmitted,
                        }) =>
                            showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (ctx) {
                            final controller = TextEditingController(
                              text: initialValue,
                            );
                            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
                            final theme = Theme.of(ctx);
                            return Padding(
                              padding: EdgeInsets.only(bottom: bottom),
                              child: Container(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.sizeOf(ctx).height * 0.88,
                                ),
                                margin:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                padding:
                                    const EdgeInsets.fromLTRB(18, 12, 18, 18),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.08),
                                  ),
                                ),
                                child: SafeArea(
                                  top: false,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.35),
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    theme.colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                            icon: const Icon(
                                                CupertinoIcons.xmark),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: controller,
                                          autofocus: true,
                                          minLines: null,
                                          maxLines: null,
                                          expands: true,
                                          textAlignVertical:
                                              TextAlignVertical.top,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            height: 1.6,
                                          ),
                                          decoration: const InputDecoration(
                                            hintText: '请输入提示词...',
                                            alignLabelWithHint: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: () async {
                                            await onSubmitted(controller.text);
                                            if (!ctx.mounted) return;
                                            Navigator.of(ctx).pop();
                                          },
                                          icon: const Icon(
                                            CupertinoIcons.check_mark,
                                          ),
                                          label: const Text('完成'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }
}

class _CharacterCard extends StatefulWidget {
  final int index;
  final CharacterSpec character;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onToggleEnabled;
  final VoidCallback onDelete;
  final ValueChanged<CharacterSpec> onChanged;
  final VoidCallback onAutoPosition;
  final void Function(int row, int col) onGridPosition;
  final Future<void> Function({
    required String title,
    required String initialValue,
    required Future<void> Function(String value) onSubmitted,
  }) onOpenExpandedEditor;

  const _CharacterCard({
    super.key,
    required this.index,
    required this.character,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleEnabled,
    required this.onDelete,
    required this.onChanged,
    required this.onAutoPosition,
    required this.onGridPosition,
    required this.onOpenExpandedEditor,
  });

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  int _tabIndex = 0;
  late final TextEditingController _promptController;
  late final TextEditingController _ucController;
  late final FocusNode _promptFocusNode;
  late final FocusNode _ucFocusNode;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.character.prompt);
    _ucController = TextEditingController(text: widget.character.uc ?? '');
    _promptFocusNode = FocusNode();
    _ucFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _CharacterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_promptFocusNode.hasFocus &&
        _promptController.text != widget.character.prompt) {
      _promptController.text = widget.character.prompt;
    }
    final uc = widget.character.uc ?? '';
    if (!_ucFocusNode.hasFocus && _ucController.text != uc) {
      _ucController.text = uc;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _ucController.dispose();
    _promptFocusNode.dispose();
    _ucFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positionLabel =
        _positionLabel(widget.character.centerX, widget.character.centerY);
    final bool isEnabled = widget.character.enabled;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.3)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isEnabled
              ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEnabled
                            ? theme.colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.25),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '未命名角色',
                            style: TextStyle(
                              color: isEnabled
                                  ? theme.colorScheme.onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            positionLabel == null
                                ? 'AI决定位置'
                                : '位置 $positionLabel',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onToggleEnabled,
                      icon: Icon(
                          isEnabled
                              ? CupertinoIcons.eye
                              : CupertinoIcons.eye_slash,
                          size: 18),
                      color: isEnabled
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.35),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      onPressed: widget.onDelete,
                      icon: Icon(CupertinoIcons.trash, size: 18),
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.35),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    Icon(
                        widget.expanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 16,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.35)),
                    SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              children: [
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _buildTabButton(0, 'Prompt'),
                      SizedBox(width: 8),
                      _buildTabButton(1, 'UContent'),
                      SizedBox(width: 8),
                      _buildTabButton(2, 'Pos'),
                      SizedBox(width: 8),
                      _buildTabButton(3, 'Ref'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: IndexedStack(
                    index: _tabIndex,
                    children: [
                      Stack(
                        children: [
                          TextField(
                            controller: _promptController,
                            focusNode: _promptFocusNode,
                            minLines: 6,
                            maxLines: 8,
                            style: TextStyle(fontSize: 13, height: 1.5),
                            decoration: InputDecoration(
                              hintText: '描述该角色的外观...',
                              hintStyle: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.55)),
                              filled: true,
                              fillColor: Colors.black.withValues(alpha: 0.2),
                              contentPadding:
                                  const EdgeInsets.fromLTRB(12, 12, 36, 12),
                            ),
                            onChanged: (value) => widget.onChanged(
                                widget.character.copyWith(prompt: value)),
                          ),
                          Positioned(
                            top: 2,
                            right: -4,
                            child: IconButton(
                              onPressed: () => widget.onOpenExpandedEditor(
                                title: '编辑角色 ${widget.index + 1} Prompt',
                                initialValue: _promptController.text,
                                onSubmitted: (value) async {
                                  widget.onChanged(
                                    widget.character.copyWith(prompt: value),
                                  );
                                },
                              ),
                              tooltip: '放大编辑',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                              icon: Icon(
                                CupertinoIcons.arrow_up_left_arrow_down_right,
                                size: 15,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Stack(
                        children: [
                          TextField(
                            controller: _ucController,
                            focusNode: _ucFocusNode,
                            minLines: 6,
                            maxLines: 8,
                            style: TextStyle(fontSize: 13, height: 1.5),
                            decoration: InputDecoration(
                              hintText: '描述该角色不需要的特征...',
                              hintStyle: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.55)),
                              filled: true,
                              fillColor: Colors.black.withValues(alpha: 0.2),
                              contentPadding:
                                  const EdgeInsets.fromLTRB(12, 12, 36, 12),
                            ),
                            onChanged: (value) =>
                                widget.onChanged(widget.character.copyWith(
                              uc: value.isEmpty ? null : value,
                              clearUc: value.isEmpty,
                            )),
                          ),
                          Positioned(
                            top: 2,
                            right: -4,
                            child: IconButton(
                              onPressed: () => widget.onOpenExpandedEditor(
                                title: '编辑角色 ${widget.index + 1} UContent',
                                initialValue: _ucController.text,
                                onSubmitted: (value) async {
                                  widget.onChanged(widget.character.copyWith(
                                    uc: value.isEmpty ? null : value,
                                    clearUc: value.isEmpty,
                                  ));
                                },
                              ),
                              tooltip: '放大编辑',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                              icon: Icon(
                                CupertinoIcons.arrow_up_left_arrow_down_right,
                                size: 15,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ],
                      ),
                      _CharacterPositionGrid(
                        centerX: widget.character.centerX,
                        centerY: widget.character.centerY,
                        onAutoPosition: widget.onAutoPosition,
                        onGridPosition: widget.onGridPosition,
                      ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.black.withValues(alpha: 0.1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('排序',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      const Spacer(),
                      IconButton(
                        onPressed: widget.onMoveUp,
                        icon: Icon(CupertinoIcons.arrow_up, size: 16),
                        color: widget.onMoveUp == null
                            ? Colors.white12
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      IconButton(
                        onPressed: widget.onMoveDown,
                        icon: Icon(CupertinoIcons.arrow_down, size: 16),
                        color: widget.onMoveDown == null
                            ? Colors.white12
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                )
              ],
            ),
            crossFadeState: widget.expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isSelected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterPositionGrid extends StatelessWidget {
  final double? centerX;
  final double? centerY;
  final VoidCallback onAutoPosition;
  final void Function(int row, int col) onGridPosition;

  const _CharacterPositionGrid({
    required this.centerX,
    required this.centerY,
    required this.onAutoPosition,
    required this.onGridPosition,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _positionIndex(centerX, centerY);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: onAutoPosition,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected == null
                  ? theme.colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected == null
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : Colors.transparent),
            ),
            child: Center(
              child: Text('AI决定位置',
                  style: TextStyle(
                    color: selected == null
                        ? theme.colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  )),
            ),
          ),
        ),
        SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(width: 30),
                  for (final col in ['A', 'B', 'C', 'D', 'E'])
                    Expanded(
                        child: Center(
                            child: Text(col,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)))),
                ],
              ),
              SizedBox(height: 8),
              for (var row = 0; row < 5; row++) ...[
                Row(
                  children: [
                    SizedBox(
                        width: 30,
                        child: Text('${row + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant))),
                    for (var col = 0; col < 5; col++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: GestureDetector(
                            onTap: () => onGridPosition(row, col),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: selected?.$1 == row &&
                                          selected?.$2 == col
                                      ? theme.colorScheme.primary
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    _gridLabel(row, col),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: selected?.$1 == row &&
                                              selected?.$2 == col
                                          ? Colors.black
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withValues(alpha: 0.35),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _gridLabel(int row, int col) =>
    '${String.fromCharCode(65 + col)}${row + 1}';

String? _positionLabel(double? x, double? y) {
  final index = _positionIndex(x, y);
  return index == null ? null : _gridLabel(index.$1, index.$2);
}

(int, int)? _positionIndex(double? x, double? y) {
  if (x == null || y == null) return null;
  final col = ((x - 0.1) / 0.2).round().clamp(0, 4);
  final row = ((y - 0.1) / 0.2).round().clamp(0, 4);
  return (row, col);
}
