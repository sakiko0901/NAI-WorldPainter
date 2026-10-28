import 'package:flutter/material.dart';

class InpaintBrushSheet extends StatefulWidget {
  const InpaintBrushSheet({
    super.key,
    required this.square,
    required this.sizeLevel,
    required this.onChanged,
    this.erase = false,
  });

  final bool square;
  final int sizeLevel;
  final bool erase;
  final void Function(bool square, int sizeLevel) onChanged;

  @override
  State<InpaintBrushSheet> createState() => _InpaintBrushSheetState();
}

class _InpaintBrushSheetState extends State<InpaintBrushSheet> {
  late bool _square = widget.square;
  late int _sizeLevel = widget.sizeLevel;

  void _update(VoidCallback change) {
    setState(change);
    widget.onChanged(_square, _sizeLevel);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    Widget shape(bool square) => Expanded(
          child: Semantics(
            button: true,
            selected: _square == square,
            child: InkWell(
              key: ValueKey(
                  square ? 'inpaint-brush-square' : 'inpaint-brush-round'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => _update(() => _square = square),
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: _square == square
                      ? colors.primary.withValues(alpha: 0.12)
                      : colors.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color:
                        _square == square ? colors.primary : Colors.transparent,
                  ),
                ),
                child: Column(children: [
                  SizedBox(
                    height: 48,
                    child: Center(
                      child: AnimatedContainer(
                        duration: duration,
                        width: 12 + _sizeLevel * 3.6,
                        height: 12 + _sizeLevel * 3.6,
                        decoration: BoxDecoration(
                          shape: square ? BoxShape.rectangle : BoxShape.circle,
                          color: const Color(0x802196F3),
                          border: Border.all(
                              color: const Color(0xFF80D8FF), width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(square ? '方形' : '圆形', style: theme.textTheme.titleSmall),
                ]),
              ),
            ),
          ),
        );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          key: const ValueKey('inpaint-brush-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Text(widget.erase ? '橡皮设置' : '画笔设置',
                      style: theme.textTheme.titleLarge)),
              IconButton(
                tooltip: '关闭画笔设置',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              shape(false),
              const SizedBox(width: 12),
              shape(true)
            ]),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: Text('笔刷大小', style: theme.textTheme.titleSmall)),
              Text('$_sizeLevel / 10', style: TextStyle(color: colors.primary)),
            ]),
            Slider(
              key: const ValueKey('inpaint-brush-size'),
              value: _sizeLevel.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '$_sizeLevel',
              onChanged: (value) => _update(() => _sizeLevel = value.round()),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('1', style: TextStyle(color: colors.onSurfaceVariant)),
              Text('10', style: TextStyle(color: colors.onSurfaceVariant)),
            ]),
            const SizedBox(height: 16),
            if (!_square && !widget.erase)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('涂抹范围即遮罩，边缘以蓝色标记',
                    style: TextStyle(
                        fontSize: 12, color: colors.onSurfaceVariant)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('inpaint-brush-done'),
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}
