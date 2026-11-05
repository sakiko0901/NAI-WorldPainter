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
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/api_config_widgets.dart';
import 'package:nai_huishi/presentation/widgets/api_endpoint_editor.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/studio_scaffold.dart';

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
  Widget build(BuildContext context) {
    final glass = FrostedTheme.of(context);
    return StudioScaffold(
      appBar: AppBar(
        title: const Text('API 与账号'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: FrostedSurface(
                    radius: 18,
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      controller: _tabController,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: glass.selection,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      labelColor: glass.onSelection,
                      unselectedLabelColor:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      labelStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      labelPadding: EdgeInsets.zero,
                      tabs: const [
                        Tab(text: 'NovelAI'),
                        Tab(text: 'GPT'),
                        Tab(text: 'Nano Banana'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabController,
                          children: const [
                            _ProviderTab(provider: ImageProviderType.novelAi),
                            _ProviderTab(provider: ImageProviderType.gpt),
                            _ProviderTab(
                                provider: ImageProviderType.nanoBanana),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      key: PageStorageKey('api-provider-${provider.name}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text('渠道与模型', style: Theme.of(context).textTheme.labelLarge),
        ),
        FrostedSurface(
          radius: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < endpoints.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: FrostedTheme.of(context).border),
                if (endpoints[i].id == AppConstants.novelAiOfficialEndpointId)
                  _OfficialNovelAiCard(
                    key: ValueKey(endpoints[i].id),
                    endpoint: endpoints[i],
                    isActive: endpoints[i].id == activeId,
                    activeModel: activeModel,
                  )
                else
                  _EndpointCard(
                    key: ValueKey(endpoints[i].id),
                    provider: provider,
                    endpoint: endpoints[i],
                    isActive: endpoints[i].id == activeId,
                    activeModel: activeModel,
                  ),
              ],
              if (endpoints.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('添加一个渠道，填写连接信息与模型即可开始使用。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              if (provider != ImageProviderType.novelAi) ...[
                if (endpoints.isNotEmpty)
                  Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: FrostedTheme.of(context).border),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton.icon(
                    onPressed: () => _showEditDialog(context, provider, null),
                    icon: const Icon(CupertinoIcons.plus, size: 18),
                    label: const Text('添加中转站'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OfficialNovelAiCard extends StatefulWidget {
  final ApiEndpoint endpoint;
  final bool isActive;
  final String? activeModel;

  const _OfficialNovelAiCard({
    super.key,
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
    if (sl.isRegistered<GenerationViewModel>()) {
      await sl<GenerationViewModel>().loadModels();
    }
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

  Future<void> _addModel() async {
    final model = await showDialog<String>(
      context: context,
      builder: (_) =>
          _NovelAiModelDialog(existingModels: widget.endpoint.models),
    );
    if (model == null || !mounted) return;
    try {
      await sl<SettingsViewModel>().updateEndpoint(
        ImageProviderType.novelAi,
        widget.endpoint.copyWith(models: [...widget.endpoint.models, model]),
      );
      if (sl.isRegistered<GenerationViewModel>()) {
        await sl<GenerationViewModel>().loadModels();
      }
      if (mounted) {
        showFloatingToast(context, '模型已添加',
            icon: CupertinoIcons.checkmark_circle_fill);
      }
    } catch (_) {
      if (mounted) showFloatingToast(context, '模型保存失败，请重试');
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
      if (mounted) {
        setState(() => _status =
            error.toString().replaceFirst('AppException(null): ', ''));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        ApiEndpointHeader(
          onTap: () => setState(() => _expanded = !_expanded),
          title: _isCustom ? 'NovelAI 自定义渠道' : 'NovelAI 官方',
          url: _isCustom
              ? widget.endpoint.baseUrl
              : ApiConstants.officialImageBaseUrl,
          active: widget.isActive,
          expanded: _expanded,
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                              : colors.primary)),
                ],
                if (!_isCustom && _account != null) ...[
                  const SizedBox(height: 6),
                  Text(
                      [
                        if (_account!.tier?.isNotEmpty == true)
                          '套餐：${_account!.tier}',
                        if (_account!.anlas != null) 'Anlas：${_account!.anlas}',
                        if (_account!.v5UsagePercent != null)
                          'V5 额度：${_account!.v5UsagePercent!.toStringAsFixed(1)}%',
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: 12, color: colors.onSurfaceVariant)),
                ],
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
                ApiModelList(
                  models: widget.endpoint.models,
                  activeModel: widget.isActive ? widget.activeModel : null,
                  onSelected: _activate,
                  action: TextButton.icon(
                    key: const ValueKey('novelai-add-model'),
                    icon: const Icon(CupertinoIcons.plus, size: 16),
                    label: const Text('新增模型'),
                    onPressed: _addModel,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NovelAiModelDialog extends StatefulWidget {
  final List<String> existingModels;

  const _NovelAiModelDialog({required this.existingModels});

  @override
  State<_NovelAiModelDialog> createState() => _NovelAiModelDialogState();
}

class _NovelAiModelDialogState extends State<_NovelAiModelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ApiConfigDialog(
        title: '新增模型',
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: TextFormField(
              key: const ValueKey('novelai-model-name'),
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: '模型名称',
                helperText: '填写渠道支持的完整模型名称',
                helperMaxLines: 2,
              ),
              validator: (value) {
                final model = value?.trim() ?? '';
                if (model.isEmpty) return '请输入模型名称';
                if (widget.existingModels.contains(model)) return '该模型已存在';
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(onPressed: _submit, child: const Text('添加')),
        ],
      );
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
    return ApiConfigDialog(
      title: 'NovelAI 渠道配置',
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
    super.key,
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
      if (mounted) {
        setState(
            () => _testStatus = '连接成功 · ${stopwatch.elapsedMilliseconds}ms');
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _testStatus = error.response == null
            ? '连接失败：${error.type.name}'
            : '服务器返回 ${error.response!.statusCode}，但连接成功');
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _activate(String model) async {
    await sl<SettingsViewModel>()
        .setActive(widget.provider, widget.endpoint.id, model);
    if (mounted) {
      showFloatingToast(context, '已切换到 ${widget.endpoint.name} · $model',
          icon: CupertinoIcons.checkmark_circle_fill);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final endpoint = widget.endpoint;
    return Column(
      children: [
        ApiEndpointHeader(
          onTap: () => setState(() => _expanded = !_expanded),
          title: _displayName(endpoint),
          url: endpoint.baseUrl.isEmpty ? '未填写 Base URL' : endpoint.baseUrl,
          active: widget.isActive,
          expanded: _expanded,
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                        onPressed: _isTesting ? null : _runTest,
                        icon: const Icon(CupertinoIcons.wifi, size: 16),
                        label: Text(_isTesting ? '测试中…' : '测试连接')),
                    OutlinedButton.icon(
                        onPressed: () =>
                            _showEditDialog(context, widget.provider, endpoint),
                        icon: const Icon(CupertinoIcons.pencil, size: 16),
                        label: const Text('编辑')),
                  ]),
                  if (_testStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(_testStatus!,
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant))
                  ],
                  const SizedBox(height: 16),
                  ApiModelList(
                    models: endpoint.models,
                    activeModel: widget.isActive ? widget.activeModel : null,
                    onSelected: _activate,
                  ),
                ]),
          ),
      ],
    );
  }
}

Future<void> _showEditDialog(BuildContext context, ImageProviderType provider,
        ApiEndpoint? existing) =>
    showDialog<void>(
      context: context,
      builder: (_) => ApiEndpointEditor(provider: provider, endpoint: existing),
    );
