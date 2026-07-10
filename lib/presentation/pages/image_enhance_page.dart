import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/sr_model.dart';
import 'package:nai_huishi/presentation/viewmodels/super_resolution_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

/// 图像增强（超分）功能页。
/// 导入图片 → 选模型/倍率 → 本地超分 → 拖拽对比 → 保存到相册。
class ImageEnhancePage extends StatefulWidget {
  const ImageEnhancePage({super.key});

  @override
  State<ImageEnhancePage> createState() => _ImageEnhancePageState();
}

class _ImageEnhancePageState extends State<ImageEnhancePage> {
  late final SuperResolutionViewModel _vm;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _vm = sl<SuperResolutionViewModel>();
    _vm.addListener(_onChanged);
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickImage() async {
    if (_vm.isRunning) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    _vm.selectInput(picked.path);
  }

  Future<void> _run() async {
    if (_vm.inputPath == null) {
      showFloatingToast(context, '请先选择图片', icon: CupertinoIcons.photo);
      return;
    }
    await _vm.run();
    if (!mounted) return;
    if (_vm.status == SrStatus.success) {
      showFloatingToast(context, '增强完成', icon: CupertinoIcons.checkmark_circle);
    } else if (_vm.status == SrStatus.failed) {
      showFloatingToast(context, '处理失败',
          icon: CupertinoIcons.exclamationmark_circle);
    }
  }

  Future<void> _save() async {
    final ok = await _vm.saveToGallery();
    if (!mounted) return;
    showFloatingToast(
      context,
      ok ? '已保存到相册' : '保存失败',
      icon: ok
          ? CupertinoIcons.checkmark_circle
          : CupertinoIcons.exclamationmark_circle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('图像增强')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildPreview(isDark),
            const SizedBox(height: 18),
            _buildModelSelector(isDark),
            const SizedBox(height: 18),
            if (_vm.isRunning) _buildProgress(isDark),
            if (_vm.status == SrStatus.failed && _vm.error != null)
              _buildError(isDark),
            const SizedBox(height: 8),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final showOutput = _vm.status == SrStatus.success && _vm.outputPath != null;
    final inputPath = _vm.inputPath;
    final outputPath = _vm.outputPath;

    Widget child;
    if (inputPath == null) {
      child = _buildPlaceholder(isDark);
    } else if (showOutput && outputPath != null) {
      // 增强成功 → 拖拽对比
      child = _BeforeAfterCompare(
        key: ValueKey('$inputPath::$outputPath'),
        beforePath: inputPath,
        afterPath: outputPath,
        scaleLabel: '${_vm.model.scale}x',
        primary: Theme.of(context).colorScheme.primary,
        isDark: isDark,
      );
    } else {
      child = Image.file(File(inputPath), fit: BoxFit.contain);
    }

    final preview = GestureDetector(
      onTap: showOutput ? null : _pickImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(color: cardColor, child: child),
      ),
    );

    if (!showOutput) {
      return AspectRatio(aspectRatio: 1, child: preview);
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final comparisonHeight = (screenHeight * 0.6).clamp(420.0, 680.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      height: comparisonHeight,
      child: preview,
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    final hint = isDark ? Colors.white54 : Colors.black38;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(CupertinoIcons.photo_on_rectangle, size: 48, color: hint),
        const SizedBox(height: 12),
        Text('点击选择图片', style: TextStyle(color: hint, fontSize: 15)),
      ],
    );
  }

  Widget _buildModelSelector(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text('选择模型',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: cardColor,
            child: Column(
              children: [
                for (var i = 0; i < SrModel.presets.length; i++) ...[
                  _modelTile(SrModel.presets[i], isDark),
                  if (i != SrModel.presets.length - 1)
                    Divider(
                        height: 1,
                        thickness: 0.6,
                        indent: 16,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.07)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _modelTile(SrModel m, bool isDark) {
    final selected = _vm.model == m;
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: _vm.isRunning ? null : () => _vm.selectModel(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 22,
              color: selected
                  ? primary
                  : (isDark ? Colors.white30 : Colors.black26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(m.description,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(bool isDark) {
    final v = _vm.progressValue;
    final pctLabel = v == null ? null : '${(v * 100).toStringAsFixed(0)}%';
    final primary = Theme.of(context).colorScheme.primary;
    final track = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.07);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C21) : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: v,
                  color: primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _vm.progress.isEmpty ? '处理中...' : _vm.progress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black54),
                ),
              ),
              if (pctLabel != null)
                Text(
                  pctLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: track,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(_vm.error ?? '',
          style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
    );
  }

  Widget _buildActions() {
    final canSave = _vm.status == SrStatus.success && _vm.outputPath != null;
    final hasOutput = _vm.outputPath != null;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _vm.isRunning ? _vm.cancel : _run,
            child: Text(_vm.isRunning ? '取消' : '开始增强',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        if (hasOutput && !_vm.isRunning) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(CupertinoIcons.photo, size: 20),
              label: const Text('换一张图片',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        if (canSave) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _save,
              icon: const Icon(CupertinoIcons.square_arrow_down, size: 20),
              label: const Text('保存到相册',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }
}

/// 增强前/后拖拽对比组件。
/// 拖动竖直分割线：左侧显示 before，右侧显示 after。
class _BeforeAfterCompare extends StatefulWidget {
  final String beforePath;
  final String afterPath;
  final String scaleLabel;
  final Color primary;
  final bool isDark;

  const _BeforeAfterCompare({
    super.key,
    required this.beforePath,
    required this.afterPath,
    required this.scaleLabel,
    required this.primary,
    required this.isDark,
  });

  @override
  State<_BeforeAfterCompare> createState() => _BeforeAfterCompareState();
}

class _BeforeAfterCompareState extends State<_BeforeAfterCompare> {
  /// 分割线位置，0~1，相对宽度
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final dividerX = (w * _split).clamp(0.0, w);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _updateSplit(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _updateSplit(d.localPosition.dx, w),
          onTapDown: (d) => _updateSplit(d.localPosition.dx, w),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 底层：增强后（after）
              Image.file(File(widget.afterPath), fit: BoxFit.contain),
              // 上层：增强前（before），用 ClipRect 限制只显示左半
              ClipRect(
                clipper: _LeftClipper(_split),
                child: Image.file(File(widget.beforePath), fit: BoxFit.contain),
              ),
              // 顶部左右标签
              Positioned(
                left: 10,
                top: 10,
                child: _badge('原图', Colors.black.withValues(alpha: 0.6)),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: _badge('增强后 ${widget.scaleLabel}', widget.primary),
              ),
              // 分割线 + 拖动手柄
              Positioned(
                left: dividerX - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: IgnorePointer(
                  child: Container(color: Colors.white),
                ),
              ),
              Positioned(
                left: dividerX - 18,
                top: 0,
                bottom: 0,
                width: 36,
                child: Center(
                  child: _DragHandle(color: widget.primary),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.arrow_left_right,
                            size: 12, color: Colors.white),
                        SizedBox(width: 6),
                        Text('左右拖动对比',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateSplit(double x, double w) {
    if (w <= 0) return;
    setState(() {
      _split = (x / w).clamp(0.0, 1.0);
    });
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// 把矩形裁剪成 [0, fraction*width]，用于在对比组件中显示左半的 before 图。
class _LeftClipper extends CustomClipper<Rect> {
  final double fraction;

  _LeftClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

/// 拖动分割线上的圆形手柄
class _DragHandle extends StatelessWidget {
  final Color color;

  const _DragHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(CupertinoIcons.arrow_left_right, size: 18, color: color),
    );
  }
}
