import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_session_search_result.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_sessions_panel.dart';

import '../../support/session_history_fake.dart';

const _previewDirectory = String.fromEnvironment('UI_PREVIEW_DIR');
const _previewFont = String.fromEnvironment('UI_PREVIEW_FONT');
final _search = find.byKey(const ValueKey('session-history-search'));
final _list = find.byKey(const ValueKey('session-history-list'));
Finder _row(String id) => find.byKey(ValueKey('session-row-$id'));
Finder _menu(String id) => find.byKey(ValueKey('session-menu-$id'));

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_previewDirectory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_previewDirectory).create(recursive: true);
    await File('$_previewDirectory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<GlobalKey> _open(
  WidgetTester tester,
  SessionHistoryFake vm, {
  Size size = const Size(320, 640),
  Brightness brightness = Brightness.dark,
  double scale = 1,
  bool highContrast = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(vm.dispose);
  final key = GlobalKey();
  var theme = buildNaiHuishiTheme(brightness);
  if (_previewFont.isNotEmpty) {
    theme =
        theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Preview'));
  }
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), highContrast: highContrast),
        child: child!,
      ),
      home: Scaffold(
          body: Builder(
              builder: (context) => Center(
                    child: TextButton(
                        onPressed: () => showChatSessionsPanel(context, vm: vm),
                        child: const Text('打开历史')),
                  ))),
    ),
  ));
  await tester.tap(find.text('打开历史'));
  await tester.pumpAndSettle();
  return key;
}

Future<void> _choose(WidgetTester tester, String id, String label) async {
  await tester.ensureVisible(_menu(id));
  await tester.tap(_menu(id));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<String>, label));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_previewFont.isEmpty) return;
    final loader = FontLoader('Preview')
      ..addFont(File(_previewFont).readAsBytes().then(ByteData.sublistView));
    await loader.load();
    for (final entry in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/CupertinoIcons':
          'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });

  testWidgets('search waits 200ms and ignores older successes and failures',
      (tester) async {
    final a = Completer<List<LlmSessionSearchResult>>();
    final b = Completer<List<LlmSessionSearchResult>>();
    final vm = SessionHistoryFake([historySession('base')])
      ..onSearch = (q) => q == 'alpha' ? a.future : b.future;
    await _open(tester, vm);
    await tester.enterText(_search, 'alpha');
    await tester.pump(const Duration(milliseconds: 199));
    expect(vm.searchQueries, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(vm.searchQueries, ['alpha']);
    await tester.enterText(_search, 'beta');
    a.complete([LlmSessionSearchResult(session: historySession('stale'))]);
    await tester.pump();
    expect(_row('stale'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    b.complete([LlmSessionSearchResult(session: historySession('fresh'))]);
    await tester.pumpAndSettle();
    expect(_row('fresh'), findsOneWidget);
    expect(_row('base'), findsNothing);

    final old = Completer<List<LlmSessionSearchResult>>();
    vm.onSearch = (q) => q == 'old' ? old.future : Future.value([]);
    await tester.enterText(_search, 'old');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(_search, 'new');
    await tester.pump(const Duration(milliseconds: 200));
    old.completeError(StateError('stale failure'));
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的会话'), findsOneWidget);
    expect(find.text('搜索失败，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'clearing search invalidates in-flight results and restores sessions',
      (tester) async {
    final pending = Completer<List<LlmSessionSearchResult>>();
    final vm = SessionHistoryFake([historySession('base')])
      ..onSearch = (_) => pending.future;
    await _open(tester, vm);
    await tester.enterText(_search, 'pending');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(_row('base'), findsOneWidget);
    pending
        .complete([LlmSessionSearchResult(session: historySession('stale'))]);
    await tester.pumpAndSettle();
    expect(_row('stale'), findsNothing);
    expect(find.byTooltip('清除搜索'), findsNothing);
    expect(vm.searchQueries, ['pending']);
  });

  testWidgets(
      'failed search retries and highlights literal case-insensitive matches',
      (tester) async {
    var attempts = 0;
    final vm = SessionHistoryFake([])
      ..onSearch = (_) async {
        if (++attempts == 1) throw StateError('offline');
        return [
          LlmSessionSearchResult(
            session: historySession('hit', title: 'Use A+b[ softly'),
            snippet: '正文匹配 a+B[ 的光线',
          )
        ];
      };
    await _open(tester, vm);
    await tester.enterText(_search, 'a+b[');
    await tester.pumpAndSettle();
    expect(find.text('搜索失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试搜索'));
    await tester.pumpAndSettle();
    expect(vm.searchQueries, ['a+b[', 'a+b[']);
    expect(_row('hit'), findsOneWidget);
    for (final text in ['Use A+b[ softly', '正文匹配 a+B[ 的光线']) {
      final widget = tester.widget<Text>(find.text(text));
      final spans =
          (widget.textSpan! as TextSpan).children!.whereType<TextSpan>();
      expect(
          spans.where((s) => s.style?.backgroundColor != null), hasLength(1));
    }
  });

  testWidgets('empty history and no matches have distinct recoverable states',
      (tester) async {
    final vm = SessionHistoryFake([]);
    await _open(tester, vm);
    expect(find.text('还没有会话'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('clear-session-history')))
            .onPressed,
        isNull);
    vm.replaceSessions([historySession('base')]);
    await tester.pumpAndSettle();
    await tester.enterText(_search, 'nothing');
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的会话'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(_row('base'), findsOneWidget);
  });

  testWidgets(
      'closing the panel cancels debounce and safely discards pending errors',
      (tester) async {
    final vm = SessionHistoryFake([]);
    await _open(tester, vm);
    await tester.enterText(_search, 'debounced');
    Navigator.of(tester.element(_search)).pop();
    await tester.pumpAndSettle();
    // A route remains mounted until its reverse transition completes, so only
    // assert that no later requests or exceptions occur after disposal.
    final calls = vm.searchQueries.length;
    await tester.pump(const Duration(seconds: 1));
    expect(vm.searchQueries, hasLength(calls));
    expect(tester.takeException(), isNull);

    final pending = Completer<List<LlmSessionSearchResult>>();
    vm.onSearch = (_) => pending.future;
    await tester.tap(find.text('打开历史'));
    await tester.pumpAndSettle();
    await tester.enterText(_search, 'pending');
    await tester.pump(const Duration(milliseconds: 200));
    Navigator.of(tester.element(_search)).pop();
    await tester.pumpAndSettle();
    pending.completeError(StateError('late'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stream notifications preserve list widget and do not restart search',
      (tester) async {
    final vm = SessionHistoryFake([historySession('base')]);
    await _open(tester, vm);
    final initial = tester.widget<CustomScrollView>(_list);
    for (var i = 0; i < 30; i++) {
      vm.notifyListeners();
      await tester.pump();
    }
    expect(identical(initial, tester.widget<CustomScrollView>(_list)), isTrue);
    await tester.enterText(_search, '会话');
    await tester.pumpAndSettle();
    final searched = tester.widget<CustomScrollView>(_list);
    for (var i = 0; i < 30; i++) {
      vm.notifyListeners();
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(identical(searched, tester.widget<CustomScrollView>(_list)), isTrue);
    expect(vm.searchQueries, ['会话']);
    vm.activeSessionId = 'base';
    vm.notifyListeners();
    await tester.pump();
    expect(
        identical(searched, tester.widget<CustomScrollView>(_list)), isFalse);
    vm.replaceSessions([historySession('base', title: '会话已修改')]);
    await tester.pumpAndSettle();
    expect(vm.searchQueries, ['会话', '会话']);
    expect(find.text('会话已修改'), findsOneWidget);
  });

  testWidgets('large history builds lazily and can reach the last entry',
      (tester) async {
    final now = DateTime.now();
    final vm = SessionHistoryFake(List.generate(
        1000,
        (i) => historySession('$i',
            updatedAt: now.subtract(Duration(minutes: i + 1)))));
    await _open(tester, vm);
    expect(_row('0'), findsOneWidget);
    expect(_row('999'), findsNothing);
    final built = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('session-row-'));
    expect(built.evaluate().length, lessThan(20));
    final scroll = tester.widget<CustomScrollView>(_list).controller!;
    for (var i = 0; i < 5 && _row('999').evaluate().isEmpty; i++) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(_row('999'), findsOneWidget);
    expect(built.evaluate().length, lessThan(25));
    expect(tester.takeException(), isNull);
  });

  testWidgets('anchored menu pins and unpins without changing updatedAt',
      (tester) async {
    final old = historySession('old', updatedAt: DateTime(2025));
    final vm = SessionHistoryFake([old, historySession('new')]);
    await _open(tester, vm);
    final anchor = tester.getRect(_menu('old'));
    await tester.tap(_menu('old'));
    await tester.pumpAndSettle();
    final pin =
        tester.getRect(find.widgetWithText(PopupMenuItem<String>, '置顶'));
    expect(pin.top, greaterThanOrEqualTo(anchor.top));
    expect(pin.left, lessThan(anchor.right));
    expect(find.byIcon(CupertinoIcons.pin), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.pencil), findsOneWidget);
    expect(tester.widget<Text>(find.text('删除')).style!.color,
        const Color(0xFFFF8A86));
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(vm.data.firstWhere((s) => s.id == 'old').isPinned, isTrue);
    expect(vm.data.firstWhere((s) => s.id == 'old').updatedAt, old.updatedAt);
    expect(tester.getTopLeft(_row('old')).dy,
        lessThan(tester.getTopLeft(_row('new')).dy));
    await _choose(tester, 'old', '取消置顶');
    expect(vm.data.firstWhere((s) => s.id == 'old').isPinned, isFalse);
    expect(tester.getTopLeft(_row('new')).dy,
        lessThan(tester.getTopLeft(_row('old')).dy));
  });

  testWidgets('pin failure is visible and a retry succeeds', (tester) async {
    final vm = SessionHistoryFake([historySession('base')])
      ..failures.add('pin:base:true');
    await _open(tester, vm);
    await _choose(tester, 'base', '置顶');
    expect(find.text('置顶失败，请重试。').hitTestable(), findsOneWidget);
    expect(vm.data.single.isPinned, isFalse);
    vm.failures.clear();
    await _choose(tester, 'base', '置顶');
    expect(vm.data.single.isPinned, isTrue);
    expect(find.text('置顶失败，请重试。'), findsNothing);
  });

  testWidgets(
      'rename rejects blank titles, trims and supports keyboard submission',
      (tester) async {
    final vm = SessionHistoryFake([historySession('base')]);
    await _open(tester, vm);
    await _choose(tester, 'base', '重命名');
    final input = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(input, '   ');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确定'))
            .onPressed,
        isNull);
    await tester.enterText(input, '  新的标题  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(vm.actions, ['rename:base:新的标题']);
    expect(find.text('新的标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename failure remains visible without dismissing history',
      (tester) async {
    final vm = SessionHistoryFake([historySession('base')])
      ..failures.add('rename:base:changed');
    await _open(tester, vm);
    await _choose(tester, 'base', '重命名');
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'changed');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('重命名失败，请重试。').hitTestable(), findsOneWidget);
    expect(_row('base'), findsOneWidget);
  });

  testWidgets(
      'delete confirms, cancels, reports failure and keeps the panel open',
      (tester) async {
    final vm = SessionHistoryFake([historySession('base')]);
    await _open(tester, vm);
    await _choose(tester, 'base', '删除');
    expect(vm.actions, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(_row('base'), findsOneWidget);
    vm.failures.add('delete:base');
    await _choose(tester, 'base', '删除');
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除会话失败，请重试。').hitTestable(), findsOneWidget);
    vm.failures.clear();
    await _choose(tester, 'base', '删除');
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(_row('base'), findsNothing);
    expect(find.text('会话历史'), findsOneWidget);
  });

  testWidgets(
      'clear history stays behind confirmation and closes only on success',
      (tester) async {
    final vm = SessionHistoryFake([historySession('base')]);
    await _open(tester, vm);
    await tester.tap(find.text('清空历史'));
    await tester.pumpAndSettle();
    expect(find.text('清空所有历史会话'), findsOneWidget);
    expect(vm.actions, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    vm.failures.add('clear');
    await tester.tap(find.text('清空历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();
    expect(find.text('清空历史失败，请重试。').hitTestable(), findsOneWidget);
    vm.failures.clear();
    await tester.tap(find.text('清空历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();
    expect(find.text('会话历史'), findsNothing);
    expect(vm.data, isEmpty);
  });

  testWidgets('selection failure and busy sending keep history open',
      (tester) async {
    final vm = SessionHistoryFake([historySession('base')])
      ..failures.add('select:base');
    await _open(tester, vm);
    await tester.tap(find.text('会话 base'));
    await tester.pumpAndSettle();
    expect(find.text('切换会话失败，请重试。'), findsOneWidget);
    vm.failures.clear();
    vm.isSending = true;
    vm.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('会话 base'));
    await tester.pumpAndSettle();
    expect(find.text('请先停止当前操作，再切换会话。'), findsOneWidget);
    expect(vm.actions, ['select:base']);
    vm.isSending = false;
    vm.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('会话 base'));
    await tester.pumpAndSettle();
    expect(find.text('会话历史'), findsNothing);
    expect(vm.activeSessionId, 'base');
  });

  testWidgets('search refreshes after pin and discards prior snapshot',
      (tester) async {
    final vm = SessionHistoryFake([historySession('base')]);
    await _open(tester, vm);
    await tester.enterText(_search, '会话');
    await tester.pumpAndSettle();
    await _choose(tester, 'base', '置顶');
    expect(vm.searchQueries, ['会话', '会话']);
    expect(find.text('置顶'), findsOneWidget);
    await _choose(tester, 'base', '重命名');
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '不再匹配');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的会话'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('320px header, timeline, search and menu preview $brightness',
        (tester) async {
      final now = DateTime.now();
      final vm = SessionHistoryFake([
        historySession('pin',
            title: '人像光影 · 常用提示词',
            updatedAt: now.subtract(const Duration(days: 3)),
            pinnedAt: now),
        historySession('today',
            title: '海边的柔和逆光',
            updatedAt: now.subtract(const Duration(minutes: 15))),
        historySession('yesterday',
            title: '让头发边缘透一点光',
            updatedAt: DateTime(now.year, now.month, now.day - 1, 16)),
        historySession('week',
            title: '灰色调与安静的街道',
            updatedAt: DateTime(now.year, now.month, now.day - 4, 16)),
        historySession('month',
            title: '旧画作的构图与配色',
            updatedAt: DateTime(now.year, now.month - 1, 8)),
      ])
        ..activeSessionId = 'today';
      final key = await _open(tester, vm,
          brightness: brightness, size: const Size(320, 760));
      final heading = tester.getRect(find.text('会话历史'));
      final memory = tester.getRect(find.text('学习记忆'));
      expect(memory.left, greaterThan(heading.right));
      expect((heading.center.dy - memory.center.dy).abs(), lessThan(8));
      expect(find.byTooltip('新对话'), findsOneWidget);
      final theme = Theme.of(tester.element(_row('today')));
      final glass = FrostedTheme.of(tester.element(_row('today')));
      final selection = tester
          .widget<Material>(find
              .descendant(of: _row('today'), matching: find.byType(Material))
              .first)
          .color!;
      final surface =
          Color.alphaBlend(glass.raised, theme.scaffoldBackgroundColor);
      final background = Color.alphaBlend(selection, surface);
      final foreground =
          tester.widget<Text>(find.text('海边的柔和逆光')).style!.color!;
      final a = foreground.computeLuminance() + .05;
      final b = background.computeLuminance() + .05;
      expect(a > b ? a / b : b / a, greaterThan(4.5),
          reason: 'selected session must remain readable in both themes');
      await _capture(tester, key, 'history-${brightness.name}-320');
      await tester.tap(_menu('today'));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'history-menu-${brightness.name}');
      Navigator.of(tester.element(find.text('重命名'))).pop();
      await tester.pumpAndSettle();
      vm.onSearch = (_) async => [
            LlmSessionSearchResult(
                session: vm.data[1], snippet: '加入柔和逆光，让头发边缘有淡淡的光晕。')
          ];
      await tester.enterText(_search, '逆光');
      await tester.pumpAndSettle();
      await _capture(tester, key, 'history-search-${brightness.name}');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '320px large text and tall keyboard remain scrollable $brightness',
        (tester) async {
      final vm = SessionHistoryFake(
          [historySession('base', title: '这是一段很长的会话标题，在窄屏和大字下也可以阅读')]);
      final key = await _open(tester, vm,
          scale: 2, brightness: brightness, size: const Size(320, 640));
      await _capture(tester, key, 'history-large-${brightness.name}');
      await tester.tap(_search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_search);
      await tester.pumpAndSettle();
      expect(tester.getRect(_search).bottom, lessThanOrEqualTo(340));
      await _capture(tester, key, 'history-keyboard-${brightness.name}');
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await tester.ensureVisible(_menu('base'));
      await tester.tap(_menu('base'));
      await tester.pumpAndSettle();
      expect(find.text('重命名').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('high contrast uses solid surface and disables panel blur',
      (tester) async {
    final vm = SessionHistoryFake([]);
    await _open(tester, vm, highContrast: true);
    final filters =
        tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
    expect(filters, isNotEmpty);
    expect(filters.every((filter) => !filter.enabled), isTrue);
    expect(tester.takeException(), isNull);
  });
}
