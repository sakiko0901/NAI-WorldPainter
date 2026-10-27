import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/novelai_connection.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/api_config_page.dart';
import 'package:nai_huishi/presentation/pages/settings_page.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/tools/tools_quota_card.dart';

void main() {
  late _SettingsFake settings;
  late _TokenStoreFake tokens;
  late _OfficialApiFake api;

  setUp(() async {
    await sl.reset();
    settings = _SettingsFake();
    tokens = _TokenStoreFake();
    api = _OfficialApiFake();
    sl.registerSingleton<SettingsViewModel>(settings);
    sl.registerSingleton<OfficialNovelAiTokenStore>(tokens);
    sl.registerSingleton<OfficialNovelAiApiService>(api);
  });

  tearDown(() async {
    await sl.reset();
    settings.dispose();
  });

  testWidgets('streaming switch saves and restores on page reopen',
      (tester) async {
    Future<void> openCard() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: const ApiConfigPage(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NovelAI 官方'));
      await tester.pumpAndSettle();
    }

    final toggle = find.byKey(const ValueKey('novelai-streaming-switch'));
    await openCard();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(settings.endpoint.streamEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await openCard();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(settings.endpoint.streamEnabled, isTrue);
    expect(api.accountRequests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom URL saves a separate key and blank URL restores official',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: const ApiConfigPage(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NovelAI 官方'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置 URL 与 API Key'));
    await tester.pumpAndSettle();

    final urlFinder = find.byKey(const ValueKey('novelai-channel-url'));
    final keyFinder = find.byKey(const ValueKey('novelai-channel-key'));
    final urlField = tester.widget<TextFormField>(urlFinder);
    expect(urlField.controller!.text, isEmpty);
    final field = tester.widget<TextField>(
        find.descendant(of: urlFinder, matching: find.byType(TextField)));
    expect(field.decoration!.hintText, ApiConstants.officialImageBaseUrl);
    expect(tester.widget<TextFormField>(keyFinder).controller!.text,
        'official-token');

    await tester.enterText(urlFinder, 'https://relay.example/novelai');
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(keyFinder).controller!.text, isEmpty);
    await tester.enterText(keyFinder, 'third-party-key');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.endpoint.baseUrl, 'https://relay.example/novelai');
    expect(tokens.saved[ApiConstants.officialImageBaseUrl], 'official-token');
    expect(tokens.saved['https://relay.example/novelai'], 'third-party-key');
    expect(find.text('NovelAI 自定义渠道'), findsOneWidget);
    expect(find.text('验证 Token'), findsNothing);
    expect(api.accountRequests, 0);

    await tester.tap(find.text('设置 URL 与 API Key'));
    await tester.pumpAndSettle();
    await tester.enterText(urlFinder, '');
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(keyFinder).controller!.text,
        'official-token');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.endpoint.baseUrl, ApiConstants.officialImageBaseUrl);
    expect(find.text('NovelAI 官方'), findsOneWidget);
    expect(find.text('验证 Token'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom channel hides quota and skips official account requests',
      (tester) async {
    settings.endpoint =
        settings.endpoint.copyWith(baseUrl: 'https://relay.example/novelai');
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: SettingsPage(
        appearanceMode: AppearanceMode.dark,
        onAppearanceChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ToolsQuotaCard), findsNothing);
    expect(tokens.officialReads, 0);
    expect(api.accountRequests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to custom clears an already visible official quota',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildNaiHuishiTheme(Brightness.dark),
      home: SettingsPage(
        appearanceMode: AppearanceMode.dark,
        onAppearanceChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ToolsQuotaCard), findsOneWidget);
    expect(api.accountRequests, 1);
    await settings.updateEndpoint(ImageProviderType.novelAi,
        settings.endpoint.copyWith(baseUrl: 'https://relay.example'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolsQuotaCard), findsNothing);
    expect(api.accountRequests, 1);
  });
}

class _SettingsFake extends ChangeNotifier implements SettingsViewModel {
  ApiEndpoint endpoint = const ApiEndpoint(
    id: AppConstants.novelAiOfficialEndpointId,
    name: 'NovelAI 官方',
    baseUrl: ApiConstants.officialImageBaseUrl,
    apiKey: '',
    models: ApiConstants.officialNovelAiModels,
    protocol: AppConstants.novelAiOfficialProtocol,
  );

  @override
  Future<void> loadSettings() async {}

  @override
  List<ApiEndpoint> endpoints(ImageProviderType provider) =>
      provider == ImageProviderType.novelAi ? [endpoint] : [];

  @override
  String? activeEndpointId(ImageProviderType provider) => endpoint.id;

  @override
  String? activeModel(ImageProviderType provider) => endpoint.models.first;

  @override
  Future<void> updateEndpoint(
      ImageProviderType provider, ApiEndpoint value) async {
    endpoint = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TokenStoreFake extends OfficialNovelAiTokenStore {
  final saved = <String, String>{
    ApiConstants.officialImageBaseUrl: 'official-token',
  };
  int officialReads = 0;

  @override
  Future<String?> read() async {
    officialReads++;
    return saved[ApiConstants.officialImageBaseUrl];
  }

  @override
  Future<String?> readForBaseUrl(String baseUrl) async =>
      saved[NovelAiConnection.normalizeBaseUrl(baseUrl)];

  @override
  Future<void> writeForBaseUrl(String baseUrl, String token) async {
    saved[NovelAiConnection.normalizeBaseUrl(baseUrl)] = token;
  }
}

class _OfficialApiFake extends OfficialNovelAiApiService {
  int accountRequests = 0;

  @override
  Future<OfficialNovelAiV5Usage?> fetchV5Usage(String token) async {
    accountRequests++;
    return const OfficialNovelAiV5Usage(
      percent: 90,
      isNegative: false,
      tier: 3,
      fixedTrainingStepsLeft: 1000,
    );
  }

  @override
  Future<OfficialNovelAiAccount> verifyToken(String token) async {
    accountRequests++;
    return const OfficialNovelAiAccount();
  }
}
