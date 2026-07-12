import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

class DirectorToolsPage extends StatefulWidget {
  const DirectorToolsPage({super.key});

  @override
  State<DirectorToolsPage> createState() => _DirectorToolsPageState();
}

class _DirectorToolsPageState extends State<DirectorToolsPage> {
  late final GenerationViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = sl<GenerationViewModel>()..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导演工具')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('角色与坐标', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('与生图页共用角色状态。这里适合快速安排角色位置；角色描述与精确参考图仍可在生图页展开编辑。'),
          const SizedBox(height: 16),
          for (final entry in _vm.characters.asMap().entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('角色 ${entry.key + 1}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                      Switch(
                        value: entry.value.enabled,
                        onChanged: (_) => _vm.toggleCharacterEnabled(entry.key),
                      ),
                    ]),
                    Text(
                        entry.value.prompt.isEmpty
                            ? '尚未填写角色描述'
                            : entry.value.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                            label: const Text('自动位置'),
                            onPressed: () =>
                                _vm.setCharacterPositionAuto(entry.key)),
                        for (final position in const [
                          (0, 0, '左上'),
                          (0, 2, '上中'),
                          (0, 4, '右上'),
                          (2, 0, '左中'),
                          (2, 2, '中央'),
                          (2, 4, '右中'),
                          (4, 0, '左下'),
                          (4, 2, '下中'),
                          (4, 4, '右下')
                        ])
                          ActionChip(
                            label: Text(position.$3),
                            onPressed: () => _vm.setCharacterGridPosition(
                                entry.key, position.$1, position.$2),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _vm.characters.length >= 6 ? null : _vm.addCharacter,
            icon: const Icon(CupertinoIcons.person_add),
            label: const Text('添加角色'),
          ),
          const SizedBox(height: 24),
          Text('图像标注', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
              '已接入二进制 PNG annotate API。请先在 API 配置中选择 ikun 渠道；标注结果可由图像工具流程调用。'),
        ],
      ),
    );
  }
}
