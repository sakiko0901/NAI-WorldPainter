import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';
import 'package:uuid/uuid.dart';

class ApiConfigPage extends StatefulWidget {
  const ApiConfigPage({super.key});

  @override
  State<ApiConfigPage> createState() => _ApiConfigPageState();
}

class _ApiConfigPageState extends State<ApiConfigPage>
    with SingleTickerProviderStateMixin {
  late final SettingsViewModel _vm;
  late final TabController _tabController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _vm = sl<SettingsViewModel>();
    _vm.addListener(_onVmChanged);
    _tabController = TabController(length: 3, vsync: this);
    _reload();
  }

  Future<void> _reload() async {
    await _vm.loadSettings();
    if (mounted) setState(() => _loading = false);
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('API 与账号'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'NovelAI'),
              Tab(text: 'GPT'),
              Tab(text: 'Nano Banana'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: const [
                  _ProviderTab(provider: ImageProviderType.novelAi),
                  _ProviderTab(provider: ImageProviderType.gpt),
                  _ProviderTab(provider: ImageProviderType.nanoBanana),
                ],
              ),
      );
}

class _ProviderTab extends StatefulWidget {
  final ImageProviderType provider;
  const _ProviderTab({required this.provider});

  @override
  State<_ProviderTab> createState() => _ProviderTabState();
}

class _ProviderTabState extends State<_ProviderTab> {
  late final SettingsViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = sl<SettingsViewModel>()..addListener(_changed);
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
    final provider = widget.provider;
    final endpoints = _vm.endpoints(provider);
    final activeId = _vm.activeEndpointId(provider);
    final activeModel = _vm.activeModel(provider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      children: [
        for (final endpoint in endpoints)
          endpoint.id == AppConstants.novelAiOfficialEndpointId
              ? _OfficialNovelAiCard(
                  endpoint: endpoint,
                  isActive: endpoint.id == activeId,
                  activeModel: activeModel,
                )
              : _EndpointCard(
                  provider: provider,
                  endpoint: endpoint,
                  isActive: endpoint.id == activeId,
                  activeModel: activeModel,
                ),
        if (provider != ImageProviderType.novelAi) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showEditDialog(context, provider, null),
            icon: const Icon(CupertinoIcons.add_circled, size: 18),
            label: const Text('添加中转站'),
          ),
        ],
      ],
    );
  }
}

class _OfficialNovelAiCard extends StatefulWidget {
  final ApiEndpoint endpoint;
  final bool isActive;
  final String? activeModel;

  const _OfficialNovelAiCard({
    required this.endpoint,
    required this.isActive,
    required this.activeModel,
  });

  @override
  State<_OfficialNovelAiCard> createState() => _OfficialNovelAiCardState();
}

class _OfficialNovelAiCardState extends State<_OfficialNovelAiCard> {
  bool _expanded = false;
  bool _testing = false;
  String? _status;
  OfficialNovelAiAccount? _account;

  Future<void> _activate(String model) async {
    await sl<SettingsViewModel>().setActive(
      ImageProviderType.novelAi,
      widget.endpoint.id,
      model,
    );
    if (mounted) {
      showFloatingToast(context, '已切换到 NovelAI 官方 · $model',
          icon: CupertinoIcons.checkmark_circle_fill);
    }
  }

  Future<void> _editToken() async {
    final store = sl<OfficialNovelAiTokenStore>();
    final controller = TextEditingController(text: await store.read() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('NovelAI 官方 Token'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Persistent API Token',
            helperText: '仅安全保存于本机，且仅发送到 NovelAI 官方 HTTPS 域名。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await store.write(controller.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == true && mounted) {
      setState(() {
        _status = 'Token 已安全保存';
        _account = null;
      });
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
      _account = null;
    });
    try {
      final token = await sl<OfficialNovelAiTokenStore>().read();
      final stopwatch = Stopwatch()..start();
      final account =
          await sl<OfficialNovelAiApiService>().verifyToken(token ?? '');
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _account = account;
          _status = 'Token 有效 · ${stopwatch.elapsedMilliseconds}ms';
        });
      }
    } catch (error) {
      if (mounted)
        setState(() => _status =
            error.toString().replaceFirst('AppException(null): ', ''));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isActive
              ? colors.primary.withValues(alpha: .5)
              : colors.onSurface.withValues(alpha: .08),
          width: widget.isActive ? 1.2 : .5,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            leading: Icon(CupertinoIcons.shield_lefthalf_fill,
                color: colors.primary),
            title: const Text('NovelAI 官方'),
            subtitle: const Text('image.novelai.net · 固定 HTTPS 官方渠道'),
            trailing: Icon(_expanded
                ? CupertinoIcons.chevron_up
                : CupertinoIcons.chevron_down),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '官方 Token 单独安全保存，仅发送到 NovelAI 官方 HTTPS 接口。',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.endpoint.models
                        .map((model) => ChoiceChip(
                              label: Text(model),
                              selected: widget.isActive &&
                                  widget.activeModel == model,
                              onSelected: (_) => _activate(model),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _editToken,
                        icon: const Icon(CupertinoIcons.lock_fill, size: 16),
                        label: const Text('设置 Token'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _test,
                        icon: _testing
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(CupertinoIcons.wifi, size: 16),
                        label: Text(_testing ? '验证中…' : '验证 Token'),
                      ),
                    ],
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 10),
                    Text(_status!,
                        style: TextStyle(
                            fontSize: 12,
                            color: _account == null
                                ? colors.onSurfaceVariant
                                : Colors.greenAccent.shade400)),
                  ],
                  if (_account != null) ...[
                    const SizedBox(height: 6),
                    Text(
                        [
                          if (_account!.tier?.isNotEmpty == true)
                            '套餐：${_account!.tier}',
                          if (_account!.anlas != null)
                            'Anlas：${_account!.anlas}',
                          if (_account!.v5UsagePercent != null)
                            'V5 额度：${_account!.v5UsagePercent!.toStringAsFixed(1)}%',
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EndpointCard extends StatefulWidget {
  final ImageProviderType provider;
  final ApiEndpoint endpoint;
  final bool isActive;
  final String? activeModel;

  const _EndpointCard({
    required this.provider,
    required this.endpoint,
    required this.isActive,
    required this.activeModel,
  });

  @override
  State<_EndpointCard> createState() => _EndpointCardState();
}

class _EndpointCardState extends State<_EndpointCard> {
  bool _expanded = false;
  bool _isTesting = false;
  String? _testStatus;

  String _displayName(ApiEndpoint endpoint) {
    if (widget.provider != ImageProviderType.novelAi) {
      return endpoint.name.isEmpty ? '未命名' : endpoint.name;
    }
    return switch (endpoint.id) {
      AppConstants.novelAiChatCompletionsEndpointId => '7877',
      AppConstants.novelAiImageGenerationsEndpointId => 'ikun',
      _ => endpoint.name.isEmpty ? '未命名' : endpoint.name,
    };
  }

  Future<void> _runTest() async {
    setState(() {
      _isTesting = true;
      _testStatus = null;
    });
    try {
      final url = widget.endpoint.baseUrl
          .replaceAll(RegExp(r'/+$'), '')
          .replaceAll(RegExp(r'/v1$'), '')
          .replaceAll(RegExp(r'/origin$'), '');
      final stopwatch = Stopwatch()..start();
      await Dio().get('$url/v1/models',
          options: Options(
              headers: {'Authorization': 'Bearer ${widget.endpoint.apiKey}'}));
      stopwatch.stop();
      if (mounted)
        setState(
            () => _testStatus = '连接成功 · ${stopwatch.elapsedMilliseconds}ms');
    } on DioException catch (error) {
      if (mounted)
        setState(() => _testStatus = error.response == null
            ? '连接失败：${error.type.name}'
            : '服务器返回 ${error.response!.statusCode}，但连接成功');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _activate(String model) async {
    await sl<SettingsViewModel>()
        .setActive(widget.provider, widget.endpoint.id, model);
    if (mounted)
      showFloatingToast(context, '已切换到 ${widget.endpoint.name} · $model',
          icon: CupertinoIcons.checkmark_circle_fill);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final endpoint = widget.endpoint;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: widget.isActive
                ? colors.primary.withValues(alpha: .5)
                : colors.onSurface.withValues(alpha: .08)),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            leading: Icon(
                widget.isActive
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color:
                    widget.isActive ? colors.primary : colors.onSurfaceVariant),
            title: Text(_displayName(endpoint)),
            subtitle: Text(
                endpoint.baseUrl.isEmpty ? '未填写 Base URL' : endpoint.baseUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            trailing: Icon(_expanded
                ? CupertinoIcons.chevron_up
                : CupertinoIcons.chevron_down),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (endpoint.models.isEmpty)
                      const Text('尚未添加任何模型', style: TextStyle(fontSize: 12))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: endpoint.models
                            .map((model) => ChoiceChip(
                                  label: Text(model),
                                  selected: widget.isActive &&
                                      widget.activeModel == model,
                                  onSelected: (_) => _activate(model),
                                ))
                            .toList(),
                      ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: _isTesting ? null : _runTest,
                          icon: const Icon(CupertinoIcons.wifi, size: 16),
                          label: Text(_isTesting ? '测试中…' : '测试连接')),
                      OutlinedButton.icon(
                          onPressed: () => _showEditDialog(
                              context, widget.provider, endpoint),
                          icon: const Icon(CupertinoIcons.pencil, size: 16),
                          label: const Text('编辑')),
                    ]),
                    if (_testStatus != null) ...[
                      const SizedBox(height: 8),
                      Text(_testStatus!,
                          style: TextStyle(
                              fontSize: 12, color: colors.onSurfaceVariant))
                    ],
                  ]),
            ),
        ],
      ),
    );
  }
}

Future<void> _showEditDialog(BuildContext context, ImageProviderType provider,
    ApiEndpoint? existing) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final url = TextEditingController(text: existing?.baseUrl ?? '');
  final key = TextEditingController(text: existing?.apiKey ?? '');
  final modelInput = TextEditingController();
  final models = [...(existing?.models ?? const <String>[])];
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
              title: Text(existing == null ? '添加中转站' : '编辑中转站'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '名称')),
                const SizedBox(height: 12),
                TextField(
                    controller: url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Base URL')),
                const SizedBox(height: 12),
                TextField(
                    controller: key,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'API Key')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: modelInput,
                          decoration: const InputDecoration(hintText: '输入模型名'),
                          onSubmitted: (value) => setState(() {
                                if (value.trim().isNotEmpty &&
                                    !models.contains(value.trim()))
                                  models.add(value.trim());
                                modelInput.clear();
                              }))),
                  IconButton(
                      onPressed: () => setState(() {
                            final value = modelInput.text.trim();
                            if (value.isNotEmpty && !models.contains(value))
                              models.add(value);
                            modelInput.clear();
                          }),
                      icon: const Icon(CupertinoIcons.add_circled_solid)),
                ]),
                Wrap(
                    spacing: 6,
                    children: models
                        .map((model) => Chip(
                            label: Text(model),
                            onDeleted: () =>
                                setState(() => models.remove(model))))
                        .toList()),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () async {
                      if (name.text.trim().isEmpty || url.text.trim().isEmpty)
                        return;
                      final endpoint = ApiEndpoint(
                          id: existing?.id ?? const Uuid().v4(),
                          name: name.text.trim(),
                          baseUrl: url.text.trim(),
                          apiKey: key.text.trim(),
                          models: models,
                          protocol: existing?.protocol ?? 'openaiChat');
                      final vm = sl<SettingsViewModel>();
                      if (existing == null) {
                        await vm.addEndpoint(provider, endpoint);
                      } else {
                        await vm.updateEndpoint(provider, endpoint);
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: const Text('保存')),
              ],
            )),
  );
  name.dispose();
  url.dispose();
  key.dispose();
  modelInput.dispose();
}
