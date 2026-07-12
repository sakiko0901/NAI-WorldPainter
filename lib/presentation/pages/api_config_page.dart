import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
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
    // 总是再 reload 一次，避免单例 vm 先前 loadSettings 时机太早导致 prefs 未就绪
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
    return Scaffold(
      appBar: AppBar(
        title: Text('API 配置'),
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
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _ProviderTab(provider: ImageProviderType.novelAi),
                _ProviderTab(provider: ImageProviderType.gpt),
                _ProviderTab(provider: ImageProviderType.nanoBanana),
              ],
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
    _vm = sl<SettingsViewModel>();
    _vm.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onChange);
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
        if (endpoints.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Icon(CupertinoIcons.cube_box,
                    size: 36,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.25)),
                SizedBox(height: 12),
                Text(
                  '还没有配置任何中转站',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 4),
                Text(
                  '点击下方按钮添加',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                      fontSize: 12),
                ),
              ],
            ),
          )
        else
          for (final ep in endpoints)
            _EndpointCard(
              provider: provider,
              endpoint: ep,
              isActive: ep.id == activeId,
              activeModel: activeModel,
            ),
        if (provider != ImageProviderType.novelAi) ...[
          SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showEditDialog(context, provider, null),
            icon: Icon(CupertinoIcons.add_circled, size: 18),
            label: Text('添加中转站'),
          ),
        ],
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
  int? _latencyMs;
  String? _testError;

  Future<void> _runTest() async {
    setState(() {
      _isTesting = true;
      _latencyMs = null;
      _testError = null;
    });
    try {
      final url = widget.endpoint.baseUrl
          .replaceAll(RegExp(r'/+$'), '')
          .replaceAll(RegExp(r'/v1$'), '');
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);
      final sw = Stopwatch()..start();
      await dio.get(
        '$url/v1/models',
        options: Options(
            headers: {'Authorization': 'Bearer ${widget.endpoint.apiKey}'}),
      );
      sw.stop();
      setState(() {
        _latencyMs = sw.elapsedMilliseconds;
      });
    } catch (e) {
      String msg;
      if (e is DioException && e.response != null) {
        msg = '服务器返回 ${e.response!.statusCode}，但连接成功';
      } else if (e is DioException) {
        msg = '连接失败: ${e.message ?? e.type.name}';
      } else {
        msg = '连接失败: $e';
      }
      setState(() => _testError = msg);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _setActive(String model) async {
    final vm = sl<SettingsViewModel>();
    await vm.setActive(widget.provider, widget.endpoint.id, model);
    if (mounted) {
      showFloatingToast(
        context,
        '已切换到 ${widget.endpoint.name} · $model',
        icon: CupertinoIcons.checkmark_circle_fill,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ep = widget.endpoint;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isActive
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          width: widget.isActive ? 1.2 : 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.25),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ep.name.isEmpty ? '未命名' : ep.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          ep.baseUrl.isEmpty ? '未填写 Base URL' : ep.baseUrl,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${ep.models.length} 模型',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.5)),
                  ),
                  Icon(
                    _expanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  SizedBox(width: 4),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.12)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ep.models.isEmpty)
                    Text(
                      '尚未添加模型，点击「编辑」添加',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.5)),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ep.models.map((m) {
                        final isActiveModel =
                            widget.isActive && widget.activeModel == m;
                        return InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _setActive(m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isActiveModel
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.25)
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActiveModel
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isActiveModel) ...[
                                  Icon(
                                    CupertinoIcons.checkmark_alt,
                                    size: 12,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  SizedBox(width: 4),
                                ],
                                Text(
                                  m,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isTesting ? null : _runTest,
                        icon: _isTesting
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(CupertinoIcons.wifi, size: 14),
                        label: Text(_isTesting ? '测试中…' : '测试连接'),
                      ),
                      SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showEditDialog(context, widget.provider, ep),
                        icon: Icon(CupertinoIcons.pencil, size: 14),
                        label: Text('编辑'),
                      ),
                      if (widget.provider != ImageProviderType.novelAi) ...[
                        const Spacer(),
                        IconButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('删除中转站'),
                                content: Text('确定要删除「${ep.name}」吗？该操作不可撤销。'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text('取消'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: Colors.redAccent),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await sl<SettingsViewModel>()
                                  .removeEndpoint(widget.provider, ep.id);
                              if (context.mounted) {
                                showFloatingToast(context, '已删除');
                              }
                            }
                          },
                          icon: Icon(CupertinoIcons.trash,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                  if (_latencyMs != null) ...[
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(CupertinoIcons.checkmark_circle_fill,
                            size: 14, color: Colors.greenAccent.shade400),
                        SizedBox(width: 6),
                        Text('延迟 ${_latencyMs}ms',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.greenAccent.shade400)),
                      ],
                    ),
                  ],
                  if (_testError != null) ...[
                    SizedBox(height: 8),
                    Text(
                      _testError!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.orangeAccent),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showEditDialog(
  BuildContext context,
  ImageProviderType provider,
  ApiEndpoint? existing,
) async {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final urlCtrl = TextEditingController(text: existing?.baseUrl ?? '');
  final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
  final modelInputCtrl = TextEditingController();
  final models = [...(existing?.models ?? const <String>[])];

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              title: Text(existing == null ? '添加中转站' : '编辑中转站'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        hintText: '例如 主中转站',
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: urlCtrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: '例如 https://api.openai.com',
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: keyCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                      ),
                    ),
                    SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '模型列表',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: modelInputCtrl,
                            decoration: const InputDecoration(
                              hintText: '输入模型名后回车或点 +',
                              isDense: true,
                            ),
                            onSubmitted: (v) {
                              final t = v.trim();
                              if (t.isEmpty) return;
                              setState(() {
                                if (!models.contains(t)) models.add(t);
                                modelInputCtrl.clear();
                              });
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(CupertinoIcons.add_circled_solid),
                          onPressed: () {
                            final t = modelInputCtrl.text.trim();
                            if (t.isEmpty) return;
                            setState(() {
                              if (!models.contains(t)) models.add(t);
                              modelInputCtrl.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    if (models.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '尚未添加任何模型',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.5)),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final m in models)
                            Chip(
                              label: Text(m, style: TextStyle(fontSize: 12)),
                              onDeleted: () => setState(() => models.remove(m)),
                              deleteIconColor: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final url = urlCtrl.text.trim();
                    final key = keyCtrl.text.trim();
                    if (name.isEmpty || url.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('名称和 Base URL 不能为空')),
                      );
                      return;
                    }
                    final vm = sl<SettingsViewModel>();
                    if (existing == null) {
                      await vm.addEndpoint(
                        provider,
                        ApiEndpoint(
                          id: const Uuid().v4(),
                          name: name,
                          baseUrl: url,
                          apiKey: key,
                          models: models,
                        ),
                      );
                    } else {
                      await vm.updateEndpoint(
                        provider,
                        existing.copyWith(
                          name: name,
                          baseUrl: url,
                          apiKey: key,
                          models: models,
                        ),
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      showFloatingToast(
                        context,
                        '已保存配置',
                        icon: CupertinoIcons.checkmark_circle_fill,
                      );
                    }
                  },
                  child: Text('保存'),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  nameCtrl.dispose();
  urlCtrl.dispose();
  keyCtrl.dispose();
  modelInputCtrl.dispose();
}
