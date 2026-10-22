import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/data/datasources/local/asset_prompting_skill_loader.dart';
import 'package:nai_huishi/domain/services/prompting_skill_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('loads the bundled V5 prompting skill and references', () async {
    final loader = AssetPromptingSkillLoader();

    final skill = await loader.loadSkill();
    final ideation = await loader.loadReference(PromptingReference.ideation);
    final writing = await loader.loadReference(PromptingReference.writing);

    expect(skill, contains('NAI5 Prompting'));
    expect(ideation, contains('通用构思'));
    expect(writing, contains('通用写法'));
    expect(writing, contains('输出长什么样'));
  });

  test(
      'keeps V5 character positioning automatic unless manual layout is requested',
      () async {
    final loader = AssetPromptingSkillLoader();

    final skill = await loader.loadSkill();
    final ideation = await loader.loadReference(PromptingReference.ideation);
    final writing = await loader.loadReference(PromptingReference.writing);

    expect(skill, contains('默认交给 V5 自动布局'));
    expect(skill, contains('不等于授权写入角色坐标'));
    expect(skill, contains('只有用户明确要求手动布局'));
    expect(ideation, contains('默认仍让 V5 自行安排角色的具体画布位置'));
    expect(ideation, contains('不要默认给每个角色分配画布坐标'));
    expect(writing, contains('默认省略角色坐标，让 V5 自动布局'));
    expect(writing, contains('不构成写入坐标的授权'));
    expect(writing, contains('已有人工坐标'));
    expect(writing, contains('用户明确要求手动布局时，才按要求设置角色 Position 坐标'));
    expect(writing, isNot(contains('调用工具时必须按构图为每个角色实际传坐标')));
    expect(writing, isNot(contains('在绘世 App 中必须写入实际角色坐标')));
    expect(writing, isNot(contains('编号对应画布定位')));
  });

  test('reuses cached V5 prompting skill resources', () async {
    final loader = AssetPromptingSkillLoader();

    final firstSkill = await loader.loadSkill();
    final secondSkill = await loader.loadSkill();
    final firstWriting = await loader.loadReference(PromptingReference.writing);
    final secondWriting =
        await loader.loadReference(PromptingReference.writing);

    expect(identical(firstSkill, secondSkill), isTrue);
    expect(identical(firstWriting, secondWriting), isTrue);
  });
}
