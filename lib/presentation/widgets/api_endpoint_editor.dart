import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/api_endpoint.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/api_config_widgets.dart';
import 'package:uuid/uuid.dart';

class ApiEndpointEditor extends StatefulWidget {
  final ImageProviderType provider;
  final ApiEndpoint? endpoint;

  const ApiEndpointEditor({super.key, required this.provider, this.endpoint});

  @override
  State<ApiEndpointEditor> createState() => _ApiEndpointEditorState();
}

class _ApiEndpointEditorState extends State<ApiEndpointEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _apiKey;
  final _models = <TextEditingController>[];
  TextEditingController? _newModel;
  bool _saving = false;
  bool _showKey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.endpoint?.name ?? '');
    _url = TextEditingController(text: widget.endpoint?.baseUrl ?? '');
    _apiKey = TextEditingController(text: widget.endpoint?.apiKey ?? '');
    for (final model in widget.endpoint?.models ?? const <String>[]) {
      _models.add(TextEditingController(text: model));
    }
    if (_models.isEmpty) _models.add(TextEditingController());
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _apiKey.dispose();
    for (final controller in _models) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final models = _models
        .map((controller) => controller.text.trim())
        .where((model) => model.isNotEmpty)
        .toList();
    final existing = widget.endpoint;
    final endpoint = existing == null
        ? ApiEndpoint(
            id: const Uuid().v4(),
            name: _name.text.trim(),
            baseUrl: _url.text.trim(),
            apiKey: _apiKey.text.trim(),
            models: models,
          )
        : existing.copyWith(
            name: _name.text.trim(),
            baseUrl: _url.text.trim(),
            apiKey: _apiKey.text.trim(),
            models: models,
          );
    try {
      final vm = sl<SettingsViewModel>();
      if (existing == null) {
        await vm.addEndpoint(widget.provider, endpoint);
      } else {
        await vm.updateEndpoint(widget.provider, endpoint);
      }
      if (mounted) Navigator.pop(context);
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_saving,
      child: ApiConfigDialog(
        title: widget.endpoint == null ? '添加中转站' : '编辑中转站',
        subtitle: '填写连接信息和这个渠道支持的模型。',
        errorText: _error,
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('endpoint-name'),
                controller: _name,
                readOnly: _saving,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '渠道名称'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入渠道名称' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('endpoint-url'),
                controller: _url,
                readOnly: _saving,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                    labelText: 'Base URL', hintText: 'https://'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '请输入 Base URL'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('endpoint-key'),
                controller: _apiKey,
                readOnly: _saving,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  suffixIcon: IconButton(
                    tooltip: _showKey ? '隐藏 API Key' : '显示 API Key',
                    onPressed: () => setState(() => _showKey = !_showKey),
                    icon: Icon(
                        _showKey
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        size: 18),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child:
                    Divider(height: 1, color: FrostedTheme.of(context).border),
              ),
              Text('模型列表', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text('每行填写一个完整模型名称，可直接修改。空白行不会保存。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              for (var i = 0; i < _models.length; i++)
                Padding(
                  key: ObjectKey(_models[i]),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    key: ValueKey('endpoint-model-$i'),
                    controller: _models[i],
                    autofocus: identical(_models[i], _newModel),
                    readOnly: _saving,
                    minLines: 1,
                    maxLines: 3,
                    keyboardType: TextInputType.text,
                    inputFormatters: [
                      FilteringTextInputFormatter.singleLineFormatter
                    ],
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '模型 ${i + 1}',
                      hintText: '填写模型名称',
                      suffixIcon: IconButton(
                        tooltip: '删除模型 ${i + 1}',
                        onPressed: _saving
                            ? null
                            : () {
                                final removed = _models[i];
                                setState(() => _models.removeAt(i));
                                // The field must unmount before its controller.
                                WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => removed.dispose());
                              },
                        icon: const Icon(CupertinoIcons.minus_circle, size: 19),
                      ),
                    ),
                    validator: (value) {
                      final model = value?.trim() ?? '';
                      if (model.isEmpty) return null;
                      if (_models.where((c) => c.text.trim() == model).length >
                          1) {
                        return '模型名称重复';
                      }
                      return null;
                    },
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('endpoint-add-model'),
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _newModel = TextEditingController();
                            _models.add(_newModel!);
                          }),
                  icon: const Icon(CupertinoIcons.plus, size: 17),
                  label: const Text('添加模型'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}
