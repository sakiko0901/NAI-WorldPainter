import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/data/datasources/local/settings_local_datasource.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
      'NovelAI streaming preference survives endpoint normalization and restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var datasource = SettingsLocalDatasource(prefs);
    expect(datasource.getEndpoints(ImageProviderType.novelAi)[2].streamEnabled,
        isNull);
    for (final enabled in [false, true]) {
      final endpoints = datasource.getEndpoints(ImageProviderType.novelAi);
      await datasource.setEndpoints(ImageProviderType.novelAi, [
        endpoints[0],
        endpoints[1],
        endpoints[2].copyWith(streamEnabled: enabled),
      ]);
      datasource = SettingsLocalDatasource(prefs);
      final restored = datasource.getEndpoints(ImageProviderType.novelAi)[2];
      expect(restored.streamEnabled, enabled);
      // Editing another channel property must retain the saved preference.
      await datasource.setEndpoints(ImageProviderType.novelAi, [
        endpoints[0],
        endpoints[1],
        restored.copyWith(baseUrl: 'https://relay.example'),
      ]);
      expect(
          SettingsLocalDatasource(prefs)
              .getEndpoints(ImageProviderType.novelAi)[2]
              .streamEnabled,
          enabled);
    }
  });

  test('inpaint role drafts persist separately from text generation roles',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final datasource = SettingsLocalDatasource(prefs);
    const original = [CharacterSpec(prompt: 'original')];
    const inpaint = [
      CharacterSpec(prompt: 'blue hair', uc: 'hat'),
      CharacterSpec(
          prompt: 'red hair', uc: 'glasses', centerX: .7, centerY: .4),
    ];
    await datasource.setCharactersDraft(original);
    await datasource.setInpaintCharactersDraft(inpaint);
    final reopened = SettingsLocalDatasource(prefs);
    expect(reopened.getCharactersDraft(), original);
    expect(reopened.getInpaintCharactersDraft(), inpaint);
    await reopened.setInpaintCharactersDraft(const []);
    expect(reopened.getInpaintCharactersDraft(), isEmpty);
    expect(reopened.getCharactersDraft(), original);
  });

  test('NovelAI 旧活动端点迁移到固定 7877 槽位', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyImageProviderNovelAiEndpoints: jsonEncode([
        {
          'id': 'first',
          'name': '首端点',
          'base_url': 'https://first.example',
          'api_key': 'first-key',
          'models': ['first-model'],
        },
        {
          'id': 'active',
          'name': '活动端点',
          'base_url': 'https://active.example',
          'api_key': 'active-key',
          'models': ['active-model'],
        },
      ]),
      AppConstants.keyImageProviderNovelAiActiveEndpointId: 'active',
    });
    final datasource =
        SettingsLocalDatasource(await SharedPreferences.getInstance());
    final endpoints = datasource.getEndpoints(ImageProviderType.novelAi);

    expect(endpoints, hasLength(3));
    expect(endpoints[0].id, AppConstants.novelAiChatCompletionsEndpointId);
    expect(endpoints[0].protocol, AppConstants.novelAiChatCompletionsProtocol);
    expect(endpoints[0].name, '活动端点');
    expect(endpoints[0].baseUrl, 'https://active.example');
    expect(endpoints[0].models, ['active-model']);
    expect(endpoints[1].id, AppConstants.novelAiImageGenerationsEndpointId);
    expect(endpoints[1].protocol, AppConstants.novelAiImageGenerationsProtocol);
    expect(endpoints[1].name, 'ikun');
    expect(endpoints[1].baseUrl, isEmpty);
    expect(endpoints[2].id, AppConstants.novelAiOfficialEndpointId);
    expect(endpoints[2].protocol, AppConstants.novelAiOfficialProtocol);
    expect(endpoints[2].models, ApiConstants.officialNovelAiModels);
  });

  test('新配置默认使用 7877 原生中转站和推荐模型', () async {
    SharedPreferences.setMockInitialValues({});
    final datasource =
        SettingsLocalDatasource(await SharedPreferences.getInstance());
    final endpoints = datasource.getEndpoints(ImageProviderType.novelAi);

    expect(endpoints.first.baseUrl, 'https://novelai.ikun114.top/');
    expect(endpoints.first.models, ApiConstants.nativeNovelAiModels);
  });

  test('NovelAI 写入时保留两个固定槽位及可编辑名称', () async {
    SharedPreferences.setMockInitialValues({});
    final datasource =
        SettingsLocalDatasource(await SharedPreferences.getInstance());
    final endpoints = datasource.getEndpoints(ImageProviderType.novelAi);

    await datasource.setEndpoints(ImageProviderType.novelAi, [
      endpoints[0].copyWith(name: '可编辑的 7877'),
      endpoints[1].copyWith(name: '可编辑的 ikun'),
      endpoints[2],
    ]);

    final saved = datasource.getEndpoints(ImageProviderType.novelAi);
    expect(saved.map((endpoint) => endpoint.id), ['7877', 'ikun', 'official']);
    expect(saved.map((endpoint) => endpoint.protocol),
        ['chat-completions', 'image-generations', 'official']);
    expect(saved[0].name, '可编辑的 7877');
    expect(saved[1].name, '可编辑的 ikun');
  });

  test('参考模式与批量数量会使用合法范围', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyReferenceModeDraft: 'precise',
      AppConstants.keyBatchCount: 99,
    });
    final preferences = await SharedPreferences.getInstance();
    final datasource = SettingsLocalDatasource(preferences);

    expect(datasource.getReferenceModeDraft(), ReferenceMode.precise);
    expect(datasource.getBatchCount(), AppConstants.maxBatchCount);

    await datasource.setReferenceModeDraft(ReferenceMode.vibe);
    await datasource.setBatchCount(0);

    expect(datasource.getReferenceModeDraft(), ReferenceMode.vibe);
    expect(datasource.getBatchCount(), 1);
  });

  test('NovelAI 自定义官方协议 URL 在重启后保留，留空恢复官渠', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final datasource = SettingsLocalDatasource(prefs);
    final endpoints = datasource.getEndpoints(ImageProviderType.novelAi);
    await datasource.setEndpoints(ImageProviderType.novelAi, [
      endpoints[0],
      endpoints[1],
      endpoints[2].copyWith(baseUrl: 'https://relay.example/novelai/'),
    ]);

    final reopened = SettingsLocalDatasource(prefs);
    final saved = reopened.getEndpoints(ImageProviderType.novelAi);
    expect(saved[2].baseUrl, 'https://relay.example/novelai');
    expect(saved[2].protocol, AppConstants.novelAiOfficialProtocol);
    expect(saved[2].apiKey, isEmpty);

    await reopened.setEndpoints(ImageProviderType.novelAi, [
      saved[0],
      saved[1],
      saved[2].copyWith(baseUrl: '  '),
    ]);
    expect(
      SettingsLocalDatasource(prefs)
          .getEndpoints(ImageProviderType.novelAi)[2]
          .baseUrl,
      ApiConstants.officialImageBaseUrl,
    );
  });

  test('旧 Precise 草稿会保留有效字段并移除可变 fidelity', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyPreciseReferencesDraft: jsonEncode([
        {
          'path': 'reference.png',
          'reference_type': 'style',
          'strength': 0.7,
          'fidelity': 0.4,
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final datasource = SettingsLocalDatasource(preferences);

    final references = await datasource.getPreciseReferencesDraft();

    expect(references, hasLength(1));
    expect(references.single.path, 'reference.png');
    expect(references.single.referenceType, 'style');
    expect(references.single.strength, 0.7);
    final saved = jsonDecode(
      preferences.getString(AppConstants.keyPreciseReferencesDraft)!,
    ) as List;
    expect(saved.single, isNot(contains('fidelity')));
  });

  test('角色精细参考不会迁移或在读取时清空', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyCharactersDraft: jsonEncode([
        {
          'prompt': 'girl',
          'uc': '',
          'enabled': true,
          'reference_images': [
            {
              'path': 'legacy.png',
              'strength': 0.6,
              'information_extracted': 0.3,
            },
          ],
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final datasource = SettingsLocalDatasource(preferences);

    final references = await datasource.getPreciseReferencesDraft();
    final characterReference =
        datasource.getCharactersDraft().single.referenceImages.single;

    expect(references, isEmpty);
    expect(
      preferences.containsKey(AppConstants.keyPreciseReferencesDraft),
      isFalse,
    );
    expect(characterReference.path, 'legacy.png');
    expect(characterReference.strength, 0.6);
    expect(characterReference.informationExtracted, 0.3);
  });
}
