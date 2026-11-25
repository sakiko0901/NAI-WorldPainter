import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/usecases/get_history.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:path_provider/path_provider.dart';

bool _hasImage(GenerationTask task) =>
    !task.isInternal &&
    task.status == AppConstants.taskSuccess &&
    (task.imagePath?.isNotEmpty == true || task.imageUrl?.isNotEmpty == true);

class ListGenerationImagesTool extends AgentTool {
  ListGenerationImagesTool(this._history, this._workspace);

  final GetHistoryUseCase _history;
  final List<GenerationTask> Function() _workspace;
  static const _pageSize = 10;

  @override
  String get name => 'list_generation_images';

  @override
  String get description => '列出工作台或历史图库里的已完成图片，返回时间、提示词摘要和任务 ID。'
      '可按正向提示词、模型或任务 ID 查找。拿到 ID 后调用 view_generation_image 看图。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'source': {
            'type': 'string',
            'enum': ['workspace', 'history'],
          },
          'query': {'type': 'string', 'description': '可选关键词，匹配正向提示词、模型或任务 ID'},
          'page': {'type': 'integer', 'minimum': 1, 'description': '页码，从 1 开始'},
        },
        'required': ['source'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final source = arguments['source'];
    if (source != 'workspace' && source != 'history') {
      return ToolResult.failure('请选择工作台或历史图库');
    }
    final query = (arguments['query'] as String?)?.trim().toLowerCase() ?? '';
    final terms = query.split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
    final page = arguments['page'] ?? 1;
    if (page is! int || page < 1) return ToolResult.failure('页码需为正整数');
    final tasks = source == 'workspace'
        ? _workspace().reversed
        : await _history.getCompleted();
    final matches = tasks.where((task) {
      if (!_hasImage(task)) return false;
      final searchable =
          '${task.prompt}\n${task.model}\n${task.taskId}'.toLowerCase();
      return terms.every(searchable.contains);
    }).toList();
    if (matches.isEmpty) return ToolResult.success('没有匹配的已完成图片。');
    final pageCount = (matches.length + _pageSize - 1) ~/ _pageSize;
    if (page > pageCount) {
      return ToolResult.failure('没有第 $page 页，共 $pageCount 页');
    }
    final items = matches.skip((page - 1) * _pageSize).take(_pageSize);
    final rows = items.map((task) {
      final prompt = String.fromCharCodes(task.prompt.trim().runes.take(180));
      return {
        'task_id': task.taskId,
        'created_at': task.createdAt.toLocal().toIso8601String(),
        'model': task.model,
        if (prompt.isNotEmpty) 'prompt_preview': prompt,
      };
    }).toList();
    return ToolResult.success(
      jsonEncode({
        'source': source,
        'page': page,
        'has_more': page < pageCount,
        'images': rows,
      }),
      displayText: '找到 ${matches.length} 张图片，已读取第 $page 页',
    );
  }
}

class ViewGenerationImageTool extends AgentTool {
  ViewGenerationImageTool({
    required GetHistoryUseCase history,
    required GenerationTask? Function() current,
    required GenerationTask? Function() latest,
    required List<GenerationTask> Function() workspace,
    required SaveImageUseCase saveImage,
    required bool directImages,
    CancelToken? cancelToken,
    Future<String> Function(String base64, String focus)? describe,
  })  : _history = history,
        _current = current,
        _latest = latest,
        _workspace = workspace,
        _saveImage = saveImage,
        _directImages = directImages,
        _cancelToken = cancelToken,
        _describe = describe;

  final GetHistoryUseCase _history;
  final GenerationTask? Function() _current;
  final GenerationTask? Function() _latest;
  final List<GenerationTask> Function() _workspace;
  final SaveImageUseCase _saveImage;
  final bool _directImages;
  final CancelToken? _cancelToken;
  final Future<String> Function(String base64, String focus)? _describe;

  static const toolName = 'view_generation_image';

  @override
  String get name => toolName;

  @override
  String get description => '读取实际图片。current 是工作台正在显示的图，latest 是最近完成的工作台结果，'
      'workspace 或 history 按 list_generation_images 返回的 task_id 读取。'
      '可用 focus 指定需观察的画面细节。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'source': {
            'type': 'string',
            'enum': ['current', 'latest', 'workspace', 'history'],
          },
          'task_id': {'type': 'string', 'description': '读取工作台或历史列表中的图片时必填'},
          'focus': {'type': 'string', 'description': '本次重点观察的画面内容'},
        },
        'required': ['source'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final source = arguments['source'];
    final taskId = arguments['task_id'];
    if ((source == 'workspace' || source == 'history') &&
        (taskId is! String || taskId.trim().isEmpty)) {
      return ToolResult.failure('请先列出图片，再传入对应的 task_id');
    }
    if (!_directImages && _describe == null) {
      return ToolResult.failure('请在助手设置中配置识图模型，或使用支持图片输入的主模型并开启多模态');
    }
    final task = switch (source) {
      'current' => _current(),
      'latest' => _latest(),
      'workspace' =>
        _workspace().where((task) => task.taskId == taskId).firstOrNull,
      'history' => await _history.getTask(taskId as String),
      _ => null,
    };
    if (task == null || !_hasImage(task)) {
      return ToolResult.failure('指定位置没有已完成的图片，请检查所选图片或任务 ID');
    }
    final String base64;
    try {
      base64 = await _readImage(task);
    } catch (_) {
      return ToolResult.failure('图片文件已失效或无法读取，请在工作台或历史图库确认原图');
    }
    final origin = source == 'history' ? 'history' : 'workspace';
    final time =
        (task.completedAt ?? task.createdAt).toLocal().toIso8601String();
    final reference = '图片来源：$origin，任务 ID：${task.taskId}，时间：$time。';
    if (_directImages) {
      return ToolResult.success(
        reference,
        displayText: '已读取生成图',
        imageDataUrl: 'data:image/png;base64,$base64',
      );
    }
    final description =
        await _describe!(base64, arguments['focus'] as String? ?? '');
    if (description.isEmpty) {
      return ToolResult.failure('识图模型没有返回可用描述，请检查配置或重试');
    }
    return ToolResult.success(
      '$reference\n识图结果：\n$description',
      displayText: '已分析生成图',
    );
  }

  Future<String> _readImage(GenerationTask task) async {
    final path = task.imagePath;
    if (path != null && await File(path).exists()) return _encodeImage(path);
    if (task.imageUrl?.isNotEmpty != true) {
      throw const FileSystemException('没有可读取的图片');
    }
    final temp =
        await (await getTemporaryDirectory()).createTemp('assistant-image-');
    try {
      final path = await _saveImage.saveTransient(task,
          downloadDirectory: temp, cancelToken: _cancelToken);
      return await _encodeImage(path);
    } finally {
      try {
        await temp.delete(recursive: true);
      } on FileSystemException {
        // 图片已读出时，保留读取结果。
      }
    }
  }

  static Future<String> _encodeImage(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final codec = await ui.instantiateImageCodecWithSize(buffer,
        getTargetSize: (width, height) {
      const maxSide = 1280;
      final longest = math.max(width, height);
      if (longest <= maxSide) return const ui.TargetImageSize();
      return ui.TargetImageSize(
        width: math.max(1, (width * maxSide / longest).round()),
        height: math.max(1, (height * maxSide / longest).round()),
      );
    });
    try {
      final frame = await codec.getNextFrame();
      try {
        final data =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('图片编码失败');
        return base64Encode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
