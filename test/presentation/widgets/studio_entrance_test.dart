import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/studio_entrance.dart';

void main() {
  testWidgets('foreground reveals in stages without layout or child rebuilds',
      (tester) async {
    final clock = AnimationController(vsync: tester, value: 0);
    addTearDown(clock.dispose);
    var builds = 0;
    var taps = 0;
    Widget host({bool reduceMotion = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: StudioEntranceScope(
              animation: clock,
              child: Column(children: [
                StudioEntrance(
                    role: StudioEntranceRole.heading,
                    child: SizedBox(
                        width: 200,
                        height: 40,
                        child: GestureDetector(
                            onTap: () => taps++,
                            behavior: HitTestBehavior.opaque,
                            child: Builder(builder: (_) {
                              builds++;
                              return const Text('Heading',
                                  key: ValueKey('heading'));
                            })))),
                StudioEntrance(
                    role: StudioEntranceRole.action,
                    child: SizedBox(
                        width: 200,
                        height: 40,
                        child: GestureDetector(
                            onTap: () => taps++,
                            behavior: HitTestBehavior.opaque,
                            child: const Text('Action',
                                key: ValueKey('action'))))),
              ]),
            ),
          ),
        );
    await tester.pumpWidget(host());
    final heading = find.byKey(const ValueKey('heading'));
    final action = find.byKey(const ValueKey('action'));
    final originalSize = tester.getSize(heading);
    final originalBuilds = builds;
    expect(heading.hitTestable(), findsNothing);
    expect(action.hitTestable(), findsOneWidget);
    clock.value = .28;
    await tester.pump();
    expect(heading.hitTestable(), findsOneWidget);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getSize(heading), originalSize);
    expect(builds, originalBuilds);
    clock.value = 1;
    await tester.pump();
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    expect(taps, 1);
    expect(builds, originalBuilds);
    // A data rebuild after completion must not start another entrance.
    await tester.pumpWidget(host());
    expect(action.hitTestable(), findsOneWidget);
    clock.value = 0;
    await tester.pumpWidget(host(reduceMotion: true));
    expect(heading.hitTestable(), findsOneWidget);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
