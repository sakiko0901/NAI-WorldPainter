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
