import 'package:nai_huishi/data/datasources/remote/model_capability_probe.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';

/// A separate client prevents testing a draft from changing the active chat client.
class ModelConnectionButton extends StatefulWidget {
  final String apiKey;
  final String baseUrl;
  final String model;
  final bool streaming;
  final void Function(int)? onContextWindow;
  const ModelConnectionButton(
      {super.key,
      required this.apiKey,
      required this.baseUrl,
      required this.model,
      this.streaming = false,
      this.onContextWindow});
  @override
  State<ModelConnectionButton> createState() => _ModelConnectionButtonState();
}

class _ModelConnectionButtonState extends State<ModelConnectionButton> {
  bool _running = false;
  String? _result;
  bool? _success;
  Dio? _client;
  @override
  void didUpdateWidget(covariant ModelConnectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKey != widget.apiKey ||
        oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.model != widget.model ||
        oldWidget.streaming != widget.streaming) {
      _client?.close(force: true);
      _client = null;
      _running = false;
      _result = null;
      _success = null;
    }
  }

  @override
  void dispose() {
    _client?.close(force: true);
    super.dispose();
  }

  Future<void> _test([String kind = '连接']) async {
    final client =
        Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
    _client = client;
    setState(() {
      _running = true;
      _result = null;
    });
    final watch = Stopwatch()..start();
    try {
      final api = LlmApiService(client);
      final probe = ModelCapabilityProbe(api);
      var passed = true;
      if (kind == '图片理解') {
        passed = await probe.image(
            apiKey: widget.apiKey,
            baseUrl: widget.baseUrl,
            model: widget.model);
      } else if (kind == '工具调用') {
        passed = await probe.tools(
            apiKey: widget.apiKey,
            baseUrl: widget.baseUrl,
            model: widget.model);
      } else if (kind == '容量') {
        final window = await ModelCapabilityProbe.contextWindow(client,
            apiKey: widget.apiKey,
            baseUrl: widget.baseUrl,
            model: widget.model);
        if (!mounted || _client != client) return;
        if (window != null) widget.onContextWindow?.call(window);
        setState(() {
          _success = window != null;
          _result =
              window == null ? '供应商未返回容量，请按模型文档手动填写。' : '已读取容量：$window tokens';
        });
        return;
      } else if (widget.streaming) {
        await api.chatCompletionsStreamWithTools(
          apiKey: widget.apiKey,
          baseUrl: widget.baseUrl,
          model: widget.model,
          messages: const [
            {'role': 'user', 'content': 'Reply only OK.'}
          ],
          tools: const [],
          onText: (_) {},
        );
      } else {
        await api.chatCompletions(
            apiKey: widget.apiKey,
            baseUrl: widget.baseUrl,
            model: widget.model,
            messages: [
              {'role': 'user', 'content': 'Reply only OK.'}
            ]);
      }
      if (!mounted || _client != client) return;
      setState(() {
        _success = passed;
        _result = passed
            ? '$kind检测通过 · ${watch.elapsedMilliseconds} ms'
            : '$kind检测未通过：模型未返回符合要求的结果，不代表一定不支持。';
      });
    } catch (e) {
      if (!mounted || _client != client) return;
      final error = e
          .toString()
          .replaceAll(widget.apiKey.isEmpty ? '\u0000' : widget.apiKey, '***');
      setState(() {
        _success = false;
        _result = '$kind检测失败：$error';
      });
    } finally {
      client.close(force: true);
      if (mounted && _client == client) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton.icon(
            onPressed: _running || widget.model.trim().isEmpty ? null : _test,
            icon: _running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    _success == true
                        ? Icons.check_circle_outline
                        : Icons.network_check,
                    size: 18),
            label: Text(_running ? '检测中…' : '检测连接')),
        Wrap(spacing: 4, children: [
          TextButton(
              onPressed: _running ? null : () => _test('图片理解'),
              child: const Text('检测图片理解')),
          TextButton(
              onPressed: _running ? null : () => _test('工具调用'),
              child: const Text('检测工具调用')),
          if (widget.onContextWindow != null)
            TextButton(
                onPressed: _running ? null : () => _test('容量'),
                child: const Text('读取容量')),
        ]),
        if (_result != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_result!,
                  style: TextStyle(
                      fontSize: 12,
                      color: _success == true
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error))),
      ]);
}
