import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/services/comic_text_recognition_service.dart';
import 'package:nai_huishi/presentation/widgets/comic_canvas.dart';

class ComicPostEditorPage extends StatefulWidget {
  final ComicPanel panel;
  final ValueChanged<ComicPanel> onSave;

  const ComicPostEditorPage({
    super.key,
    required this.panel,
    required this.onSave,
  });

  @override
  State<ComicPostEditorPage> createState() => _ComicPostEditorPageState();
}

class _ComicPostEditorPageState extends State<ComicPostEditorPage> {
  static const _uuid = Uuid();
  late ComicPanel _panel;
  String? _selectedOverlayId;
  bool _brushMode = false;
  List<ComicPoint> _pendingStroke = const [];
  double _brushWidth = 0.035;

  @override
  void initState() {
    super.initState();
    _panel = widget.panel;
  }

  ComicCandidate? get _candidate => _panel.selectedCandidate;

  ComicOverlay? get _selectedOverlay {
    for (final overlay in _panel.overlays) {
      if (overlay.id == _selectedOverlayId) return overlay;
    }
    return null;
  }

  void _updateOverlay(ComicOverlay overlay) {
    setState(() {
      _panel = _panel.copyWith(
        overlays: _panel.overlays
            .map((item) => item.id == overlay.id ? overlay : item)
            .toList(),
      );
    });
  }

  Future<void> _addBubble({bool withCover = false}) async {
    final order = _panel.overlays.length;
    final rect = const ComicRect(x: 0.2, y: 0.2, width: 0.42, height: 0.22);
    final overlays = [..._panel.overlays];
    if (withCover) {
      overlays.add(ComicOverlay(
        id: _uuid.v4(),
        type: ComicOverlayType.whiteCover,
        rect: rect,
        backgroundColor: 0xFFFFFFFF,
        zIndex: order,
      ));
    }
    final bubble = ComicOverlay(
      id: _uuid.v4(),
      type: ComicOverlayType.bubble,
      rect: rect,
      text: '输入台词',
      tailY: 1.16,
      zIndex: order + (withCover ? 1 : 0),
    );
    setState(() {
      _panel = _panel.copyWith(overlays: [...overlays, bubble]);
      _selectedOverlayId = bubble.id;
      _brushMode = false;
    });
    if (!withCover) return;
    final candidate = _candidate;
    if (candidate == null) return;
    final areas = await ComicTextRecognitionService()
        .recognizeTextAreas(candidate.imagePath, rect);
    if (!mounted || areas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请使用白色笔覆盖原文字。')),
        );
      }
      return;
    }
    setState(() {
      final detected = areas
          .map((area) => ComicOverlay(
                id: _uuid.v4(),
                type: ComicOverlayType.whiteCover,
                rect: area,
                backgroundColor: 0xFFFFFFFF,
                zIndex: order + 1,
              ))
          .toList();
      final bubbleIndex =
          _panel.overlays.indexWhere((item) => item.id == bubble.id);
      final next = [..._panel.overlays]..insertAll(bubbleIndex, detected);
      _panel = _panel.copyWith(overlays: next);
    });
  }

  void _addText() {
    final overlay = ComicOverlay(
      id: _uuid.v4(),
      type: ComicOverlayType.text,
      rect: const ComicRect(x: 0.25, y: 0.25, width: 0.4, height: 0.14),
      text: '输入文字',
      fontSize: 0.09,
      zIndex: _panel.overlays.length,
    );
    setState(() {
      _panel = _panel.copyWith(overlays: [..._panel.overlays, overlay]);
      _selectedOverlayId = overlay.id;
      _brushMode = false;
    });
  }

  void _removeSelected() {
    if (_selectedOverlayId == null) return;
    setState(() {
      _panel = _panel.copyWith(
        overlays: _panel.overlays
            .where((overlay) => overlay.id != _selectedOverlayId)
            .toList(),
      );
      _selectedOverlayId = null;
      _brushMode = false;
    });
  }

  ComicOverlay _coverForBrush() {
    final selected = _selectedOverlay;
    if (selected?.type == ComicOverlayType.whiteCover) return selected!;
    final existing = _panel.overlays.lastWhere(
      (overlay) => overlay.type == ComicOverlayType.whiteCover,
      orElse: () => ComicOverlay(
        id: _uuid.v4(),
        type: ComicOverlayType.whiteCover,
        rect: const ComicRect(x: 0, y: 0, width: 1, height: 1),
        zIndex: _panel.overlays.length,
      ),
    );
    if (!_panel.overlays.any((overlay) => overlay.id == existing.id)) {
      _panel = _panel.copyWith(overlays: [..._panel.overlays, existing]);
    }
    return existing;
  }

  void _toggleBrush() {
    setState(() {
      _coverForBrush();
      _brushMode = !_brushMode;
      _pendingStroke = const [];
    });
  }

  void _startBrush(ComicPoint point) {
    setState(() => _pendingStroke = [point]);
  }

  void _updateBrush(ComicPoint point) {
    if (_pendingStroke.isEmpty) return;
    setState(() => _pendingStroke = [..._pendingStroke, point]);
  }

  void _endBrush() {
    if (_pendingStroke.isEmpty) return;
    final cover = _coverForBrush();
    _updateOverlay(cover.copyWith(
      brushStrokes: [
        ...cover.brushStrokes,
        ComicBrushStroke(points: _pendingStroke, width: _brushWidth),
      ],
    ));
    setState(() => _pendingStroke = const []);
  }

  void _undoBrush() {
    final cover = _selectedOverlay?.type == ComicOverlayType.whiteCover
        ? _selectedOverlay
        : _panel.overlays.lastWhere(
            (overlay) => overlay.type == ComicOverlayType.whiteCover,
            orElse: () => const ComicOverlay(
              id: '',
              type: ComicOverlayType.whiteCover,
              rect: ComicRect(x: 0, y: 0, width: 1, height: 1),
            ),
          );
    if (cover == null || cover.id.isEmpty || cover.brushStrokes.isEmpty) return;
    _updateOverlay(cover.copyWith(
      brushStrokes:
          cover.brushStrokes.sublist(0, cover.brushStrokes.length - 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    if (candidate == null || candidate.imagePath.isEmpty) {
      return const Scaffold(body: Center(child: Text('请先在分镜中选择一张主图')));
    }
    final selected = _selectedOverlay;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_panel.title} · 对白后期'),
        actions: [
          IconButton(
            tooltip: '保存工程',
            onPressed: () {
              widget.onSave(_panel);
              Navigator.pop(context);
            },
            icon: const Icon(CupertinoIcons.check_mark_circled_solid),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          final canvas = _buildCanvas(candidate.imagePath);
          final inspector = selected == null
              ? const SizedBox.shrink()
              : _OverlayInspector(overlay: selected, onChanged: _updateOverlay);
          return Column(children: [
            _buildToolbar(selected),
            Expanded(
              child: wide
                  ? Row(children: [
                      Expanded(child: canvas),
                      SizedBox(
                          width: 300, child: _InspectorPanel(child: inspector)),
                    ])
                  : canvas,
            ),
            if (!wide && selected != null) _InspectorPanel(child: inspector),
          ]);
        }),
      ),
    );
  }

  Widget _buildCanvas(String imagePath) => Padding(
        padding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          minScale: 0.7,
          maxScale: 4,
          child: ComicCanvas(
            panel: _panel,
            imagePath: imagePath,
            selectedOverlayId: _selectedOverlayId,
            onSelectOverlay: (id) => setState(() {
              _selectedOverlayId = id;
              _brushMode = false;
            }),
            onUpdateOverlay: _updateOverlay,
            brushMode: _brushMode,
            onBrushStart: _startBrush,
            onBrushUpdate: _updateBrush,
            onBrushEnd: _endBrush,
          ),
        ),
      );

  Widget _buildToolbar(ComicOverlay? selected) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border:
              Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _ToolbarButton(
              tooltip: '添加对话框',
              icon: CupertinoIcons.text_bubble,
              onPressed: () => _addBubble(),
            ),
            _ToolbarButton(
              tooltip: '覆盖替换',
              icon: CupertinoIcons.rectangle_on_rectangle,
              onPressed: () => _addBubble(withCover: true),
            ),
            _ToolbarButton(
              tooltip: '只添加文字',
              icon: CupertinoIcons.textformat,
              onPressed: _addText,
            ),
            _ToolbarButton(
              tooltip: _brushMode ? '结束白色笔' : '白色笔',
              icon: CupertinoIcons.paintbrush,
              selected: _brushMode,
              onPressed: _toggleBrush,
            ),
            if (_brushMode) ...[
              SizedBox(
                width: 150,
                child: Slider(
                  value: _brushWidth,
                  min: 0.01,
                  max: 0.12,
                  onChanged: (value) => setState(() => _brushWidth = value),
                ),
              ),
              _ToolbarButton(
                tooltip: '撤销最后一笔',
                icon: CupertinoIcons.arrow_uturn_left,
                onPressed: _undoBrush,
              ),
            ],
            if (selected != null)
              _ToolbarButton(
                tooltip: '删除图层',
                icon: CupertinoIcons.delete,
                destructive: true,
                onPressed: _removeSelected,
              ),
          ]),
        ),
      );
}

class _ToolbarButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final bool destructive;

  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          foregroundColor: destructive
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.onSurface,
        ),
        icon: Icon(icon),
      );
}

class _InspectorPanel extends StatelessWidget {
  final Widget child;

  const _InspectorPanel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
            left: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: SingleChildScrollView(child: child),
      );
}

class _OverlayInspector extends StatefulWidget {
  final ComicOverlay overlay;
  final ValueChanged<ComicOverlay> onChanged;

  const _OverlayInspector({required this.overlay, required this.onChanged});

  @override
  State<_OverlayInspector> createState() => _OverlayInspectorState();
}

class _OverlayInspectorState extends State<_OverlayInspector> {
  late final TextEditingController _controller;

  static const _fontOptions = <String?, String>{
    null: '系统无衬线',
    'serif': '系统衬线',
    'monospace': '系统等宽',
  };

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.overlay.text);
  }

  @override
  void didUpdateWidget(covariant _OverlayInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlay.id != widget.overlay.id) {
      _controller.text = widget.overlay.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _controller,
        minLines: 1,
        maxLines: 4,
        onChanged: (value) => widget.onChanged(overlay.copyWith(text: value)),
        decoration: const InputDecoration(
          isDense: true,
          labelText: '文字内容',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      if (overlay.type == ComicOverlayType.bubble) ...[
        DropdownButtonFormField<ComicBubbleType>(
          initialValue: overlay.bubbleType,
          isDense: true,
          items: ComicBubbleType.values
              .map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(switch (type) {
                      ComicBubbleType.speech => '对话框',
                      ComicBubbleType.thought => '思考泡',
                      ComicBubbleType.narration => '旁白框',
                      ComicBubbleType.shout => '爆炸框',
                    }),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null)
              widget.onChanged(overlay.copyWith(bubbleType: value));
          },
          decoration: const InputDecoration(labelText: '气泡类型'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ComicBubbleShape>(
          initialValue: overlay.bubbleShape,
          isDense: true,
          items: ComicBubbleShape.values
              .map((shape) => DropdownMenuItem(
                    value: shape,
                    child: Text(shape == ComicBubbleShape.oval ? '椭圆' : '矩形'),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null)
              widget.onChanged(overlay.copyWith(bubbleShape: value));
          },
          decoration: const InputDecoration(labelText: '外形'),
        ),
        const SizedBox(height: 8),
      ],
      DropdownButtonFormField<String?>(
        initialValue: overlay.fontFamily,
        isDense: true,
        items: _fontOptions.entries
            .map((entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)))
            .toList(),
        onChanged: (value) => widget.onChanged(
          value == null
              ? overlay.copyWith(clearFontFamily: true)
              : overlay.copyWith(fontFamily: value),
        ),
        decoration: const InputDecoration(labelText: '字体'),
      ),
      const SizedBox(height: 6),
      Row(children: [
        const Text('字号'),
        Expanded(
          child: Slider(
            value: overlay.fontSize.clamp(0.025, 0.16),
            min: 0.025,
            max: 0.16,
            onChanged: (value) =>
                widget.onChanged(overlay.copyWith(fontSize: value)),
          ),
        ),
      ]),
      if (overlay.type == ComicOverlayType.bubble)
        Text(
          '拖动画布上的箭头调整尾巴指向',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ]);
  }
}
