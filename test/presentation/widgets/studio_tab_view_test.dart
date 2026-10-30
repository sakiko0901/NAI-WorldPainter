import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/studio_tab_view.dart';

void main() {
  Widget host(int index, {bool reduceMotion = false, bool expand = true}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: StudioTabView(
                index: index,
                expand: expand,
                children: const [
                  _DraftPage(key: ValueKey('first'), height: 180),
                  _DraftPage(key: ValueKey('second'), height: 360),
                  _DraftPage(key: ValueKey('third'), height: 240),
                ],
              ),
            ),
          ),
        ),
      );

  Finder page(String name) => find.byKey(ValueKey(name), skipOffstage: false);
  double opacity(WidgetTester tester, String name) => tester
      .widget<FadeTransition>(find
          .ancestor(
              of: page(name),
              matching: find.byType(FadeTransition, skipOffstage: false))
          .first)
      .opacity
      .value;

  testWidgets('cross-fades in direction and retains drafts through rapid taps',
      (tester) async {
    await tester.pumpWidget(host(0));
    await tester.enterText(find.byType(TextField).first, 'keep this draft');
    final state = tester.state(page('first'));
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(opacity(tester, 'first'), inExclusiveRange(0, 1));
    expect(opacity(tester, 'second'), inExclusiveRange(0, 1));
    expect(tester.getTopLeft(page('first')).dx, lessThan(0));
    expect(tester.getTopLeft(page('second')).dx, greaterThan(0));
    expect(
        find
            .descendant(of: page('first'), matching: find.byType(TextField))
            .hitTestable(),
        findsNothing);
    await tester.pumpWidget(host(2));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(tester.state(page('first')), same(state));
    expect(find.text('keep this draft'), findsOneWidget);
    expect(find.byKey(const ValueKey('second')), findsNothing);
    expect(find.byKey(const ValueKey('third')), findsNothing);
    expect(opacity(tester, 'first'), 1);
    expect(TickerMode.of(tester.element(page('second'))), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrollable mode animates height and keeps hidden state',
      (tester) async {
    await tester.pumpWidget(host(0, expand: false));
    final first = tester.state(page('first'));
    final view = find.byType(StudioTabView);
    expect(tester.getSize(view).height, 180);
    await tester.pumpWidget(host(1, expand: false));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getSize(view).height, inExclusiveRange(180, 360));
    await tester.pumpAndSettle();
    expect(tester.getSize(view).height, 360);
    await tester.pumpWidget(host(0, expand: false));
    await tester.pumpAndSettle();
    expect(tester.getSize(view).height, 180);
    expect(tester.state(page('first')), same(first));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reduced motion selects immediately and exposes only active semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(0, reduceMotion: true));
    await tester.pumpWidget(host(2, reduceMotion: true));
    await tester.pump();
    expect(find.byKey(const ValueKey('first')), findsNothing);
    expect(opacity(tester, 'third'), 1);
    expect(tester.getTopLeft(page('third')).dx, 0);
    expect(find.bySemanticsLabel('draft-180'), findsNothing);
    expect(find.bySemanticsLabel('draft-240'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

class _DraftPage extends StatefulWidget {
  final double height;
  const _DraftPage({super.key, required this.height});

  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: Semantics(
          label: 'draft-${widget.height.toInt()}',
          child: TextField(controller: controller),
        ),
      );
}
