import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/prompt_memory_page.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/prompt_memory_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';

import '../../support/chat_memory_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatMemoryHarness harness;
  late PromptMemoryViewModel memoryViewModel;

  setUp(() async {
    harness = createChatMemoryHarness();
    await harness.viewModel.ensureInitialized();
    memoryViewModel = PromptMemoryViewModel(
      ManagePromptMemoriesUseCase(_EmptyMemoryRepository()),
    );
    sl.registerSingleton<LlmChatViewModel>(harness.viewModel);
    sl.registerSingleton<PromptMemoryViewModel>(memoryViewModel);
  });

  tearDown(() async {
    await sl.reset();
    harness.dispose();
    memoryViewModel.dispose();
  });

  Future<void> pumpChat(
    WidgetTester tester, {
    bool embedded = true,
    VoidCallback? onClose,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Scaffold(
        body: ChatDrawer(
          embedded: embedded,
          title: 'AI 助手',
          onClose: onClose ?? () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('embedded header places history left and actions right',
      (tester) async {
    await pumpChat(tester);

    expect(find.text('AI 助手'), findsNothing);
    expect(find.byTooltip('返回创作'), findsNothing);
    expect(find.byTooltip('关闭'), findsNothing);
    expect(find.text('学习记忆'), findsNothing);
    expect(tester.getCenter(find.byTooltip('会话历史')).dx, lessThan(80));
    expect(tester.getCenter(find.byTooltip('新建会话')).dx, greaterThan(200));
    expect(tester.getCenter(find.byTooltip('设置')).dx, greaterThan(260));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow history panel opens learning memories and returns',
      (tester) async {
    await pumpChat(tester);
    await tester.tap(find.byTooltip('会话历史'));
    await tester.pumpAndSettle();

    expect(find.text('会话历史'), findsOneWidget);
    expect(find.text('学习记忆'), findsOneWidget);
    expect(find.byTooltip('新对话'), findsOneWidget);
    final heading = tester.getRect(find.text('会话历史'));
    final memories = tester.getRect(find.text('学习记忆'));
    expect(memories.left, greaterThan(heading.right));
    expect((memories.center.dy - heading.center.dy).abs(), lessThan(8));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('学习记忆'));
    await tester.pumpAndSettle();
    expect(find.byType(PromptMemoryPage), findsOneWidget);
    expect(memoryViewModel.errorMessage, isNull);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('会话历史'), findsOneWidget);
    expect(find.text('学习记忆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlay chat retains its close action', (tester) async {
    var closed = false;
    await pumpChat(tester, embedded: false, onClose: () => closed = true);

    await tester.tap(find.byTooltip('关闭'));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five-line draft and attachment menu fit above a tall keyboard',
      (tester) async {
    await pumpChat(tester);
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), '一\n二\n三\n四\n五');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    expect(find.text('添加照片').hitTestable(), findsOneWidget);
    expect(find.text('画风收藏').hitTestable(), findsOneWidget);
    expect(
        tester.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });
}

class _EmptyMemoryRepository extends FakePromptMemoryRepository {
  _EmptyMemoryRepository() : super(memories: [], readFails: false);

  @override
  Future<List<PromptMemory>> getAll() async => [];

  @override
  Future<List<PromptMemory>> listPending() async => [];
}
