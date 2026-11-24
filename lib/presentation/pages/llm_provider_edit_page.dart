import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/model_connection_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/domain/entities/llm_role_config.dart';
import 'package:nai_huishi/presentation/widgets/studio_select.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart'
    show showFloatingToast;

class LlmProviderEditPage extends StatefulWidget {
  final LlmChatViewModel vm;
  final String providerId;
  final LlmProvider? draft;

  const LlmProviderEditPage({
    super.key,
    required this.vm,
    required this.providerId,
    this.draft,
  });

  @override
  State<LlmProviderEditPage> createState() => _LlmProviderEditPageState();
}

class _LlmProviderEditPageState extends State<LlmProviderEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late LlmApiProtocol _protocol;
  final _backupKeyControllers = <TextEditingController>[];
  late TextEditingController _selectedKey;
  bool _keySelectionChanged = false;
  late List<TextEditingController> _modelControllers;
  final _streaming = <TextEditingController, bool>{};

  @override
  void initState() {
    super.initState();
    final p = _findProvider() ?? widget.draft;
    _protocol = p?.protocol ?? LlmApiProtocol.openAiCompatible;
    _nameController = TextEditingController(text: p?.name ?? '');
    _apiKeyController = TextEditingController(text: p?.apiKey ?? '');
    _baseUrlController = TextEditingController(text: p?.baseUrl ?? '');
    _apiKeyController.addListener(_refresh);
    _baseUrlController.addListener(_refresh);
    _backupKeyControllers.addAll(
      (p?.backupApiKeys ?? const <String>[]).map(
        (key) => TextEditingController(text: key)..addListener(_refresh),
      ),
    );
    final activeIndex = p == null ? 0 : widget.vm.activeGeminiKeyIndex(p);
    _selectedKey = _keyControllers[activeIndex];
    _modelControllers = (p?.models ?? const [])
        .map((m) => TextEditingController(text: m)..addListener(_refresh))
        .toList();
    for (final controller in _modelControllers) {
      _streaming[controller] = p?.streaming[controller.text] ??
          (widget.draft != null ||
              (widget.vm.mainBinding.providerId == p?.id &&
                  widget.vm.mainBinding.model == controller.text));
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  LlmProvider? _findProvider() {
    for (final p in widget.vm.providers) {
      if (p.id == widget.providerId) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    for (final c in _backupKeyControllers) {
      c.dispose();
    }
    for (final c in _modelControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _findProvider() == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '新建供应商' : '编辑供应商'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.checkmark_circle_fill),
            tooltip: '保存供应商',
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('连接你的模型', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('配置连接后，为每个模型检测可用性。检测会发送一条简短请求。',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            const _Label('名称'),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '如 OpenAI 官方 / DeepSeek / 自建中转',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none),
                filled: true,
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            const _Label('接口类型'),
            StudioSelect<LlmApiProtocol>(
              id: 'llm-provider-protocol',
              label: '接口类型',
              value: _protocol,
              options: [
                for (final protocol in LlmApiProtocol.values)
                  StudioSelectOption(protocol, protocol.label),
              ],
              onChanged: _changeProtocol,
            ),
            const SizedBox(height: 16),
            const _Label('API Key'),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                hintText: '输入 API Key',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none),
                filled: true,
                isDense: true,
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            const _Label('Base URL'),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                hintText: 'https://api.example.com/v1',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none),
                filled: true,
                isDense: true,
              ),
            ),
            if (_canRotateKeys) ..._buildKeyRotation(),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('模型',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _modelControllers.add(TextEditingController(text: '')
                        ..addListener(_refresh));
                    });
                  },
                  icon: const Icon(CupertinoIcons.add, size: 16),
                  label: const Text('添加模型'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < _modelControllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FrostedSurface(
                    blur: 0,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _modelControllers[i],
                                  decoration: InputDecoration(
                                    hintText: '填写模型 ID',
                                    border: const OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(14)),
                                        borderSide: BorderSide.none),
                                    filled: true,
                                    isDense: true,
                                    prefixText: '${i + 1}. ',
                                    prefixStyle: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon:
                                    const Icon(CupertinoIcons.delete, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _modelControllers[i].dispose();
                                    _modelControllers.removeAt(i);
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('流式输出'),
                            subtitle: const Text('关闭后等待完整回复'),
                            value: _streaming[_modelControllers[i]] ?? true,
                            onChanged: (value) => setState(
                                () => _streaming[_modelControllers[i]] = value),
                          ),
                          ModelConnectionButton(
                              key: ObjectKey(_modelControllers[i]),
                              streaming:
                                  _streaming[_modelControllers[i]] ?? true,
                              config: _connection(
                                  _modelControllers[i].text.trim())),
                        ])),
              ),
            if (_modelControllers.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  '还没有添加模型。每个供应商至少需要一个模型才能被角色绑定使用。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  bool get _canRotateKeys =>
      _protocol.supportsKeyRotation(_baseUrlController.text);

  List<TextEditingController> get _keyControllers =>
      [_apiKeyController, ..._backupKeyControllers];

  List<String> get _filledKeys => {
        for (final controller in _keyControllers)
          if (controller.text.trim().isNotEmpty) controller.text.trim(),
      }.toList();

  LlmRoleConfig _connection(String model) {
    final keys = _canRotateKeys ? _filledKeys : const <String>[];
    final selected = keys.indexOf(_selectedKey.text.trim());
    return LlmRoleConfig(
      apiKey: keys.firstOrNull ?? _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: model,
      protocol: _protocol,
      backupApiKeys: keys.skip(1).toList(),
      geminiKeyIndex: selected < 0 ? 0 : selected,
      thinkingLevel:
          _findProvider()?.thinkingLevels[model] ?? LlmThinkingLevel.automatic,
    );
  }

  void _changeProtocol(LlmApiProtocol protocol) {
    if (protocol == _protocol) return;
    final baseUrl = _baseUrlController.text.trim();
    final applyDefault = baseUrl.isEmpty ||
        (baseUrl == _protocol.defaultBaseUrl &&
            _apiKeyController.text.trim().isEmpty);
    setState(() => _protocol = protocol);
    if (applyDefault) _baseUrlController.text = protocol.defaultBaseUrl;
  }

  List<Widget> _buildKeyRotation() {
    final controllers = _keyControllers;
    return [
      const SizedBox(height: 16),
      for (var index = 1; index < controllers.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: ObjectKey(controllers[index]),
                  controller: controllers[index],
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '备用 Key ${index + 1}',
                    filled: true,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: '移除备用 Key ${index + 1}',
                icon: const Icon(CupertinoIcons.delete),
                onPressed: () => setState(() {
                  final removed = _backupKeyControllers.removeAt(index - 1);
                  if (_selectedKey == removed) {
                    _selectedKey = _apiKeyController;
                    _keySelectionChanged = true;
                  }
                  removed.removeListener(_refresh);
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => removed.dispose());
                }),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _backupKeyControllers
                .add(TextEditingController()..addListener(_refresh));
          }),
          icon: const Icon(CupertinoIcons.add, size: 16),
          label: const Text('添加备用 Key'),
        ),
      ),
      if (_filledKeys.length > 1) ...[
        const _Label('当前 Key'),
        StudioSelect<int>(
          id: 'llm-gemini-active-key',
          label: '当前 Key',
          value: _selectedKey.text.trim().isNotEmpty
              ? controllers.indexOf(_selectedKey)
              : controllers.indexWhere(
                  (controller) => controller.text.trim().isNotEmpty),
          options: [
            for (var index = 0; index < controllers.length; index++)
              if (controllers[index].text.trim().isNotEmpty)
                StudioSelectOption(
                    index, index == 0 ? 'Key 1（主 Key）' : 'Key ${index + 1}'),
          ],
          onChanged: (index) => setState(() {
            _selectedKey = controllers[index];
            _keySelectionChanged = true;
          }),
        ),
        const SizedBox(height: 6),
        Text('达到额度或频率限制时自动切换。手动选择后保存生效。',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    ];
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final connection = _connection('');
    final baseUrl = _baseUrlController.text.trim();
    final models = _modelControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    if (name.isEmpty) {
      showFloatingToast(context, '请填写名称');
      return;
    }
    if (baseUrl.isEmpty) {
      showFloatingToast(context, '请填写 Base URL');
      return;
    }

    final streaming = {
      for (final controller in _modelControllers)
        if (controller.text.trim().isNotEmpty)
          controller.text.trim(): _streaming[controller] ?? true,
    };
    final list = List<LlmProvider>.from(widget.vm.providers);
    final idx = list.indexWhere((p) => p.id == widget.providerId);
    final old = idx < 0 ? widget.draft : list[idx];
    final hasKeyRotation = connection.protocol.supportsKeyRotation(baseUrl);
    var keyIndex = connection.geminiKeyIndex;
    if (!hasKeyRotation) {
      keyIndex = old?.geminiKeyIndex ?? 0;
    } else if (!_keySelectionChanged && old != null) {
      final previous = [old.apiKey, ...old.backupApiKeys];
      final preferred =
          old.geminiKeyIndex >= 0 && old.geminiKeyIndex < previous.length
              ? previous[old.geminiKeyIndex]
              : old.apiKey;
      keyIndex =
          [connection.apiKey, ...connection.backupApiKeys].indexOf(preferred);
      if (keyIndex < 0) keyIndex = 0;
    }
    final provider =
        (old ?? LlmProvider.create(id: widget.providerId, name: name)).copyWith(
      name: name,
      apiKey: connection.apiKey,
      baseUrl: baseUrl,
      models: models,
      protocol: _protocol,
      backupApiKeys:
          hasKeyRotation ? connection.backupApiKeys : old?.backupApiKeys,
      geminiKeyIndex: keyIndex,
      streaming: streaming,
    );
    if (idx < 0) {
      list.add(provider);
    } else {
      list[idx] = provider;
    }
    await widget.vm.setProviders(list);
    if (_keySelectionChanged && hasKeyRotation) {
      widget.vm.selectGeminiKey(provider);
    }
    if (mounted) {
      showFloatingToast(context, '已保存');
      Navigator.pop(context);
    }
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
