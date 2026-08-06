import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/local/settings_local_datasource.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

    expect(endpoints, hasLength(2));
    expect(endpoints[0].id, AppConstants.novelAiChatCompletionsEndpointId);
    expect(endpoints[0].protocol, AppConstants.novelAiChatCompletionsProtocol);
    expect(endpoints[0].name, '活动端点');
    expect(endpoints[0].baseUrl, 'https://active.example');
    expect(endpoints[1].id, AppConstants.novelAiImageGenerationsEndpointId);
    expect(endpoints[1].protocol, AppConstants.novelAiImageGenerationsProtocol);
    expect(endpoints[1].name, 'ikun');
    expect(endpoints[1].baseUrl, isEmpty);
  });

  test('NovelAI 写入时保留两个固定槽位及可编辑名称', () async {
    SharedPreferences.setMockInitialValues({});
    final datasource =
        SettingsLocalDatasource(await SharedPreferences.getInstance());
    final endpoints = datasource.getEndpoints(ImageProviderType.novelAi);

    await datasource.setEndpoints(ImageProviderType.novelAi, [
      endpoints[0].copyWith(name: '可编辑的 7877'),
      endpoints[1].copyWith(name: '可编辑的 ikun'),
    ]);

    final saved = datasource.getEndpoints(ImageProviderType.novelAi);
    expect(saved.map((endpoint) => endpoint.id), ['7877', 'ikun']);
    expect(saved.map((endpoint) => endpoint.protocol),
        ['chat-completions', 'image-generations']);
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

  test('旧角色参考迁移为 Precise 时不保留信息提取量', () async {
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

    expect(references, hasLength(1));
    expect(references.single.path, 'legacy.png');
    expect(references.single.referenceType, 'character');
    expect(references.single.strength, 0.6);
    final saved = jsonDecode(
      preferences.getString(AppConstants.keyPreciseReferencesDraft)!,
    ) as List;
    expect(saved.single, isNot(contains('fidelity')));
    expect(datasource.getCharactersDraft().single.referenceImages, isEmpty);
  });
}
