import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/llm_provider.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart'
    show showFloatingToast;

class LlmProviderEditPage extends StatefulWidget {
  final LlmChatViewModel vm;
  final String providerId;

  const LlmProviderEditPage({
    super.key,
    required this.vm,
    required this.providerId,
  });

  @override
  State<LlmProviderEditPage> createState() => _LlmProviderEditPageState();
}

class _LlmProviderEditPageState extends State<LlmProviderEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late List<TextEditingController> _modelControllers;

  @override
  void initState() {
    super.initState();
    final p = _findProvider();
    _nameController = TextEditingController(text: p?.name ?? '');
    _apiKeyController = TextEditingController(text: p?.apiKey ?? '');
    _baseUrlController = TextEditingController(text: p?.baseUrl ?? '');
    _modelControllers = (p?.models ?? const [])
        .map((m) => TextEditingController(text: m))
        .toList();
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
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label('名称'),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '如 OpenAI 官方 / DeepSeek / 自建中转',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            _Label('API Key'),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                hintText: 'sk-...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            _Label('Base URL'),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                hintText: 'https://api.example.com/v1',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
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
                      _modelControllers.add(TextEditingController(text: ''));
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
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _modelControllers[i],
                        decoration: InputDecoration(
                          hintText: 'gpt-4o-mini / claude-3-5-sonnet / ...',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          prefixText: '${i + 1}. ',
                          prefixStyle: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.delete, size: 18),
                      onPressed: () {
                        setState(() {
                          _modelControllers[i].dispose();
                          _modelControllers.removeAt(i);
                        });
                      },
                    ),
                  ],
                ),
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

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final models = _modelControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (name.isEmpty) {
      showFloatingToast(context, '请填写名称');
      return;
    }
    if (baseUrl.isEmpty) {
      showFloatingToast(context, '请填写 Base URL');
      return;
    }

    final list = List<LlmProvider>.from(widget.vm.providers);
    final idx = list.indexWhere((p) => p.id == widget.providerId);
    if (idx < 0) {
      // 新建（理论上 initState 已经在 manage 页加了一个空 provider，这里不该走到）
      final newProvider = LlmProvider.create(
        id: widget.providerId,
        name: name,
        apiKey: apiKey,
        baseUrl: baseUrl,
        models: models,
      );
      list.add(newProvider);
    } else {
      final old = list[idx];
      list[idx] = LlmProvider(
        id: old.id,
        name: name,
        apiKey: apiKey,
        baseUrl: baseUrl,
        models: models,
        createdAt: old.createdAt,
      );
    }
    await widget.vm.setProviders(list);
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
