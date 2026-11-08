import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/slow_selection_scroll.dart';

void main() {
  testWidgets(
      'native long-press drag keeps scrolling slowly while held at the edge',
      (tester) async {
    final controller = TextEditingController(
        text: List.generate(80, (i) => 'line $i for selection').join('\n'));
    final scroll = ScrollController();
    final pageScroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    addTearDown(pageScroll.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SlowSelectionScroll(child: child!),
      home: Scaffold(
        body: SingleChildScrollView(
          controller: pageScroll,
          child: Column(
            children: [
              SizedBox(
                width: 300,
                height: 180,
                child: TextField(
                  controller: controller,
                  scrollController: scroll,
                  maxLines: null,
                  expands: true,
                ),
              ),
              const SizedBox(height: 700),
            ],
          ),
        ),
      ),
    ));
    final box = tester.getRect(find.byType(TextField));
    final gesture =
        await tester.startGesture(box.topLeft + const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(Offset(box.center.dx, box.bottom - 8));
    await tester.pump(const Duration(milliseconds: 32));
    final before = scroll.offset;
    final selectedBefore = controller.selection.extentOffset;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.offset, greaterThan(before));
    expect(scroll.offset - before, lessThan(80));
    expect(pageScroll.offset, 0);
    expect(controller.selection.extentOffset,
        greaterThanOrEqualTo(selectedBefore));
    await gesture.up();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'selection leaves an outer scroll view still when the text has no internal scroll',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => SlowSelectionScroll(child: child!),
        home: Scaffold(
            body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                    width: 300,
                    height: 180,
                    child: SingleChildScrollView(
                        controller: scroll,
                        child: SelectableText(
                            List.generate(80, (i) => 'line $i for selection')
                                .join('\n'))))))));
    final editor = tester.state<EditableTextState>(find.byType(EditableText));
    editor.widget.controller.selection =
        const TextSelection(baseOffset: 0, extentOffset: 30);
    await tester.pump();
    final render = editor.renderEditable;
    final handle = render.localToGlobal(render
        .getLocalRectForCaret(editor.widget.controller.selection.extent)
        .center);
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    GestureBinding.instance.pointerRouter
        .route(PointerDownEvent(pointer: 92, position: handle));
    GestureBinding.instance.pointerRouter.route(PointerMoveEvent(
        pointer: 92,
        position: Offset(viewport.center.dx, viewport.bottom - 2)));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.offset, 0);
    expect(editor.widget.controller.selection.extentOffset, 30);
    GestureBinding.instance.pointerRouter.route(PointerUpEvent(pointer: 92));
    await tester.pumpWidget(const SizedBox());
  });
  for (final readOnly in [false, true]) {
    testWidgets(
        'edge selection scroll is gradual and stops on release, readOnly=$readOnly',
        (tester) async {
      final controller = TextEditingController(
          text: List.generate(80, (i) => 'line $i for selection').join('\n'));
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => SlowSelectionScroll(child: child!),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                      width: 300,
                      height: 180,
                      child: TextField(
                        controller: controller,
                        scrollController: scroll,
                        readOnly: readOnly,
                        maxLines: null,
                        expands: true,
                      ))))));
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 30);
      await tester.pump();
      final editable =
          tester.state<EditableTextState>(find.byType(EditableText));
      final render = editable.renderEditable;
      final handle = render.localToGlobal(
          render.getLocalRectForCaret(controller.selection.extent).center);
      final rect = render.localToGlobal(Offset.zero) & render.size;
      GestureBinding.instance.pointerRouter
          .route(PointerDownEvent(pointer: 91, position: handle));
      GestureBinding.instance.pointerRouter.route(PointerMoveEvent(
          pointer: 91, position: Offset(rect.center.dx, rect.bottom - 2)));
      final before = scroll.offset;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.offset, greaterThan(before));
      expect(scroll.offset - before, lessThan(80));
      expect(controller.selection.isCollapsed, false);
      GestureBinding.instance.pointerRouter.route(PointerUpEvent(pointer: 91));
      await tester.pump();
      final stopped = scroll.offset;
      await tester.pump(const Duration(milliseconds: 300));
      expect(scroll.offset, stopped);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
