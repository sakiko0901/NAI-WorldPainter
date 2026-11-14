import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_message_bubble.dart';

/// Owns message updates and scrolling independently of the chat controls.
class ChatMessageList extends StatefulWidget {
  final LlmChatViewModel vm;
  final EdgeInsets insets;
  final bool ready;
  final bool active;

  const ChatMessageList({
    super.key,
    required this.vm,
    required this.insets,
    this.ready = true,
    this.active = true,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final _scrollController = ScrollController();
  late List<LlmMessage> _messages;
  String? _sessionId;
  bool _loading = false;
  bool _following = true;
  bool _manualScroll = false;
  bool _followScheduled = false;
  bool _returningToBottom = false;
  int _scrollGeneration = 0;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _readInitialState();
    widget.vm.addListener(_onVmChanged);
    _scheduleFollow();
  }

  void _readInitialState() {
    _messages = widget.vm.messages;
    _sessionId = widget.vm.activeSessionId;
    _loading = widget.vm.isLoading;
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vm, widget.vm)) {
      oldWidget.vm.removeListener(_onVmChanged);
      widget.vm.addListener(_onVmChanged);
      _readInitialState();
      _resetFollowing();
    }
    if (oldWidget.insets != widget.insets ||
        oldWidget.ready != widget.ready ||
        oldWidget.active != widget.active ||
        !identical(oldWidget.vm, widget.vm)) {
      _scheduleFollow();
    }
  }

  void _resetFollowing() {
    _following = true;
    _manualScroll = false;
    _returningToBottom = false;
    _unreadCount = 0;
    _scrollGeneration++;
  }

  void _onVmChanged() {
    // The VM getter copies the list: read it once per notification, never from
    // itemBuilder. Compare identity, not Equatable's recursive message equality.
    final next = widget.vm.messages;
    final sessionId = widget.vm.activeSessionId;
    final loading = widget.vm.isLoading;
    final sessionChanged = sessionId != _sessionId;
    final messagesChanged = next.length != _messages.length ||
        Iterable<int>.generate(next.length)
            .any((i) => !identical(next[i], _messages[i]));
    if (!sessionChanged && !messagesChanged && loading == _loading) return;

    if (sessionChanged) {
      _resetFollowing();
    } else if (!_loading && !loading) {
      if (next.length < _messages.length) {
        _unreadCount = 0;
      } else if (!_following) {
        // Tokens and replacement of a tentative message by its persisted row
        // do not add messages. Count only newly appended conversation entries.
        _unreadCount += next.length - _messages.length;
      }
    }
    _messages = next;
    _sessionId = sessionId;
    _loading = loading;
    if (widget.active) setState(() {});
    _scheduleFollow();
  }

  void _scheduleFollow() {
    if (_followScheduled || !_following || !widget.active) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted ||
          !widget.ready ||
          !widget.active ||
          _loading ||
          !_following ||
          _manualScroll ||
          _returningToBottom ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      if ((position.maxScrollExtent - position.pixels).abs() > 0.5) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final userStarted = notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final userMoved = notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    if (userStarted || userMoved) {
      _manualScroll = true;
      _returningToBottom = false;
      _scrollGeneration++;
      if (_following) setState(() => _following = false);
    }
    if (notification is ScrollEndNotification && _manualScroll) {
      _manualScroll = false;
      // An upward drag within the old 80px threshold still means "let me read".
      if (notification.metrics.extentAfter <= 0.5) {
        setState(() {
          _following = true;
          _unreadCount = 0;
        });
        _scheduleFollow();
      }
    }
    return false;
  }

  Future<void> _returnToBottom() async {
    if (!_scrollController.hasClients) return;
    final generation = ++_scrollGeneration;
    setState(() {
      _following = true;
      _manualScroll = false;
      _returningToBottom = true;
      _unreadCount = 0;
    });
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    if (!mounted || generation != _scrollGeneration) return;
    _returningToBottom = false;
    // The reply or composer may have grown during this explicit animation.
    _scheduleFollow();
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onVmChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ready || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return Padding(
        padding: widget.insets,
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.wand_stars,
                        size: 34,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text('请阐述你的梦',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            height: 1.6,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ]),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Stack(children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _scheduleFollow();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            key: ValueKey((widget.vm, _sessionId)),
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
                12, widget.insets.top, 12, widget.insets.bottom),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return _MessageItem(
                key: ValueKey((
                  message.sessionId,
                  message.id ?? message.createdAt,
                  message.role
                )),
                vm: widget.vm,
                message: message,
                index: index,
              );
            },
          ),
        ),
      ),
      if (!_following)
        Positioned(
          right: 12,
          bottom: widget.insets.bottom + 4,
          child: FloatingActionButton(
            key: const ValueKey('chat-scroll-to-bottom'),
            tooltip: '返回底部',
            mini: true,
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.92),
            shape: CircleBorder(
              side: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
            elevation: 0,
            onPressed: _returnToBottom,
            child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(CupertinoIcons.arrow_down,
                      size: 18, color: theme.colorScheme.onSurface),
                  if (_unreadCount > 0)
                    Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.redAccent, shape: BoxShape.circle),
                          constraints:
                              const BoxConstraints(minWidth: 14, minHeight: 14),
                          child: Text(_unreadCount > 9 ? '9+' : '$_unreadCount',
                              key: const ValueKey('chat-unread-count'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        )),
                ]),
          ),
        ),
    ]);
  }
}

/// One cached bubble per lazily mounted list item, released with that item.
/// No history-sized widget map; Flutter retains only its viewport/cache items
/// (and the usual focused/selected item keep-alive).
class _MessageItem extends StatefulWidget {
  final LlmChatViewModel vm;
  final LlmMessage message;
  final int index;

  const _MessageItem(
      {super.key,
      required this.vm,
      required this.message,
      required this.index});

  @override
  State<_MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<_MessageItem> {
  late ChatMessageBubble _bubble;

  @override
  void initState() {
    super.initState();
    _createBubble();
  }

  @override
  void didUpdateWidget(covariant _MessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vm, widget.vm) ||
        !identical(oldWidget.message, widget.message) ||
        oldWidget.index != widget.index) {
      _createBubble();
    }
  }

  void _createBubble() {
    final vm = widget.vm;
    final message = widget.message;
    final index = widget.index;
    bool isCurrent() {
      if (!mounted || vm.activeSessionId != message.sessionId) return false;
      final messages = vm.messages;
      return index < messages.length && identical(messages[index], message);
    }

    _bubble = ChatMessageBubble(
      message: message,
      messageIndex: index,
      onRetry: message.role == LlmMessageRole.user
          ? () {
              if (isCurrent()) vm.retryFromIndex(index);
            }
          : null,
      onEditAndResend: message.role == LlmMessageRole.user
          ? (text) {
              if (isCurrent()) vm.editAndResend(index, text);
            }
          : null,
      onAnswerInteraction: (optionId, customAnswer) {
        if (isCurrent()) {
          vm.answerInteraction(
              message: message, optionId: optionId, customAnswer: customAnswer);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => _bubble;
}
