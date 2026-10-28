import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/prompt_template.dart';
import 'package:nai_huishi/domain/repositories/prompt_template_repository.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_templates.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/generate_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/prompt_editor_field.dart';
import 'package:nai_huishi/presentation/widgets/prompt_notebook_dialog.dart';

import '../../support/frontend_generation_fake.dart';

void main() {
  late _NotebookRepository repository;
  late ManagePromptTemplatesUseCase templates;
  late FrontendGenerationFake vm;
  String? clipboard;
  setUp(() {
    repository = _NotebookRepository();
    templates = ManagePromptTemplatesUseCase(repository);
    vm = FrontendGenerationFake();
    sl.registerSingleton<GenerationViewModel>(vm);
    sl.registerSingleton<ManagePromptTemplatesUseCase>(templates);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await sl.reset();
    vm.dispose();
  });

  testWidgets(
      'creation heading opens persistent searchable notebook and imports safely',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    vm.prompt = 'masterpiece,  ';
    vm.negativePrompt = 'blurry';
    await tester.pumpWidget(_host(const GeneratePage()));
    await tester.pumpAndSettle();
    final notebook = find.byKey(const ValueKey('positive-prompt-notebook'));
    final copy = find.byKey(const ValueKey('positive-prompt-copy'));
    final expand = find.byKey(const ValueKey('positive-prompt-expand'));
    await tester.ensureVisible(notebook);
    expect(tester.getCenter(notebook).dx, lessThan(tester.getCenter(copy).dx));
    expect(tester.getCenter(copy).dx, lessThan(tester.getCenter(expand).dx));
    expect(tester.getCenter(notebook).dy, tester.getCenter(expand).dy);
    expect(
        tester
            .widget<PromptEditorField>(find.byType(PromptEditorField).first)
            .showExpandButton,
        isFalse);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboard, 'masterpiece,  ');
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(notebook);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notebook-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notebook-save')));
    await tester.pump();
    expect(find.text('请填写标题'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('notebook-title')), '柔和逆光');
    await tester.enterText(find.byKey(const ValueKey('notebook-content')),
        'backlighting, {{soft lighting}}');
    await tester.tap(find.byKey(const ValueKey('notebook-save')));
    await tester.pumpAndSettle();
    expect(find.text('柔和逆光'), findsOneWidget);
    expect(find.text('backlighting, {{soft lighting}}'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭笔记本'));
    await tester.pumpAndSettle();
    await tester.tap(notebook);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('notebook-search')), 'BACKLIGHTING');
    await tester.pumpAndSettle();
    expect(find.text('柔和逆光'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notebook-copy-1')));
    await tester.pumpAndSettle();
    expect(clipboard, 'backlighting, {{soft lighting}}');
    await tester.tap(find.byKey(const ValueKey('notebook-import-1')));
    await tester.pumpAndSettle();
    expect(vm.prompt, 'masterpiece, backlighting, {{soft lighting}}');
    expect(vm.negativePrompt, 'blurry');
    await tester.enterText(
        find.byKey(const ValueKey('notebook-search')), '不存在的词');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的笔记'), findsOneWidget);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('柔和逆光'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('notebook-title')), '逆光组合');
    await tester.tap(find.byKey(const ValueKey('notebook-save')));
    await tester.pumpAndSettle();
    expect(repository.entries.single.name, '逆光组合');
    await tester.tap(find.byTooltip('管理笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(repository.entries, isEmpty);
    await tester.tap(find.byTooltip('关闭笔记本'));
    await tester.pumpAndSettle();
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('save failure retains draft and notebook fits enlarged text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 852);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
            onPressed: () => showPromptNotebook(
                context: context, templates: templates, onImport: (_) async {}),
            child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notebook-add')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('notebook-title')), '蓝色眼睛');
    await tester.enterText(
        find.byKey(const ValueKey('notebook-content')), 'blue eyes');
    repository.failSave = true;
    await tester.ensureVisible(find.byKey(const ValueKey('notebook-save')));
    await tester.tap(find.byKey(const ValueKey('notebook-save')));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，内容已保留，请重试'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('notebook-content')))
            .controller!
            .text,
        'blue eyes');
    repository.failSave = false;
    await tester.ensureVisible(find.byKey(const ValueKey('notebook-save')));
    await tester.tap(find.byKey(const ValueKey('notebook-save')));
    await tester.pumpAndSettle();
    expect(find.text('蓝色眼睛'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing while notes load does not publish into disposed dialog',
      (tester) async {
    repository.loadGate = Completer<List<PromptTemplate>>();
    await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
            onPressed: () => showPromptNotebook(
                context: context, templates: templates, onImport: (_) async {}),
            child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('关闭笔记本'));
    await tester.pump(const Duration(milliseconds: 300));
    repository.loadGate!.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(PromptNotebookDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture notebook and prompt actions for mobile visual QA',
      (tester) async {
    if (!const bool.fromEnvironment('FRONTEND_CAPTURE')) return;
    final fontPath = Platform.environment['FRONTEND_QA_FONT'];
    if (fontPath != null) {
      final bytes = File(fontPath).readAsBytesSync();
      for (final family in ['Roboto', 'Microsoft YaHei']) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    for (final pair in [
      (
        '柔和逆光',
        'backlighting, {{soft lighting}}, warm rim light, floating petals'
      ),
      ('蓝色眼睛', 'blue eyes'),
      (
        '电影氛围',
        'cinematic lighting, depth of field, soft shadows, detailed background'
      ),
    ]) {
      final now = DateTime.now();
      await templates.create(PromptTemplate(
          name: pair.$1,
          category: '笔记本',
          content: pair.$2,
          createdAt: now,
          updatedAt: now));
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    vm.prompt = 'masterpiece, best quality, 1girl, silver hair, blue eyes';
    vm.negativePrompt = 'lowres, bad anatomy, blurry';
    final screenKey = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: screenKey, child: _host(const GeneratePage())));
    await tester.pumpAndSettle();
    await _capture(tester, screenKey, 'prompt-actions.png');
    await tester.tap(find.byKey(const ValueKey('positive-prompt-notebook')));
    await tester.pumpAndSettle();
    await _capture(tester, screenKey, 'prompt-notebook.png');
    await tester.tap(find.byKey(const ValueKey('notebook-add')));
    await tester.pumpAndSettle();
    await _capture(tester, screenKey, 'prompt-notebook-editor.png');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/frontend-preview/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Scaffold(body: child),
    );

class _NotebookRepository implements PromptTemplateRepository {
  final List<PromptTemplate> entries = [];
  int nextId = 0;
  bool failSave = false;
  Completer<List<PromptTemplate>>? loadGate;
  @override
  Future<List<PromptTemplate>> getAllTemplates() async {
    if (loadGate != null) return await loadGate!.future;
    return List.of(entries);
  }

  @override
  Future<PromptTemplate> createTemplate(PromptTemplate entry) async {
    if (failSave) throw StateError('storage unavailable');
    final saved = entry.copyWith(id: ++nextId);
    entries.add(saved);
    return saved;
  }

  @override
  Future<PromptTemplate> updateTemplate(PromptTemplate entry) async {
    if (failSave) throw StateError('storage unavailable');
    entries[entries.indexWhere((item) => item.id == entry.id)] = entry;
    return entry;
  }

  @override
  Future<void> deleteTemplate(int id) async =>
      entries.removeWhere((item) => item.id == id);
  @override
  Future<void> incrementUseCount(int id) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
