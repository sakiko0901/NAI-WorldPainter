import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:dio/dio.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/core/services/tag_completion_service.dart';
import 'package:nai_huishi/core/utils/prompt_completion_edit.dart';
import 'package:nai_huishi/domain/entities/tag_completion.dart';

/// Keeps the native editor and adds a caret-anchored, keyboard-safe suggestion list.
class PromptTagField extends StatefulWidget {
  const PromptTagField(
      {super.key,
      this.fieldKey,
      required this.controller,
      this.focusNode,
      this.onChanged,
      this.enabled = true,
      this.autofocus = false,
      this.minLines,
      this.maxLines = 1,
      this.expands = false,
      this.style,
      this.decoration = const InputDecoration(),
      this.textAlignVertical,
      this.textInputAction,
      this.service});
  final Key? fieldKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final TextStyle? style;
  final InputDecoration decoration;
  final TextAlignVertical? textAlignVertical;
  final TextInputAction? textInputAction;
  final TagCompletionService? service;

  @override
  State<PromptTagField> createState() => _PromptTagFieldState();
}

class _PromptTagFieldState extends State<PromptTagField>
    with WidgetsBindingObserver {
  final _anchor = GlobalKey();
  final _tapGroup = Object();
  final _textScroll = ScrollController();
  final _listScroll = ScrollController();
  late FocusNode _focus;
  late TagCompletionService _service;
  late TextEditingValue _previous;
  ScrollPosition? _parentScroll;
  OverlayEntry? _overlay;
  Timer? _debounce;
  CancelToken? _remoteRequest;
  int _generation = 0;
  int _selected = 0;
  List<TagCompletion> _items = const [];
  PromptCompletionEdit? _edit;
  TextEditingValue? _snapshot;
  String? _status;
  bool _applying = false;
  bool _related = false;
  bool _loading = false;
  double _rowHeight = 52;
  KeyEventResult Function(FocusNode, KeyEvent)? _previousKeyHandler;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? TagCompletionService.instance;
    _service.addListener(_settingsChanged);
    _previous = widget.controller.value;
    widget.controller.addListener(_textChanged);
    _attachFocus();
    _textScroll.addListener(_reposition);
    WidgetsBinding.instance.addObserver(this);
  }

  void _attachFocus() {
    _focus = widget.focusNode ?? FocusNode();
    _previousKeyHandler = _focus.onKeyEvent;
    _focus.onKeyEvent = _keyEvent;
    _focus.addListener(_focusChanged);
  }

  void _detachFocus(FocusNode? external) {
    _focus.removeListener(_focusChanged);
    _focus.onKeyEvent = _previousKeyHandler;
    if (external == null) _focus.dispose();
  }

  @override
  void didUpdateWidget(covariant PromptTagField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_textChanged);
      widget.controller.addListener(_textChanged);
      _previous = widget.controller.value;
      _dismiss();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocus(oldWidget.focusNode);
      _attachFocus();
      _dismiss();
    }
    if (!widget.enabled) _dismiss();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _parentScroll) {
      _parentScroll?.removeListener(_dismiss);
      _parentScroll = position;
      _parentScroll?.addListener(_dismiss);
    }
    _reposition();
  }

  @override
  void didChangeMetrics() => _reposition();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismiss();
    _parentScroll?.removeListener(_dismiss);
    widget.controller.removeListener(_textChanged);
    _service.removeListener(_settingsChanged);
    _detachFocus(widget.focusNode);
    _textScroll.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _settingsChanged() {
    _dismiss();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) {
      _dismiss();
    } else {
      unawaited(_service.initialize());
    }
  }

  void _textChanged() {
    final value = widget.controller.value;
    final changed = value.text != _previous.text ||
        (value.composing.isCollapsed && !_previous.composing.isCollapsed);
    _previous = value;
    if (_applying) return;
    _dismiss();
    if (!changed || !_focus.hasFocus || !widget.enabled) return;
    final edit = PromptCompletionEdit.parse(value);
    if (edit == null || edit.query.isEmpty) return;
    // One Chinese character is useful; English starts at two characters.
    if (edit.query.length < 2 &&
        !RegExp(r'[\u3400-\u9fff]').hasMatch(edit.query)) {
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 140), () => _query(edit, value));
  }

  Future<void> _query(
      PromptCompletionEdit edit, TextEditingValue snapshot) async {
    final generation = ++_generation;
    await _service.initialize();
    if (!_current(generation, snapshot) || !_service.enabled) return;
    _edit = edit;
    _snapshot = snapshot;
    _loading = true;
    _status = '正在查询词库…';
    _show();
    try {
      final local =
          await _service.search(edit.query, artistOnly: edit.artistOnly);
      if (!_current(generation, snapshot)) return;
      _items = _rank(local, edit);
      _loading = false;
      _status = null;
      if (_items.isEmpty && !_service.onlineEnabled) {
        _dismiss();
        return;
      }
      _show();
    } catch (_) {
      if (!_current(generation, snapshot)) return;
      _loading = false;
      _status = '离线词库暂不可用，可在补全设置中重试';
      _show();
    }
    if (!_service.onlineEnabled || !_current(generation, snapshot)) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!_current(generation, snapshot)) return;
    try {
      final remote = await _service.online(edit.query,
          cancelToken: _remoteRequest = CancelToken());
      if (!_current(generation, snapshot)) return;
      final seen = _items.map((t) => t.tag).toSet();
      final selectedTag = _items.isEmpty ? null : _items[_selected].tag;
      _items = _rank([
        ..._items,
        ...remote.where(
            (t) => seen.add(t.tag) && (!edit.artistOnly || t.category == 1))
      ], edit);
      if (selectedTag != null) {
        _selected = math.max(0, _items.indexWhere((t) => t.tag == selectedTag));
      }
      _status = _items.isEmpty ? '没有匹配的标签' : null;
      _show();
    } catch (_) {
      if (!_current(generation, snapshot)) return;
      _status = _items.isEmpty ? '在线查询暂不可用' : '在线暂不可用，已显示离线结果';
      _show();
    }
  }

  List<TagCompletion> _rank(
      List<TagCompletion> items, PromptCompletionEdit edit) {
    // Stable partition keeps remote updates from reshuffling local matches.
    return [
      ...items.where((t) => !edit.existing.contains(t.tag)),
      ...items.where((t) => edit.existing.contains(t.tag))
    ];
  }

  bool _current(int generation, TextEditingValue snapshot) =>
      mounted &&
      generation == _generation &&
      widget.enabled &&
      _focus.hasFocus &&
      widget.controller.value == snapshot;

  void _dismiss() {
    _generation++;
    _debounce?.cancel();
    _remoteRequest?.cancel();
    _remoteRequest = null;
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
    _items = const [];
    _selected = 0;
    _status = null;
    _related = false;
    _loading = false;
  }

  void _show() {
    if (!mounted || !_focus.hasFocus) return;
    if (_overlay == null) {
      _overlay = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context, rootOverlay: true).insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _reposition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _overlay?.markNeedsBuild();
    });
  }

  RenderEditable? _editable(RenderObject? node) {
    if (node is RenderEditable) return node;
    RenderEditable? result;
    node?.visitChildren((child) {
      result ??= _editable(child);
    });
    return result;
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final anchor = _anchor.currentContext?.findRenderObject();
    final editable = _editable(anchor);
    final root =
        Overlay.of(context, rootOverlay: true).context.findRenderObject();
    if (anchor is! RenderBox ||
        root is! RenderBox ||
        editable == null ||
        !anchor.attached) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(overlayContext);
    final origin = root.localToGlobal(Offset.zero);
    final fieldOrigin = anchor.localToGlobal(Offset.zero) - origin;
    final caretRect =
        editable.getLocalRectForCaret(widget.controller.selection.extent);
    final caret = editable.localToGlobal(caretRect.bottomLeft) - origin;
    final topLimit = math.max(8.0, media.padding.top - origin.dy + 8);
    final bottomLimit = math.min(
            root.size.height,
            media.size.height -
                math.max(media.viewInsets.bottom, media.padding.bottom) -
                origin.dy) -
        8;
    final rowTop = caret.dy - caretRect.height;
    if (caret.dy < topLimit || rowTop > bottomLimit) {
      return const SizedBox.shrink();
    }
    final below = bottomLimit - caret.dy - 6;
    final above = rowTop - topLimit - 6;
    final space = math.max(below, above);
    if (space < 55) return const SizedBox.shrink();
    _rowHeight = math.max(52, media.textScaler.scale(13) * 2.6 + 14);
    final desired = math.min(4, _items.length) * _rowHeight +
        40 +
        (_status == null ? 0 : 32);
    final height = math.min(math.max(80.0, desired), space);
    final useBelow = below >= height;
    final width = math.min(440.0,
        math.min(math.max(anchor.size.width, 270.0), root.size.width - 24));
    final left = fieldOrigin.dx
        .clamp(12.0, math.max(12.0, root.size.width - width - 12));
    final top = useBelow ? caret.dy + 6 : rowTop - height - 6;
    return Positioned(
        left: left.toDouble(),
        top: math.max(topLimit, top),
        width: width,
        height: height,
        child: InheritedTheme.captureAll(
            context, TextFieldTapRegion(groupId: _tapGroup, child: _panel())));
  }

  Widget _panel() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
        key: const ValueKey('tag-completion-panel'),
        color: Color.alphaBlend(
            colors.onSurface.withValues(alpha: 0.025), colors.surface),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          SizedBox(
              height: 40,
              child: Row(children: [
                const SizedBox(width: 12),
                Expanded(
                    child: Text(_related ? '相关标签' : '标签补全',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant))),
                if (!_related &&
                    _items.isNotEmpty &&
                    _service.onlineEnabled &&
                    _items.any((t) => t.tag == _edit?.query))
                  TextButton(
                      onPressed: _loadRelated,
                      style: TextButton.styleFrom(
                          minimumSize: const Size(48, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('相关', style: TextStyle(fontSize: 12))),
                IconButton(
                    tooltip: '关闭补全',
                    onPressed: _dismiss,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 36),
                    icon: const Icon(CupertinoIcons.xmark, size: 13)),
              ])),
          if (_items.isNotEmpty)
            Expanded(
                child: Scrollbar(
                    controller: _listScroll,
                    child: ListView.builder(
                        controller: _listScroll,
                        padding: EdgeInsets.zero,
                        itemExtent: _rowHeight,
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final existing =
                              _edit?.existing.contains(item.tag) ?? false;
                          final subtitle = _service.showTranslation &&
                                  item.translation.isNotEmpty
                              ? item.translation
                              : item.alias == null
                                  ? item.categoryLabel
                                  : '别名：${item.alias}';
                          return Semantics(
                              selected: index == _selected,
                              button: true,
                              label:
                                  '${item.displayTag}，$subtitle${existing ? '，已添加' : ''}',
                              child: InkWell(
                                  onTap: () => _select(index),
                                  canRequestFocus: false,
                                  child: Container(
                                      color: index == _selected
                                          ? colors.primary
                                              .withValues(alpha: 0.10)
                                          : null,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      child: Row(children: [
                                        Expanded(
                                            child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(item.displayTag,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: existing
                                                          ? colors
                                                              .onSurfaceVariant
                                                          : colors.onSurface)),
                                              Text(subtitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: colors
                                                          .onSurfaceVariant)),
                                            ])),
                                        const SizedBox(width: 8),
                                        Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                  existing
                                                      ? '已添加'
                                                      : item.categoryLabel,
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: colors
                                                          .onSurfaceVariant)),
                                              if (item.count > 0)
                                                Text(_count(item.count),
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: colors
                                                            .onSurfaceVariant))
                                            ]),
                                      ]))));
                        }))),
          if (_status != null)
            Flexible(
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: Text(_status!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant)))),
        ]));
  }

  String _count(int count) =>
      count >= 10000 ? '${(count / 10000).toStringAsFixed(1)}万' : '$count';

  Future<void> _loadRelated() async {
    final current = widget.controller.value;
    if (!current.selection.isValid || !current.composing.isCollapsed) return;
    var cursor = current.selection.end;
    while (cursor > 0 && ',， \n\r'.contains(current.text[cursor - 1])) {
      cursor--;
    }
    final edit = PromptCompletionEdit.parse(
        current.copyWith(selection: TextSelection.collapsed(offset: cursor)),
        allowBoundary: true);
    if (edit == null) return;
    _dismiss();
    _edit = edit;
    _snapshot = current;
    final generation = ++_generation;
    _related = true;
    _loading = true;
    _items = const [];
    _selected = 0;
    _status = '正在查找相关标签…';
    _show();
    try {
      final result = await _service.online(edit.query,
          related: true, cancelToken: _remoteRequest = CancelToken());
      if (!_current(generation, current)) return;
      _items = result
          .where((t) => t.tag != edit.query && !edit.existing.contains(t.tag))
          .toList();
      _status = _items.isEmpty ? '暂无相关标签' : null;
    } catch (_) {
      if (!_current(generation, current)) return;
      _status = '相关标签查询失败，请稍后重试';
    }
    _loading = false;
    _show();
  }

  void _select(int index) {
    if (index < 0 ||
        index >= _items.length ||
        _edit == null ||
        widget.controller.value != _snapshot) {
      _dismiss();
      return;
    }
    final next = _edit!.apply(widget.controller.value, _items[index].tag,
        autoComma: _service.autoComma, related: _related);
    _dismiss();
    _applying = true;
    widget.controller.value = next;
    _applying = false;
    widget.onChanged?.call(next.text);
    _focus.requestFocus();
  }

  KeyEventResult _keyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed &&
        _service.onlineEnabled) {
      _loadRelated();
      return KeyEventResult.handled;
    }
    if (_overlay != null &&
        event is! KeyUpEvent &&
        widget.controller.value.composing.isCollapsed) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape) {
        _dismiss();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter &&
          HardwareKeyboard.instance.isShiftPressed) {
        _dismiss();
        if (widget.maxLines != 1 && event is KeyDownEvent) {
          final value = widget.controller.value;
          final selection = value.selection;
          final next = TextEditingValue(
              text:
                  value.text.replaceRange(selection.start, selection.end, '\n'),
              selection: TextSelection.collapsed(offset: selection.start + 1));
          _applying = true;
          widget.controller.value = next;
          _applying = false;
          widget.onChanged?.call(next.text);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      if (_items.isNotEmpty && !_loading) {
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) {
          _selected =
              (_selected + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
                  _items.length;
          if (_listScroll.hasClients) {
            _listScroll.jumpTo((_selected * _rowHeight)
                .clamp(0.0, _listScroll.position.maxScrollExtent));
          }
          _overlay?.markNeedsBuild();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter) {
          _select(_selected);
          return KeyEventResult.handled;
        }
      }
    }
    return _previousKeyHandler?.call(node, event) ?? KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      key: _anchor,
      child: TextField(
        key: widget.fieldKey,
        groupId: _tapGroup,
        controller: widget.controller,
        focusNode: _focus,
        scrollController: _textScroll,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        expands: widget.expands,
        style: widget.style,
        decoration: widget.decoration,
        textAlignVertical: widget.textAlignVertical,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        contextMenuBuilder: (context, state) =>
            AdaptiveTextSelectionToolbar.buttonItems(
                anchors: state.contextMenuAnchors,
                buttonItems: [
              ...state.contextMenuButtonItems,
              if (_service.onlineEnabled)
                ContextMenuButtonItem(
                    label: '相关标签',
                    onPressed: () {
                      state.hideToolbar();
                      _loadRelated();
                    }),
            ]),
        onTapOutside: (event) {
          _dismiss();
          if (event.kind == PointerDeviceKind.mouse) _focus.unfocus();
        },
      ));
}
