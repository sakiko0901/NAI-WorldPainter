import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/llm_session_search_result.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/prompt_memory_page.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_session_timeline.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/prompt_version_dialog.dart';

Future<void> showChatSessionsPanel(
  BuildContext context, {
  required LlmChatViewModel vm,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) => _SessionsPanel(vm: vm),
  );
}

class _SessionsPanel extends StatefulWidget {
  final LlmChatViewModel vm;
  const _SessionsPanel({required this.vm});

  @override
  State<_SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends State<_SessionsPanel> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  int _searchRevision = 0;
  String _query = '';
  bool _searching = false;
  bool _busy = false;
  String? _searchError;
  String? _actionError;
  List<LlmSessionSearchResult> _results = [];
  late List<LlmSession> _observedSessions;
  String? _observedActiveId;
  String? _observedError;
  late bool _observedSending;

  @override
  void initState() {
    super.initState();
    _observedSessions = List.of(widget.vm.sessions);
    _observedActiveId = widget.vm.activeSessionId;
    _observedError = widget.vm.errorMessage;
    _observedSending = widget.vm.isSending;
    _searchController.addListener(_onQueryChanged);
    widget.vm.addListener(_onVmChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchRevision++;
    widget.vm.removeListener(_onVmChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onVmChanged() {
    if (!mounted) return;
    final changed = !listEquals(_observedSessions, widget.vm.sessions);
    if (!changed &&
        _observedActiveId == widget.vm.activeSessionId &&
        _observedError == widget.vm.errorMessage &&
        _observedSending == widget.vm.isSending) {
      return;
    }
    _observedActiveId = widget.vm.activeSessionId;
    _observedError = widget.vm.errorMessage;
    _observedSending = widget.vm.isSending;
    if (changed) {
      _observedSessions = List.of(widget.vm.sessions);
      if (_query.isNotEmpty) {
        _scheduleSearch();
        return;
      }
    }
    setState(() {});
  }

  void _showActionError(String message) {
    if (!mounted) return;
    setState(() => _actionError = message);
    // A failed action on an older row must not leave its feedback offscreen.
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void _onQueryChanged() {
    final query = _searchController.text.trim();
    if (query == _query) {
      setState(() {});
      return;
    }
    _query = query;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _scheduleSearch();
  }

  void _scheduleSearch({bool immediate = false}) {
    _debounce?.cancel();
    // Invalidate immediately, including during the debounce and after clear.
    final revision = ++_searchRevision;
    final query = _query;
    setState(() {
      _results = [];
      _searchError = null;
      _searching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    if (immediate) {
      unawaited(_search(query, revision));
    } else {
      _debounce = Timer(
          const Duration(milliseconds: 200), () => _search(query, revision));
    }
  }

  Future<void> _search(String query, int revision) async {
    try {
      final results = await widget.vm.searchSessions(query);
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searching = false;
        _searchError = '搜索失败，请重试';
      });
    }
  }

  Future<void> _runAction(
    String label,
    Future<void> Function() action, {
    bool closePanel = false,
    bool requiresIdle = false,
  }) async {
    if (!mounted || _busy) return;
    if (requiresIdle && widget.vm.isSending) {
      _showActionError('请先停止当前操作，再$label。');
      return;
    }
    final previousError = widget.vm.errorMessage;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
      if (!mounted) return;
      final error = widget.vm.errorMessage;
      if (error != null && error != previousError) {
        _showActionError(error);
      } else if (closePanel) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      _showActionError('$label失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(LlmSession session) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSessionDialog(initialTitle: session.title),
    );
    if (!mounted || title == null || title == session.title) return;
    await _runAction('重命名', () => widget.vm.renameSession(session.id, title));
  }

  Future<bool> _confirmDelete({LlmSession? session}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(session == null ? '清空所有历史会话' : '删除会话'),
          content: Text(session == null
              ? '会删除所有提示词辅助助手的历史会话，并新建一个空白会话。是否继续？'
              : '确定删除「${session.title}」？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: _dangerColor(ctx)),
              child: Text(session == null ? '清空' : '删除'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _delete(LlmSession session) async {
    if (!await _confirmDelete(session: session) || !mounted) return;
    await _runAction('删除会话', () => widget.vm.deleteSession(session.id),
        requiresIdle: true);
  }

  Future<void> _deleteAll() async {
    if (!await _confirmDelete() || !mounted) return;
    await _runAction('清空历史', widget.vm.deleteAllSessions,
        requiresIdle: true, closePanel: true);
  }

  Future<void> _newSession() async {
    final version = await showPromptVersionDialog(context);
    if (!mounted || version == null) return;
    await _runAction(
        '新建会话', () => widget.vm.createNewSession(promptVersion: version),
        requiresIdle: true, closePanel: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    final now = DateTime.now();
    final entries = _query.isEmpty
        ? widget.vm.sessions.map((s) => LlmSessionSearchResult(session: s))
        : _results;
    final groups = groupChatSessionTimeline(entries, now: now);
    final rows = <Object>[
      for (final group in groups) ...[group.label, ...group.entries],
    ];
    final error = _actionError ?? widget.vm.errorMessage;
    final highContrast = MediaQuery.highContrastOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: LayoutBuilder(builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight * 0.9,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: BackdropFilter(
                enabled: glass.blurEnabled && !highContrast,
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  color:
                      highContrast ? theme.colorScheme.surface : glass.raised,
                  child: SafeArea(
                    top: false,
                    child: CustomScrollView(
                      key: const ValueKey('session-history-list'),
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Column(
                              children: [
                                Center(
                                  child: Container(
                                    width: 28,
                                    height: 3,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                                _buildHeader(),
                                const SizedBox(height: 12),
                                TextField(
                                  key: const ValueKey('session-history-search'),
                                  controller: _searchController,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) {
                                    FocusScope.of(context).unfocus();
                                    _scheduleSearch(immediate: true);
                                  },
                                  decoration: InputDecoration(
                                    hintText: '搜索标题或聊天内容',
                                    prefixIcon: const Icon(
                                        CupertinoIcons.search,
                                        size: 19),
                                    suffixIcon: _searchController.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: '清除搜索',
                                            onPressed: _searchController.clear,
                                            icon: const Icon(
                                                CupertinoIcons
                                                    .xmark_circle_fill,
                                                size: 18),
                                          ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                  ),
                                ),
                                if (_busy) ...[
                                  const SizedBox(height: 8),
                                  const LinearProgressIndicator(
                                      semanticsLabel: '正在处理会话'),
                                ],
                                if (error != null) ...[
                                  const SizedBox(height: 8),
                                  Semantics(
                                    liveRegion: true,
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline,
                                            color: _dangerColor(context),
                                            size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: Text(error,
                                                style: TextStyle(
                                                    color: _dangerColor(
                                                        context)))),
                                        IconButton(
                                          tooltip: '关闭错误提示',
                                          onPressed: () {
                                            setState(() => _actionError = null);
                                            widget.vm.clearError();
                                          },
                                          icon:
                                              const Icon(Icons.close, size: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_searching)
                          const SliverToBoxAdapter(
                              child: _HistoryState(
                            icon: CupertinoIcons.search,
                            title: '正在搜索…',
                            progress: true,
                          ))
                        else if (_searchError != null)
                          SliverToBoxAdapter(
                              child: _HistoryState(
                            icon: CupertinoIcons.exclamationmark_circle,
                            title: _searchError!,
                            action: TextButton.icon(
                              onPressed: () => _scheduleSearch(immediate: true),
                              icon: const Icon(CupertinoIcons.arrow_clockwise,
                                  size: 16),
                              label: const Text('重试搜索'),
                            ),
                          ))
                        else if (rows.isEmpty)
                          SliverToBoxAdapter(
                              child: _HistoryState(
                            icon: _query.isEmpty
                                ? CupertinoIcons.chat_bubble_2
                                : CupertinoIcons.search,
                            title: _query.isEmpty ? '还没有会话' : '未找到匹配的会话',
                            subtitle: _query.isEmpty
                                ? '新建对话后，会在这里留下记录。'
                                : '试试其他关键词，或清除搜索查看全部历史。',
                          ))
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            sliver: SliverList.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                if (row is String) return _buildGroupLabel(row);
                                return _buildSession(
                                    row as LlmSessionSearchResult, now);
                              },
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                            child: Center(
                              child: TextButton.icon(
                                key: const ValueKey('clear-session-history'),
                                onPressed: widget.vm.sessions.isEmpty || _busy
                                    ? null
                                    : _deleteAll,
                                style: TextButton.styleFrom(
                                    foregroundColor: _dangerColor(context)),
                                icon:
                                    const Icon(CupertinoIcons.trash, size: 15),
                                label: const Text('清空历史',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHeader() {
    const heading = Text('会话历史',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700));
    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      TextButton.icon(
        onPressed: () => Navigator.of(context).push(CupertinoPageRoute<void>(
          builder: (_) => const PromptMemoryPage(),
        )),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8)),
        icon: const Icon(CupertinoIcons.book, size: 17),
        label: const Text('学习记忆'),
      ),
      IconButton(
        tooltip: '新对话',
        onPressed: _busy ? null : _newSession,
        icon: const Icon(CupertinoIcons.square_pencil, size: 21),
      ),
    ]);
    return LayoutBuilder(builder: (context, constraints) {
      final scaled = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (constraints.maxWidth < 240 * scaled) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading,
          Align(alignment: Alignment.centerRight, child: actions),
        ]);
      }
      return Row(children: [const Expanded(child: heading), actions]);
    });
  }

  Widget _buildGroupLabel(String label) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(children: [
          SizedBox(
              width: 20,
              child: Icon(
                  label == '置顶' ? CupertinoIcons.pin_fill : Icons.circle,
                  size: label == '置顶' ? 12 : 5,
                  color: color)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color))),
        ]),
      ),
    );
  }

  Widget _buildSession(LlmSessionSearchResult result, DateTime now) {
    final session = result.session;
    final theme = Theme.of(context);
    final active = session.id == widget.vm.activeSessionId;
    final glass = FrostedTheme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final selectedColor = highContrast
        ? theme.colorScheme.surfaceContainerHighest
        : glass.selection
            .withValues(alpha: theme.brightness == Brightness.dark ? .10 : .45);
    return Padding(
      key: ValueKey('session-row-${session.id}'),
      padding: const EdgeInsets.only(left: 9),
      child: DecoratedBox(
        decoration: BoxDecoration(
            border: Border(left: BorderSide(color: glass.border))),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 6),
          child: Material(
            color: active ? selectedColor : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side:
                  BorderSide(color: active ? glass.border : Colors.transparent),
            ),
            child: Row(children: [
              Expanded(
                child: Semantics(
                  selected: active,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _busy
                        ? null
                        : () => _runAction(
                            '切换会话', () => widget.vm.selectSession(session.id),
                            requiresIdle: true, closePanel: true),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _highlight(session.title,
                                style: theme.textTheme.bodyMedium!
                                    .copyWith(fontWeight: FontWeight.w600),
                                maxLines: 2),
                            if (result.snippet?.trim().isNotEmpty == true) ...[
                              const SizedBox(height: 5),
                              _highlight(result.snippet!,
                                  style: theme.textTheme.bodySmall!.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                  maxLines: 2),
                            ],
                            const SizedBox(height: 5),
                            Text(
                                formatChatSessionTime(session.updatedAt,
                                    now: now),
                                style: theme.textTheme.labelSmall!.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ]),
                    ),
                  ),
                ),
              ),
              _buildSessionMenu(session),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _highlight(String text, {required TextStyle style, int maxLines = 2}) {
    final spans = <TextSpan>[];
    var cursor = 0;
    if (_query.isNotEmpty) {
      // User input is literal, including symbols such as [, + and *.
      for (final match in RegExp(RegExp.escape(_query), caseSensitive: false)
          .allMatches(text)) {
        if (match.start > cursor) {
          spans.add(TextSpan(text: text.substring(cursor, match.start)));
        }
        spans.add(TextSpan(
            text: text.substring(match.start, match.end),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
              fontWeight: FontWeight.w700,
            )));
        cursor = match.end;
      }
    }
    spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(children: spans),
        style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }

  Widget _buildSessionMenu(LlmSession session) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      key: ValueKey('session-menu-${session.id}'),
      tooltip: '会话选项：${session.title}',
      enabled: !_busy,
      position: PopupMenuPosition.under,
      icon: Icon(CupertinoIcons.ellipsis,
          size: 21, color: theme.colorScheme.onSurfaceVariant),
      color: theme.colorScheme.surface.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: .20),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: FrostedTheme.of(context).border)),
      onSelected: (action) async {
        if (!mounted) return;
        if (action == 'pin') {
          await _runAction(session.isPinned ? '取消置顶' : '置顶',
              () => widget.vm.setSessionPinned(session.id, !session.isPinned));
        } else if (action == 'rename') {
          await _rename(session);
        } else if (action == 'delete') {
          await _delete(session);
        }
      },
      itemBuilder: (_) => [
        _menuItem('pin', session.isPinned ? '取消置顶' : '置顶',
            session.isPinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin),
        _menuItem('rename', '重命名', CupertinoIcons.pencil),
        const PopupMenuDivider(),
        _menuItem('delete', '删除', CupertinoIcons.trash,
            color: _dangerColor(context)),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, String label, IconData icon,
          {Color? color}) =>
      PopupMenuItem(
        value: value,
        child: Row(children: [
          Icon(icon,
              size: 18,
              color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Flexible(child: Text(label, style: TextStyle(color: color))),
        ]),
      );
}

Color _dangerColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF8A86)
        : const Color(0xFFB3261E);

class _HistoryState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool progress;
  const _HistoryState(
      {required this.icon,
      required this.title,
      this.subtitle,
      this.action,
      this.progress = false});

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(children: [
            if (progress)
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(icon,
                  size: 26,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (action != null) action!,
          ]),
        ),
      );
}

class _RenameSessionDialog extends StatefulWidget {
  final String initialTitle;
  const _RenameSessionDialog({required this.initialTitle});

  @override
  State<_RenameSessionDialog> createState() => _RenameSessionDialogState();
}

class _RenameSessionDialogState extends State<_RenameSessionDialog> {
  late final _controller = TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isNotEmpty) Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('重命名会话'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(hintText: '输入新的会话标题'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: _controller.text.trim().isEmpty ? null : _submit,
              child: const Text('确定')),
        ],
      );
}
