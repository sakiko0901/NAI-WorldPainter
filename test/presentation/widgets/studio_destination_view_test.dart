import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/widgets/studio_destination_view.dart';

void main() {
  Widget host(int index, {bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: StudioDestinationView(
            index: index,
            children: const [
              _Page(key: ValueKey('a')),
              _Page(key: ValueKey('b')),
              _Page(key: ValueKey('c')),
            ],
          ),
        ),
      );

  Finder page(String name) => find.byKey(ValueKey(name));
  testWidgets('previous page cannot bleed through the entering workspace',
      (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(page('a'), findsNothing);
    expect(page('b'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(page('a'), findsNothing);
  });

  testWidgets('rapid switches retain drafts and settle on the latest page',
      (tester) async {
    await tester.pumpWidget(host(0));
    final state = tester.state(page('a'));
    await tester.enterText(find.byType(TextField), 'retained draft');
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(host(2));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(tester.state(page('a')), same(state));
    expect(find.text('retained draft'), findsOneWidget);
    expect(page('b'), findsNothing);
    expect(page('c'), findsNothing);
    expect(tester.getTopLeft(page('a')), Offset.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabling reduced motion settles an ongoing reveal immediately',
      (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(2));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(host(2, reduceMotion: true));
    expect(page('a'), findsNothing);
    expect(tester.getTopLeft(page('c')), Offset.zero);
    await tester.pumpWidget(host(1, reduceMotion: true));
    expect(page('c'), findsNothing);
    expect(tester.getTopLeft(page('b')), Offset.zero);
    expect(tester.takeException(), isNull);
  });
}

class _Page extends StatefulWidget {
  const _Page({super.key});

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        child: Align(
          alignment: Alignment.topCenter,
          child: TextField(controller: controller),
        ),
      );
}
