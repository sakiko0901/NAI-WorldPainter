import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/tools/tools_quota_card.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('unconfigured account shows unavailable quota values', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ToolsQuotaCard(
          tokenConfigured: false,
          isLoading: false,
          hasError: false,
          staminaPercent: null,
          isNegative: false,
          tier: null,
          anlas: null,
        ),
      ),
    );

    expect(find.text('官方 Token 未配置'), findsOneWidget);
    expect(find.text('V5 体力'), findsOneWidget);
    expect(find.text('预计剩余 —'), findsOneWidget);
    expect(find.text('订阅到期时间'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('shows stamina with image estimate and Anlas beside bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ToolsQuotaCard(
          tokenConfigured: true,
          isLoading: false,
          hasError: false,
          staminaPercent: 72.5,
          isNegative: false,
          tier: 3,
          anlas: 1200,
        ),
      ),
    );

    expect(find.text('Opus V5 体力'), findsOneWidget);
    expect(find.text('72.5%'), findsOneWidget);
    expect(find.text('Anlas '), findsOneWidget);
    expect(find.text('1200'), findsOneWidget);
    // 72.5% * 17 ≈ 1233 张
    expect(find.text('预计剩余 约1233张'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // 72.5% ≥ 65% → 绿色进度条
    final context = tester.element(find.byType(LinearProgressIndicator));
    final theme = Theme.of(context);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(
      indicator.valueColor!.value,
      ToolsQuotaCard.staminaColor(72.5, theme.colorScheme),
    );
  });

  testWidgets('yellow bar between 20 and 64 percent', (tester) async {
    await tester.pumpWidget(
      _host(
        const ToolsQuotaCard(
          tokenConfigured: true,
          isLoading: false,
          hasError: false,
          staminaPercent: 40,
          isNegative: false,
          tier: 3,
          anlas: null,
        ),
      ),
    );

    final context = tester.element(find.byType(LinearProgressIndicator));
    final theme = Theme.of(context);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(
      indicator.valueColor!.value,
      ToolsQuotaCard.staminaColor(40, theme.colorScheme),
    );
    expect(
      indicator.valueColor!.value,
      isNot(theme.colorScheme.error),
    );
  });

  testWidgets('red bar below 20 percent', (tester) async {
    await tester.pumpWidget(
      _host(
        const ToolsQuotaCard(
          tokenConfigured: true,
          isLoading: false,
          hasError: false,
          staminaPercent: 12,
          isNegative: false,
          tier: 3,
          anlas: null,
        ),
      ),
    );

    final context = tester.element(find.byType(LinearProgressIndicator));
    final theme = Theme.of(context);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.valueColor!.value, theme.colorScheme.error);
  });

  testWidgets('missing fields and query failure remain explicit',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const ToolsQuotaCard(
          tokenConfigured: true,
          isLoading: false,
          hasError: true,
          staminaPercent: null,
          isNegative: false,
          tier: null,
          anlas: null,
        ),
      ),
    );

    expect(find.text('查询失败'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'expiry stays beside stamina on a narrow screen at scale $scale',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_host(MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: ToolsQuotaCard(
          tokenConfigured: true,
          isLoading: false,
          hasError: false,
          staminaPercent: 46,
          isNegative: false,
          tier: 3,
          anlas: 5168,
          expiresAt: DateTime(2026, 11, 30, 8, 50).toUtc(),
        ),
      )));
      expect(find.text('2026-11-30 08:50'), findsOneWidget);
      expect(tester.getTopLeft(find.text('订阅到期时间')).dx,
          greaterThan(tester.getTopLeft(find.text('Opus V5 体力')).dx));
      expect(tester.getTopLeft(find.text('订阅到期时间')).dy,
          tester.getTopLeft(find.text('Opus V5 体力')).dy);
    });
  }

  testWidgets('expiry is visible when subscription has no stamina usage',
      (tester) async {
    await tester.pumpWidget(_host(ToolsQuotaCard(
      tokenConfigured: true,
      isLoading: false,
      hasError: false,
      staminaPercent: null,
      isNegative: false,
      tier: 1,
      anlas: 1000,
      expiresAt: DateTime(2026, 11, 30, 8, 50),
    )));
    expect(find.text('2026-11-30 08:50'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
