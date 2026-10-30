import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/studio_select.dart';

void main() {
  for (final bottom in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('menu stays attached to field bottom=$bottom scale=$scale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(393, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(MaterialApp(
            theme: buildNaiHuishiTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 24),
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Align(
                            alignment: bottom
                                ? Alignment.bottomCenter
                                : Alignment.topCenter,
                            child: StudioSelect<String>(
                                id: 'noise',
                                label: '噪声调度',
                                value: 'karras',
                                options: const [
                                  StudioSelectOption('karras', 'karras'),
                                  StudioSelectOption(
                                      'exponential', 'exponential'),
                                  StudioSelectOption(
                                      'polyexponential', 'polyexponential')
                                ],
                                onChanged: (_) {})))))));
        final field = tester.getRect(find.byKey(const ValueKey('noise-field')));
        await tester.tap(find.byKey(const ValueKey('noise-field')));
        await tester.pumpAndSettle();
        final menu = tester.getRect(find.byKey(const ValueKey('noise-menu')));
        if (bottom) {
          expect(menu.bottom, closeTo(field.top - 4, 0.1));
        } else {
          expect(menu.top, closeTo(field.bottom + 4, 0.1));
        }
        expect(menu.left, closeTo(field.left, 0.1));
        expect(menu.top, greaterThanOrEqualTo(36));
        expect(menu.bottom, lessThanOrEqualTo(808));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('selector rounds menu and highlight and selects at $scale text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var value = '832x1216';
      await tester.pumpWidget(MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
          body: Padding(
              padding: const EdgeInsets.all(20),
              child: StatefulBuilder(
                  builder: (context, setState) => StudioSelect<String>(
                        id: 'resolution',
                        label: '图像尺寸',
                        value: value,
                        options: const [
                          StudioSelectOption('832x1216', '832 × 1216',
                              leading: ResolutionGlyph('832x1216')),
                          StudioSelectOption('1216x832', '1216 × 832',
                              leading: ResolutionGlyph('1216x832')),
                        ],
                        onChanged: (next) => setState(() => value = next),
                      ))),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('resolution-field')));
      await tester.pumpAndSettle();
      final menu = tester
          .widget<Material>(find.byKey(const ValueKey('resolution-menu')));
      expect((menu.shape as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(studioSelectRadius));
      final option = find.byKey(const ValueKey('resolution-option-832x1216'));
      expect(tester.widget<InkWell>(option).borderRadius,
          BorderRadius.circular(studioSelectRadius));
      final highlight = tester.widget<Material>(
          find.ancestor(of: option, matching: find.byType(Material)).first);
      expect(highlight.borderRadius, BorderRadius.circular(studioSelectRadius));
      await tester
          .tap(find.byKey(const ValueKey('resolution-option-1216x832')));
      await tester.pumpAndSettle();
      expect(value, '1216x832');
      expect(find.byKey(const ValueKey('resolution-menu')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
