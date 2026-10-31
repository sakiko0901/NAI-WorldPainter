import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/navigation/app_update_navigation_observer.dart';

void main() {
  testWidgets('a page or fading modal prevents a startup prompt',
      (tester) async {
    final observer = AppUpdateNavigationObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(observer.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      home: const Scaffold(body: Text('home')),
    ));
    await tester.pumpAndSettle();
    expect(observer.rootRouteCurrent.value, isTrue);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('editing page'))));
    await tester.pumpAndSettle();
    expect(observer.rootRouteCurrent.value, isFalse);
    navigatorKey.currentState!.pop();
    await tester.pump();
    expect(observer.rootRouteCurrent.value, isFalse,
        reason: 'The outgoing page is still animating');
    await tester.pumpAndSettle();
    expect(observer.rootRouteCurrent.value, isTrue);
    showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(title: Text('existing dialog')),
    );
    await tester.pumpAndSettle();
    expect(observer.rootRouteCurrent.value, isFalse);
    navigatorKey.currentState!.pop();
    await tester.pump();
    expect(observer.rootRouteCurrent.value, isFalse);
    await tester.pumpAndSettle();
    expect(observer.rootRouteCurrent.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing the home route still permits a startup prompt',
      (tester) async {
    final observer = AppUpdateNavigationObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(observer.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      home: const Scaffold(body: Text('first home')),
    ));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('replacement home'))));
    await tester.pumpAndSettle();
    expect(find.text('replacement home'), findsOneWidget);
    expect(observer.rootRouteCurrent.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlapping exits wait for the slower underlying page',
      (tester) async {
    final observer = AppUpdateNavigationObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(observer.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      home: const Scaffold(body: Text('home')),
    ));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.push(PageRouteBuilder<void>(
      reverseTransitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const Scaffold(body: Text('slow page')),
    ));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.push(PageRouteBuilder<void>(
      opaque: false,
      reverseTransitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const Center(child: Text('quick modal')),
    ));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(observer.rootRouteCurrent.value, isFalse,
        reason: 'The quick modal ended but the slower page is still exiting');
    await tester.pumpAndSettle();
    expect(observer.rootRouteCurrent.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
