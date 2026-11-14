import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_input_bar.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_message_bubble.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_message_list.dart';

class _ChatVm extends ChangeNotifier implements LlmChatViewModel {
  _ChatVm(this.items);
  List<LlmMessage> items;
  int messageReads = 0;
  final retries = <(String?, int)>[];
  final edits = <(String?, int, String)>[];
  final answers = <LlmMessage>[];
  bool get hasUiListeners => hasListeners;

  @override
  List<LlmMessage> get messages {
    messageReads++;
    return List.unmodifiable(items);
  }

  @override
  String? activeSessionId = 'session';
  @override
  bool isLoading = false;
  @override
  bool isSending = false;
  @override
  bool canStop = false;
  @override
  bool canUndoPrompt = false;
  @override
  String? errorMessage;
  @override
  String runStage = '';
  @override
  Future<bool> Function(AgentToolConfirmRequest)? onRequireConfirmation;
  @override
  LlmSession get activeSession => LlmSession(
      id: activeSessionId!,
      title: 'Test',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026));
  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<void> retryFromIndex(int index) async =>
      retries.add((activeSessionId, index));
  @override
  Future<void> editAndResend(int index, String text) async =>
      edits.add((activeSessionId, index, text));
  @override
  Future<void> answerInteraction(
          {required LlmMessage message,
          String? optionId,
          String? customAnswer}) async =>
      answers.add(message);

  void publish(List<LlmMessage> next, {String? session}) {
    items = next;
    if (session != null) activeSessionId = session;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LlmMessage _message(int id,
        {String? text,
        String session = 'session',
        LlmMessageRole role = LlmMessageRole.assistant}) =>
    LlmMessage(
      id: id,
      sessionId: session,
      role: role,
      content: text ?? 'Message $id\nA second line\nA third line',
      createdAt: DateTime(2026).add(Duration(seconds: id)),
    );

Finder _bubble(int id) => find.byWidgetPredicate(
    (widget) => widget is ChatMessageBubble && widget.message.id == id);
final _back = find.byKey(const ValueKey('chat-scroll-to-bottom'));
final _unread = find.byKey(const ValueKey('chat-unread-count'));
ScrollController _scroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView).first).controller!;

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
  expect(tester.takeException(), isNull);
}

Widget _host(_ChatVm vm,
        {EdgeInsets insets = const EdgeInsets.only(top: 60, bottom: 90),
        bool ready = true,
        bool active = true,
        Widget? child,
        bool Function(ScrollNotification)? onScroll}) =>
    MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Scaffold(
          body: NotificationListener<ScrollNotification>(
        onNotification: onScroll,
        child: child ??
            ChatMessageList(
                vm: vm, insets: insets, ready: ready, active: active),
      )),
    );

void main() {
  Future<void> pump(WidgetTester tester, _ChatVm vm,
      {Widget? child, bool Function(ScrollNotification)? onScroll}) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_host(vm, child: child, onScroll: onScroll));
    await _settle(tester);
  }

  testWidgets('stream only rebuilds changed bubble; snapshots are read once',
      (tester) async {
    final vm = _ChatVm([_message(1), _message(2)]);
    await pump(tester, vm);
    final first = tester.widget<ChatMessageBubble>(_bubble(1));
    final oldReply = tester.widget<ChatMessageBubble>(_bubble(2));
    final rebuilt = <Widget>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is ChatMessageBubble) rebuilt.add(element.widget);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    vm.messageReads = 0;
    vm.publish(
        [vm.items.first, vm.items.last.copyWith(content: 'new streamed text')]);
    await _settle(tester);
    expect(vm.messageReads, 1);
    expect(tester.widget<ChatMessageBubble>(_bubble(1)), same(first));
    expect(tester.widget<ChatMessageBubble>(_bubble(2)), isNot(same(oldReply)));
    expect(rebuilt, hasLength(1));
    expect(rebuilt.single, tester.widget<ChatMessageBubble>(_bubble(2)));
    rebuilt.clear();
    vm.notifyListeners();
    await _settle(tester);
    expect(rebuilt, isEmpty);
    // Equal values can still carry a new timeline/interaction object. Identity
    // replacement must invalidate the cached widget even without changed text.
    final equalReplacement = vm.items.first.copyWith();
    expect(equalReplacement, vm.items.first);
    vm.publish([equalReplacement, vm.items.last]);
    await _settle(tester);
    expect(tester.widget<ChatMessageBubble>(_bubble(1)), isNot(same(first)));
  });

  testWidgets(
      'small upward drag stays detached inside the former 80px threshold',
      (tester) async {
    final vm = _ChatVm(List.generate(20, _message));
    await pump(tester, vm);
    await tester.drag(find.byType(ListView), const Offset(0, 45));
    await _settle(tester);
    expect(_scroll(tester).position.extentAfter, greaterThan(0.5));
    expect(_scroll(tester).position.extentAfter, lessThan(80));
    final offset = _scroll(tester).offset;
    vm.publish(
        [...vm.items.take(19), vm.items.last.copyWith(content: 'new text')]);
    await _settle(tester);
    expect(_scroll(tester).offset, offset);
    expect(_back, findsOneWidget);
  });

  testWidgets('session loading resets unread and follows the new history',
      (tester) async {
    final vm = _ChatVm(List.generate(25, _message));
    await pump(tester, vm);
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await _settle(tester);
    vm.publish([...vm.items, _message(25)]);
    await _settle(tester);
    expect(_unread, findsOneWidget);
    vm.isLoading = true;
    vm.publish(vm.items, session: 'branch');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    vm.isLoading = false;
    vm.publish(List.generate(30, (i) => _message(i, session: 'branch')));
    await _settle(tester);
    expect(_bubble(29), findsOneWidget);
    expect(_scroll(tester).position.extentAfter, lessThan(1));
    expect(_unread, findsNothing);
    expect(_back, findsNothing);
  });

  testWidgets('inactive list defers stream builds and catches up on activation',
      (tester) async {
    final vm = _ChatVm([_message(1), _message(2)]);
    await pump(tester, vm);
    await tester.pumpWidget(_host(vm, active: false));
    await _settle(tester);
    final previous = tester.widget<ChatMessageBubble>(_bubble(2));
    vm.publish(
        [vm.items.first, vm.items.last.copyWith(content: 'background reply')]);
    await _settle(tester);
    expect(tester.widget<ChatMessageBubble>(_bubble(2)), same(previous));
    await tester.pumpWidget(_host(vm));
    await _settle(tester);
    expect(tester.widget<ChatMessageBubble>(_bubble(2)).message.content,
        'background reply');
  });

  testWidgets('initial variable-height history reaches its end and settles',
      (tester) async {
    final vm = _ChatVm(List.generate(
        80,
        (i) => _message(i,
            text:
                'Message $i\n${'a long paragraph with several words\n' * (i % 9 + 1)}')));
    await pump(tester, vm);
    expect(_scroll(tester).position.extentAfter, lessThan(1));
    expect(_bubble(79), findsOneWidget);
    expect(tester.getBottomRight(_bubble(79)).dy, lessThanOrEqualTo(510));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('multiple stream updates coalesce to one immediate tail jump',
      (tester) async {
    final vm = _ChatVm(List.generate(20, _message));
    var scrollUpdates = 0;
    await pump(tester, vm, onScroll: (n) {
      if (n.depth == 0 && n is ScrollUpdateNotification) scrollUpdates++;
      return false;
    });
    scrollUpdates = 0;
    final before = _scroll(tester).offset;
    for (var i = 0; i < 10; i++) {
      vm.publish([
        ...vm.items.take(19),
        vm.items.last.copyWith(content: 'stream\n${'new line\n' * (i + 6)}')
      ]);
    }
    await tester.pump();
    expect(_scroll(tester).offset, greaterThan(before));
    expect(scrollUpdates, 1);
    await _settle(tester);
    expect(_scroll(tester).position.extentAfter, lessThan(1));
    expect(scrollUpdates, 1);
  });

  testWidgets('upward drag cancels queued follow even near bottom',
      (tester) async {
    final vm = _ChatVm(List.generate(20, _message));
    await pump(tester, vm);
    vm.publish(
        [...vm.items.take(19), vm.items.last.copyWith(content: 'reply\n' * 8)]);
    final gesture = await tester.startGesture(const Offset(180, 240));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_back, findsOneWidget);
    final readingOffset = _scroll(tester).offset;
    vm.publish([
      ...vm.items.take(19),
      vm.items.last.copyWith(content: 'reply\n' * 12)
    ]);
    await tester.pump();
    expect(_scroll(tester).offset, readingOffset);
    await gesture.up();
    await _settle(tester);
    final afterDrag = _scroll(tester).offset;
    vm.publish([
      ...vm.items.take(19),
      vm.items.last.copyWith(content: 'reply\n' * 15)
    ]);
    await _settle(tester);
    expect(_scroll(tester).offset, afterDrag);
    expect(_unread, findsNothing);
  });

  testWidgets(
      'unread counts new messages; return animates then follows latest tail',
      (tester) async {
    final vm = _ChatVm(List.generate(20, _message));
    await pump(tester, vm);
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await _settle(tester);
    vm.publish([...vm.items, _message(20)]);
    await _settle(tester);
    expect(tester.widget<Text>(_unread).data, '1');
    for (var i = 0; i < 10; i++) {
      vm.publish(
          [...vm.items.take(20), vm.items.last.copyWith(content: 'token $i')]);
    }
    // Persisting the tentative response replaces identity but not message count.
    vm.publish(vm.items.map((m) => m.copyWith()).toList());
    await _settle(tester);
    expect(tester.widget<Text>(_unread).data, '1');
    vm.publish([...vm.items, _message(21)]);
    await _settle(tester);
    expect(tester.widget<Text>(_unread).data, '2');
    final oldOffset = _scroll(tester).offset;
    await tester.tap(_back);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_scroll(tester).offset, greaterThan(oldOffset));
    expect(_scroll(tester).position.extentAfter, greaterThan(1));
    vm.publish([...vm.items, _message(22)]);
    await _settle(tester);
    expect(_scroll(tester).position.extentAfter, lessThan(1));
    expect(_unread, findsNothing);
    expect(_back, findsNothing);
  });

  testWidgets('manual drag interrupts explicit return without later recapture',
      (tester) async {
    final vm = _ChatVm(List.generate(25, _message));
    await pump(tester, vm);
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await _settle(tester);
    await tester.tap(_back);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.drag(find.byType(ListView), const Offset(0, 80));
    await _settle(tester);
    final readingOffset = _scroll(tester).offset;
    vm.publish([...vm.items, _message(25)]);
    await _settle(tester);
    expect(_scroll(tester).offset, readingOffset);
    expect(_back, findsOneWidget);
  });

  testWidgets('insets follow only when pinned; history stays put while reading',
      (tester) async {
    final vm = _ChatVm(List.generate(25, _message));
    await pump(tester, vm);
    await tester.pumpWidget(
        _host(vm, insets: const EdgeInsets.only(top: 80, bottom: 170)));
    await _settle(tester);
    expect(_scroll(tester).position.extentAfter, lessThan(1));
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await _settle(tester);
    final readingOffset = _scroll(tester).offset;
    await tester.pumpWidget(
        _host(vm, insets: const EdgeInsets.only(top: 80, bottom: 210)));
    await _settle(tester);
    expect(_scroll(tester).offset, readingOffset);
  });

  testWidgets('cached callbacks track index, identity, and session',
      (tester) async {
    final a = _message(1, role: LlmMessageRole.user);
    final b = _message(2);
    final vm = _ChatVm([a, b]);
    await pump(tester, vm);
    final old = tester.widget<ChatMessageBubble>(_bubble(1));
    vm.publish([_message(0), a, b]);
    await _settle(tester);
    final moved = tester.widget<ChatMessageBubble>(_bubble(1));
    expect(moved.messageIndex, 1);
    old.onRetry!();
    old.onEditAndResend!('stale');
    old.onAnswerInteraction!('old', null);
    expect(vm.retries, isEmpty);
    expect(vm.edits, isEmpty);
    expect(vm.answers, isEmpty);
    moved.onRetry!();
    moved.onEditAndResend!('current');
    expect(vm.retries, [('session', 1)]);
    expect(vm.edits, [('session', 1, 'current')]);

    final replacement = a.copyWith(content: 'replaced');
    vm.publish([_message(0), replacement, b]);
    await _settle(tester);
    moved.onRetry!();
    expect(vm.retries, hasLength(1));
    final current = tester.widget<ChatMessageBubble>(_bubble(1));
    current.onAnswerInteraction!('new', null);
    expect(vm.answers.single, same(replacement));

    vm.publish([a.copyWith(sessionId: 'branch')], session: 'branch');
    await _settle(tester);
    current.onRetry!();
    expect(vm.retries, hasLength(1));
    tester.widget<ChatMessageBubble>(_bubble(1)).onRetry!();
    expect(vm.retries.last, ('branch', 0));
    expect(_unread, findsNothing);
  });

  testWidgets('large history lazily releases offscreen bubble caches',
      (tester) async {
    final vm = _ChatVm(List.generate(1000, _message));
    await pump(tester, vm);
    final lastState = tester.state(_bubble(999));
    expect(find.byType(ChatMessageBubble).evaluate().length, lessThan(25));
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await _settle(tester);
    _scroll(tester).jumpTo(0);
    await _settle(tester);
    expect(lastState.mounted, isFalse);
    expect(_bubble(0), findsOneWidget);
    expect(
        find.byType(ChatMessageBubble, skipOffstage: false).evaluate().length,
        lessThan(25));
  });

  testWidgets('VM replacement and disposal detach listeners and pending follow',
      (tester) async {
    final vm = _ChatVm([_message(1)]);
    await pump(tester, vm);
    final other = _ChatVm([_message(2)]);
    addTearDown(other.dispose);
    await tester.pumpWidget(_host(other));
    await _settle(tester);
    expect(vm.hasUiListeners, isFalse);
    expect(other.hasUiListeners, isTrue);
    vm.publish([_message(3)]);
    other.publish([_message(2), _message(4)]);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    expect(other.hasUiListeners, isFalse);
  });

  testWidgets('drawer controls and draft stay unchanged during text streaming',
      (tester) async {
    final vm = _ChatVm([_message(1), _message(2)]);
    sl.registerSingleton<LlmChatViewModel>(vm);
    addTearDown(sl.reset);
    await pump(tester, vm, child: ChatDrawer(embedded: true, onClose: () {}));
    await tester.enterText(find.byType(TextField), 'unsent draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await _settle(tester);
    final input = tester.widget<ChatInputBar>(find.byType(ChatInputBar));
    final history = tester.widget(find.byTooltip('会话历史'));
    vm.publish(
        [vm.items.first, vm.items.last.copyWith(content: 'stream update')]);
    await _settle(tester);
    expect(tester.widget<ChatInputBar>(find.byType(ChatInputBar)), same(input));
    expect(tester.widget(find.byTooltip('会话历史')), same(history));
    expect(find.text('unsent draft'), findsOneWidget);
    vm.errorMessage = 'connection failed';
    vm.notifyListeners();
    await _settle(tester);
    expect(find.text('connection failed'), findsOneWidget);
    expect(find.text('unsent draft'), findsOneWidget);
  });
}
