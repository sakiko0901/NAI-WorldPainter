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
    expect(find.text('Anlas'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(find.textContaining('张'), findsNothing);
  });

  testWidgets('displays only returned stamina and Anlas; estimate stays blank',
      (
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
    expect(find.text('1200'), findsOneWidget);
    expect(find.text('预计剩余 '), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('张'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
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
    expect(find.text('—'), findsNWidgets(3));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
