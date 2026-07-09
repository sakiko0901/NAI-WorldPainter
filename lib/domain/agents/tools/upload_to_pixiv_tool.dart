import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';
import 'package:nai_huishi/domain/usecases/upload_to_pixiv.dart';
import 'package:uuid/uuid.dart';

/// 上传图片到 Pixiv。副作用工具，需用户确认。
class UploadToPixivTool extends AgentTool {
  final UploadToPixivUseCase _useCase;
  UploadToPixivTool(this._useCase);

  @override
  String get name => 'upload_to_pixiv';

  @override
  String get description =>
      '把图片上传到 Pixiv。副作用工具，需用户确认。'
      'image_paths 是本地图片路径列表（最多 30 张）。'
      'title / caption / tags 为必填字段。'
      'is_r18 标记 NSFW 等级。'
      '上传成功后返回 illust_id。';

  @override
  bool get requireConfirmation => true;

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'image_paths': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '本地图片文件绝对路径列表（1-30 张）',
          },
          'title': {
            'type': 'string',
            'description': '作品标题',
          },
          'caption': {
            'type': 'string',
            'description': '作品说明/描述',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标签列表（中文或日文 tag）',
          },
          'is_r18': {
            'type': 'boolean',
            'description': '是否 R18，默认 false',
          },
        },
        'required': ['image_paths', 'title', 'tags'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final imagePaths = (arguments['image_paths'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final title = (arguments['title'] as String?)?.trim() ?? '';
    final caption = (arguments['caption'] as String?)?.trim() ?? '';
    final tags = (arguments['tags'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final isR18 = (arguments['is_r18'] as bool?) ?? false;

    if (imagePaths.isEmpty) return ToolResult.failure('image_paths 不能为空');
    if (title.isEmpty) return ToolResult.failure('title 不能为空');
    if (tags.isEmpty) return ToolResult.failure('tags 不能为空');

    try {
      final task = PixivUploadTask(
        id: const Uuid().v4(),
        imagePaths: imagePaths,
        title: title,
        caption: caption,
        tags: tags,
        isR18: isR18,
        allowTagEdit: true,
        stripMetadata: true,
        createdAt: DateTime.now(),
      );
      final result = await _useCase.call(task);
      if (result.illustId != null && result.illustId!.isNotEmpty) {
        return ToolResult.success(
          '已上传到 Pixiv，作品 ID：${result.illustId}。',
          displayText: '已上传到 Pixiv',
          followUpHint: '{"illust_id":"${result.illustId}"}',
        );
      }
      return ToolResult.failure('Pixiv 上传失败：${result.error ?? "未拿到 illustId"}');
    } catch (e) {
      return ToolResult.failure('Pixiv 上传失败：$e');
    }
  }
}
