import 'package:nai_huishi/presentation/widgets/studio_scaffold.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/services/tag_completion_service.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
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
    return StudioScaffold(
        appBar: AppBar(title: const Text('标签补全')),
        body: Stack(children: [
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
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: Text(_error!)),
                  TextButton.icon(
                      onPressed: () => _load(repair: true),
                      icon: const Icon(CupertinoIcons.refresh),
                      label: const Text('重试')),
                ]),
              ),
          ]),
        ]));
  }
}
