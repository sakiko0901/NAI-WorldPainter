import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/character_position_editor.dart';

void main() {
  for (final ratio in [832 / 1216, 1216 / 832, 1.0]) {
    testWidgets('continuous board keeps ratio $ratio and exact coordinates',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Offset? point;
      await tester.pumpWidget(MaterialApp(
          theme: buildNaiHuishiTheme(Brightness.dark),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
                builder: (context, setState) => CharacterPositionEditor(
                    aspectRatio: ratio,
                    continuous: true,
                    roleNumber: 1,
                    x: point?.dx,
                    y: point?.dy,
                    onAuto: () => setState(() => point = null),
                    onChanged: (value) => setState(() => point = value))),
          )))));
      await tester.pumpAndSettle();
      final board = find.byKey(const ValueKey('free-character-position'));
      final rect = tester.getRect(board);
      expect(rect.width / rect.height, closeTo(ratio, .0001));
      await tester
          .tapAt(rect.topLeft + Offset(rect.width * .37, rect.height * .63));
      await tester.pumpAndSettle();
      expect(point!.dx, closeTo(.37, .001));
      expect(point!.dy, closeTo(.63, .001));
      final marker = find.byKey(const ValueKey('character-position-marker'));
      expect(tester.getCenter(marker).dx,
          closeTo(rect.left + rect.width * .37, .01));
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(rect.topLeft - const Offset(20, 20));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(point, Offset.zero);
      expect(tester.getCenter(marker).dx, closeTo(rect.left, .01));
      expect(tester.getCenter(marker).dy, closeTo(rect.top, .01));
      await tester.enterText(
          find.byKey(const ValueKey('character-coordinate-x')), '.25');
      await tester.pump();
      expect(point!.dx, .25);
      await tester.enterText(
          find.byKey(const ValueKey('character-coordinate-x')), '2.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(point!.dx, 1);
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('character-coordinate-x')))
              .controller!
              .text,
          '1.000');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'legacy grid matches output ratio and keeps five-axis coordinates',
      (tester) async {
    Offset? point;
    await tester.pumpWidget(MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.light),
        home: Scaffold(
            body: Padding(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
              builder: (_, setState) => CharacterPositionEditor(
                  aspectRatio: 1216 / 832,
                  continuous: false,
                  roleNumber: 1,
                  x: point?.dx,
                  y: point?.dy,
                  onAuto: () => setState(() => point = null),
                  onChanged: (value) => setState(() => point = value))),
        ))));
    await tester.pumpAndSettle();
    final rect =
        tester.getRect(find.byKey(const ValueKey('legacy-character-position')));
    expect(rect.width / rect.height, closeTo(1216 / 832, .0001));
    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('位置 E5'));
    await tester.pumpAndSettle();
    expect(point, const Offset(.9, .9));
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
