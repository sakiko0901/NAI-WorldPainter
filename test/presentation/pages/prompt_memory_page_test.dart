import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/prompt_memory.dart';
import 'package:nai_huishi/domain/repositories/prompt_memory_repository.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/prompt_memory_page.dart';
import 'package:nai_huishi/presentation/viewmodels/prompt_memory_viewmodel.dart';

void main() {
  late PromptMemoryViewModel viewModel;
  late _FakePromptMemoryRepository repository;

  setUp(() {
    repository = _FakePromptMemoryRepository([
      PromptMemory(
        id: 1,
        trigger: '纳西妲 | Nahida',
        content: '白色披肩与绿色连衣裙',
        type: PromptMemoryType.characterOutfit,
        source: PromptMemorySource.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ]);
    viewModel = PromptMemoryViewModel(
      ManagePromptMemoriesUseCase(repository),
    );
    sl.registerSingleton<PromptMemoryViewModel>(viewModel);
  });

  tearDown(() async {
    await sl.reset();
    viewModel.dispose();
  });

  testWidgets('keeps the editor open and reports repository validation errors',
      (tester) async {
    repository.saveThrows = true;
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: const PromptMemoryPage(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('纳西妲 | Nahida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('保存失败：角色穿搭字段验证失败'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 让浮动提示完成 1.4 秒停留与淡出移除，避免测试留下 pending timer。
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'outfit aliases editor stays scrollable on a narrow keyboard viewport',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: const PromptMemoryPage(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('纳西妲 | Nahida'));
    await tester.pumpAndSettle();

    final dialog = find.byType(CupertinoAlertDialog);
    expect(find.text('编辑记忆'), findsOneWidget);
    expect(find.text('角色标准穿搭'), findsOneWidget);
    expect(find.text('标准穿搭描述'), findsOneWidget);
    expect(find.text('别名（多个用 | 分隔）'), findsOneWidget);

    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(3));
    await tester.ensureVisible(fields.at(1));
    await tester.tap(fields.at(1));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('opens editor with a full-length trigger and no aliases',
      (tester) async {
    final fullLengthTrigger = List<String>.filled(512, 'x').join();
    expect(fullLengthTrigger.length, 512);
    repository.replaceTrigger(fullLengthTrigger);

    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: const PromptMemoryPage(),
    ));
    await tester.pumpAndSettle();

    final tile = find.byType(ListTile).first;
    await tester.ensureVisible(tile);
    final tileRect = tester.getRect(tile);
    await tester.tapAt(Offset(tileRect.left + 12, tileRect.top + 12));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(CupertinoAlertDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(3));
    expect(tester.widget<TextField>(fields.at(0)).maxLength, 512);
    expect(tester.widget<TextField>(fields.at(1)).maxLength, 512);
    expect(tester.takeException(), isNull);
  });
}

class _FakePromptMemoryRepository implements PromptMemoryRepository {
  _FakePromptMemoryRepository(List<PromptMemory> memories)
      : _memories = List.of(memories);

  final List<PromptMemory> _memories;
  bool saveThrows = false;

  void replaceTrigger(String trigger) {
    _memories[0] = _memories[0].copyWith(trigger: trigger);
  }

  @override
  Future<List<PromptMemory>> getAll() async => List.of(_memories);

  @override
  Future<List<PromptMemory>> search(String query) async =>
      _memories.where((memory) => memory.trigger.contains(query)).toList();

  @override
  Future<List<PromptMemory>> matchText(String text) async =>
      _memories.where((memory) => memory.isRetrievable).toList();

  @override
  Future<PromptMemory> save(PromptMemory memory) async {
    if (saveThrows) throw ArgumentError('角色穿搭字段验证失败');
    if (memory.id == null) {
      final saved = memory.copyWith(id: _memories.length + 1);
      _memories.add(saved);
      return saved;
    }
    final index = _memories.indexWhere((row) => row.id == memory.id);
    if (index < 0) throw StateError('missing memory');
    _memories[index] = memory;
    return memory;
  }

  @override
  Future<PromptMemory> promotePending(
    int id, {
    String? newTrigger,
    String? newContent,
    PromptMemoryType? newType,
  }) async {
    final index = _memories.indexWhere((row) => row.id == id);
    if (index < 0) throw StateError('missing memory');
    final promoted = _memories[index].copyWith(
      trigger: newTrigger,
      content: newContent,
      type: newType,
      source: PromptMemorySource.llmCandidate,
    );
    _memories[index] = promoted;
    return promoted;
  }

  @override
  Future<void> delete(int id) async {
    _memories.removeWhere((memory) => memory.id == id);
  }

  @override
  Future<void> incrementHit(int id) async {}

  @override
  Future<List<PromptMemory>> findConflicts(String trigger) async => const [];

  @override
  Future<List<PromptMemory>> listPending() async => _memories
      .where(
          (memory) => memory.source == PromptMemorySource.pendingLlmCandidate)
      .toList();

  @override
  Future<List<PromptMemory>> listStale(
          {Duration olderThan = const Duration(days: 90)}) async =>
      const [];
}
