import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/viewmodels/pixiv_settings_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class PixivSettingsPage extends StatefulWidget {
  const PixivSettingsPage({super.key});

  @override
  State<PixivSettingsPage> createState() => _PixivSettingsPageState();
}

class _PixivSettingsPageState extends State<PixivSettingsPage> {
  late final PixivSettingsViewModel _vm;

  final _cookieCtrl = TextEditingController();
  final _csrfCtrl = TextEditingController();
  final _proxyCtrl = TextEditingController();
  final _captionPrefixCtrl = TextEditingController();
  final _defaultTagsCtrl = TextEditingController();
  final _repFillCtrl = TextEditingController();
  final _junkCtrl = TextEditingController();

  bool _loading = true;
  bool _obscureCookie = true;
  bool _obscureCsrf = true;

  @override
  void initState() {
    super.initState();
    _vm = sl<PixivSettingsViewModel>();
    _vm.addListener(_onVm);
    _load();
  }

  Future<void> _load() async {
    await _vm.load();
    final s = _vm.settings!;
    _cookieCtrl.text = s.cookie;
    _csrfCtrl.text = s.csrfToken;
    _proxyCtrl.text = s.proxy;
    _captionPrefixCtrl.text = s.captionPrefix;
    _defaultTagsCtrl.text = s.defaultTags.join(', ');
    _repFillCtrl.text = s.repTagsFill;
    _junkCtrl.text = s.junkText;
    if (mounted) setState(() => _loading = false);
  }

  void _onVm() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onVm);
    _cookieCtrl.dispose();
    _csrfCtrl.dispose();
    _proxyCtrl.dispose();
    _captionPrefixCtrl.dispose();
    _defaultTagsCtrl.dispose();
    _repFillCtrl.dispose();
    _junkCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = _vm.settings!;
    await _vm.save(s.copyWith(
      cookie: _cookieCtrl.text.trim(),
      csrfToken: _csrfCtrl.text.trim(),
      proxy: _proxyCtrl.text.trim(),
      captionPrefix: _captionPrefixCtrl.text,
      defaultTags: _defaultTagsCtrl.text
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      repTagsFill: _repFillCtrl.text,
      junkText: _junkCtrl.text,
    ));
    if (!mounted) return;
    showFloatingToast(context, '已保存', icon: CupertinoIcons.checkmark_circle);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final s = _vm.settings!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pixiv 设置'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.checkmark),
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
        children: [
          _Section(
            isDark: isDark,
            title: '认证',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Cookie'),
                TextField(
                  controller: _cookieCtrl,
                  obscureText: _obscureCookie,
                  maxLines: _obscureCookie ? 1 : 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: '完整的 Pixiv Cookie 字符串',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCookie
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye),
                      onPressed: () => setState(() => _obscureCookie = !_obscureCookie),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _label('X-CSRF-Token'),
                TextField(
                  controller: _csrfCtrl,
                  obscureText: _obscureCsrf,
                  decoration: InputDecoration(
                    hintText: '从 illustration/create 请求头取',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCsrf
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye),
                      onPressed: () => setState(() => _obscureCsrf = !_obscureCsrf),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _Hint(
                  text:
                      '抓取步骤：浏览器登录 Pixiv → 进入 pixiv.net/illustration/create → F12 开网络面板 → 上传任意一张图触发 illustration 请求 → 在请求头复制 cookie 和 x-csrf-token。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            isDark: isDark,
            title: '网络',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('代理 (可选)'),
                TextField(
                  controller: _proxyCtrl,
                  decoration: const InputDecoration(
                    hintText: '如 127.0.0.1:7890',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                _Hint(
                    text: '国内直连 Pixiv 通常不可用。留空则不使用代理，可能需要全局代理或 VPN。'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            isDark: isDark,
            title: '默认值',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('描述前缀'),
                TextField(
                  controller: _captionPrefixCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                _label('默认标签 (逗号分隔)'),
                TextField(
                  controller: _defaultTagsCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '女の子, NovelAI',
                  ),
                ),
                const SizedBox(height: 14),
                _SwitchRow(
                  title: 'R18 默认',
                  value: s.r18Default,
                  onChanged: (v) async {
                    await _vm.save(s.copyWith(r18Default: v));
                  },
                ),
                _SwitchRow(
                  title: '允许他人编辑标签',
                  value: s.allowTagEdit,
                  onChanged: (v) async {
                    await _vm.save(s.copyWith(allowTagEdit: v));
                  },
                ),
                _SwitchRow(
                  title: '上传前 LSB 隐写擦除',
                  value: s.stripMetadata,
                  onChanged: (v) async {
                    await _vm.save(s.copyWith(stripMetadata: v));
                  },
                ),
                _SwitchRow(
                  title: '调用 Pixiv 自动推荐标签',
                  value: s.suggestTagsEnabled,
                  onChanged: (v) async {
                    await _vm.save(s.copyWith(suggestTagsEnabled: v));
                  },
                ),
                const SizedBox(height: 8),
                _label('冷却时间 (分钟): ${s.cooldownMinutes}'),
                Slider(
                  value: s.cooldownMinutes.toDouble().clamp(5, 60),
                  min: 5,
                  max: 60,
                  divisions: 55,
                  onChanged: (v) async {
                    await _vm.save(s.copyWith(cooldownMinutes: v.round()));
                  },
                ),
                _label('描述抽样比例: ${(s.repTagsPercent * 100).toStringAsFixed(0)}%'),
                Slider(
                  value: s.repTagsPercent.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  onChanged: (v) async {
                    await _vm.save(s.copyWith(repTagsPercent: v));
                  },
                ),
                const SizedBox(height: 8),
                _label('抽样填充词 (用于替换被丢弃的 tag)'),
                TextField(
                  controller: _repFillCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '杂鱼~',
                  ),
                ),
                const SizedBox(height: 12),
                _label('隐写垃圾文本 (写入 LSB)'),
                TextField(
                  controller: _junkCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '随便填，将被压缩写入 alpha 通道',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(CupertinoIcons.checkmark_circle),
              label: const Text('保存所有更改'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Section extends StatelessWidget {
  final bool isDark;
  final String title;
  final Widget child;
  const _Section({required this.isDark, required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C21) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: isDark ? 0.06 : 0.08),
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info, size: 14,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
