import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/services/tag_completion_service.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class TagCompletionSettingsPage extends StatefulWidget {
  const TagCompletionSettingsPage({super.key});
  @override
  State<TagCompletionSettingsPage> createState() =>
      _TagCompletionSettingsPageState();
}

class _TagCompletionSettingsPageState extends State<TagCompletionSettingsPage> {
  final _service = TagCompletionService.instance;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool repair = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _service.initialize();
    try {
      if (repair) {
        await _service.catalog.repair();
      } else {
        await _service.catalog.open();
      }
    } catch (_) {
      _error = '词库准备失败，请检查可用空间后重试';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(Future<void> action) async {
    try {
      await action;
    } catch (_) {
      if (mounted) showFloatingToast(context, '设置保存失败，请重试');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final meta = _service.catalog.metadata;
    final theme = Theme.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('标签补全')),
        body: Stack(children: [
          const Positioned.fill(child: StudioBackground()),
          ListView(padding: const EdgeInsets.all(16), children: [
            FrostedSurface(
                child: Column(children: [
              SwitchListTile.adaptive(
                  title: const Text('输入时补全标签'),
                  subtitle: const Text('在正负提示词、角色与重绘编辑器中使用'),
                  value: _service.enabled,
                  onChanged: (v) => _save(_service.update(enabled: v))),
              SwitchListTile.adaptive(
                  title: const Text('显示中文释义'),
                  value: _service.showTranslation,
                  onChanged: (v) => _save(_service.update(showTranslation: v))),
              SwitchListTile.adaptive(
                  title: const Text('自动补齐逗号'),
                  subtitle: const Text('选中标签后继续输入下一个标签'),
                  value: _service.autoComma,
                  onChanged: (v) => _save(_service.update(autoComma: v))),
              SwitchListTile.adaptive(
                  title: const Text('在线补充与相关标签'),
                  subtitle: const Text('将当前标签发送到查词服务，补充较新的标签和相关推荐'),
                  value: _service.onlineEnabled,
                  onChanged: (v) => _save(_service.update(onlineEnabled: v))),
            ])),
            const SizedBox(height: 16),
            FrostedSurface(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('完整离线词库', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 10),
                      if (_loading)
                        const Text('正在准备词库，首次使用需要解压…')
                      else if (_error != null) ...[
                        Text(_error!),
                        TextButton.icon(
                            onPressed: () => _load(repair: true),
                            icon: const Icon(CupertinoIcons.refresh),
                            label: const Text('重试')),
                      ] else if (meta != null) ...[
                        Text('${meta['tags']} 个标签 · ${meta['aliases']} 条别名'),
                        const SizedBox(height: 4),
                        Text('${meta['translations']} 条中文释义'),
                        const SizedBox(height: 8),
                        Text('词库版本 ${meta['version']}',
                            style: theme.textTheme.bodySmall),
                      ],
                      const SizedBox(height: 12),
                      Text(
                          '完整收录所用版本的 Danbooru / e621 标签及中文译库，不按热度裁剪。'
                          '词库随应用更新，离线即可使用；没有译文的标签仍可用英文检索。',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.6)),
                      const SizedBox(height: 8),
                      Text(
                          '数据来源：dbr-e621-lists-archive、NAI Launcher、ffdkj 中英文对照表。中文释义可能存在翻译误差。',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.6)),
                    ])),
            const SizedBox(height: 16),
            Text(
                '键盘：↑ ↓ 选择，Tab / Enter 插入，Esc 关闭，Shift + Enter 换行。'
                '开启在线补充后，长按输入框可查找当前标签的相关内容。',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.6)),
          ]),
        ]));
  }
}
