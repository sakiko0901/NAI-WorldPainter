import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/novelai_connection.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
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
  bool _savingStreaming = false;
  String? _status;
  OfficialNovelAiAccount? _account;

  bool get _isCustom =>
      NovelAiConnection.isCustomBaseUrl(widget.endpoint.baseUrl);

  Future<void> _setStreaming(bool enabled) async {
    setState(() => _savingStreaming = true);
    try {
      await sl<SettingsViewModel>().updateEndpoint(
        ImageProviderType.novelAi,
        widget.endpoint.copyWith(streamEnabled: enabled),
      );
    } catch (_) {
      if (mounted) showFloatingToast(context, '流式设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _savingStreaming = false);
    }
  }

  Future<void> _activate(String model) async {
    await sl<SettingsViewModel>().setActive(
      ImageProviderType.novelAi,
      widget.endpoint.id,
      model,
    );
    if (mounted) {
      showFloatingToast(
          context, '已切换到 NovelAI ${_isCustom ? '自定义渠道' : '官方'} · $model',
          icon: CupertinoIcons.checkmark_circle_fill);
    }
  }

  Future<void> _editConnection() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _NovelAiConnectionDialog(endpoint: widget.endpoint),
    );
    if (saved == true && mounted) {
      setState(() {
        _status = '渠道配置已保存';
        _account = null;
      });
    }
  }

  Future<void> _test() async {
    if (_isCustom) return;
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
      if (mounted && !_isCustom) {
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
            title: Text(_isCustom ? 'NovelAI 自定义渠道' : 'NovelAI 官方'),
            subtitle: Text(
              _isCustom
                  ? widget.endpoint.baseUrl
                  : ApiConstants.officialImageBaseUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
                  Text(
                    _isCustom
                        ? '使用自定义 URL 与 API Key，适用于兼容 NovelAI 原生接口的中转平台。'
                        : 'URL 留空时使用官方渠道，也可填写中转平台的 URL 与 API Key。',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    key: const ValueKey('novelai-streaming-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用流式传输', style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      _isCustom
                          ? '实时预览生成进度，需要中转平台支持流式传输。'
                          : '实时预览生成进度；关闭后仅显示完成的图片。',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: widget.endpoint.streamEnabled ?? !_isCustom,
                    onChanged: _savingStreaming ? null : _setStreaming,
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
                        onPressed: _testing ? null : _editConnection,
                        icon: const Icon(CupertinoIcons.lock_fill, size: 16),
                        label: const Text('设置 URL 与 API Key'),
                      ),
                      if (!_isCustom)
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
                  if (!_isCustom && _account != null) ...[
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

class _NovelAiConnectionDialog extends StatefulWidget {
  final ApiEndpoint endpoint;

  const _NovelAiConnectionDialog({required this.endpoint});

  @override
  State<_NovelAiConnectionDialog> createState() =>
      _NovelAiConnectionDialogState();
}

class _NovelAiConnectionDialogState extends State<_NovelAiConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url;
  final _key = TextEditingController();
  late String _credentialUrl;
  bool _loadingKey = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final custom = NovelAiConnection.isCustomBaseUrl(widget.endpoint.baseUrl);
    _url = TextEditingController(text: custom ? widget.endpoint.baseUrl : '');
    _credentialUrl = NovelAiConnection.normalizeBaseUrl(_url.text);
    _loadKey(_credentialUrl);
  }

  Future<void> _loadKey(String baseUrl) async {
    try {
      final value =
          await sl<OfficialNovelAiTokenStore>().readForBaseUrl(baseUrl);
      if (!mounted || baseUrl != _credentialUrl) return;
      setState(() {
        _key.text = value ?? '';
        _loadingKey = false;
      });
    } catch (_) {
      if (!mounted || baseUrl != _credentialUrl) return;
      setState(() {
        _loadingKey = false;
        _error = '无法读取已保存的 API Key，请重新填写';
      });
    }
  }

  void _urlChanged(String value) {
    final baseUrl = NovelAiConnection.normalizeBaseUrl(value);
    if (baseUrl == _credentialUrl) return;
    setState(() {
      _credentialUrl = baseUrl;
      _key.clear();
      _error = null;
      _loadingKey = true;
    });
    _loadKey(baseUrl);
  }

  Future<void> _save() async {
    if (_saving || _loadingKey || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final baseUrl = NovelAiConnection.normalizeBaseUrl(_url.text);
      await sl<OfficialNovelAiTokenStore>().writeForBaseUrl(baseUrl, _key.text);
      await sl<SettingsViewModel>().updateEndpoint(
        ImageProviderType.novelAi,
        widget.endpoint.copyWith(
          baseUrl: baseUrl,
          apiKey: '',
          name: NovelAiConnection.isCustomBaseUrl(baseUrl)
              ? 'NovelAI 自定义渠道'
              : 'NovelAI 官方',
        ),
      );
      if (sl.isRegistered<GenerationViewModel>()) {
        await sl<GenerationViewModel>().loadModels();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，请重试';
        });
      }
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final custom = NovelAiConnection.isCustomBaseUrl(_url.text);
    return AlertDialog(
      title: const Text('NovelAI 渠道配置'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('novelai-channel-url'),
                controller: _url,
                readOnly: _saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _urlChanged,
                validator: (value) =>
                    NovelAiConnection.validateBaseUrl(value ?? ''),
                decoration: InputDecoration(
                  labelText: 'URL（可选）',
                  hintText: ApiConstants.officialImageBaseUrl,
                  hintStyle:
                      TextStyle(color: colors.onSurface.withValues(alpha: .35)),
                  helperText: '留空使用 NovelAI 官方渠道',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('novelai-channel-key'),
                controller: _key,
                readOnly: _saving || _loadingKey,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText:
                      custom ? 'API Key' : 'API Key / Persistent API Token',
                  helperText: _loadingKey
                      ? '读取当前渠道的 API Key…'
                      : custom
                          ? '填写该中转平台的 API Key'
                          : '填写 NovelAI 官方的 Persistent API Token',
                  helperMaxLines: 2,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(color: colors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || _loadingKey ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
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
