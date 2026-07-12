import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/sr_model.dart';
import 'package:nai_huishi/domain/usecases/upscale_image.dart';

/// 图片超分（放大）。副作用工具，需用户确认。
class UpscaleImageTool extends AgentTool {
  final UpscaleImageUseCase _useCase;
  UpscaleImageTool(this._useCase);

  @override
  String get name => 'upscale_image';

  @override
  String get description => '对本地图片做超分放大（Real-ESRGAN / RealCUGAN）。副作用工具，需用户确认。'
      'image_path 是本地文件路径（绝对路径）。'
      'engine 可选 realesrgan_anime（4x，动漫专用）或 realcugan（2x/4x，自然风格）。'
      'scale 可选 2 或 4（realesrgan_anime 仅支持 4）。'
      '返回放大后的图片本地路径。';

  @override
  bool get requireConfirmation => true;

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'image_path': {
            'type': 'string',
            'description': '本地图片文件绝对路径',
          },
          'engine': {
            'type': 'string',
            'enum': ['realesrgan_anime', 'realcugan'],
            'description': '超分引擎，默认 realesrgan_anime',
          },
          'scale': {
            'type': 'integer',
            'enum': [2, 4],
            'description': '放大倍率，默认 4',
          },
        },
        'required': ['image_path'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final inputPath = (arguments['image_path'] as String?)?.trim() ?? '';
    if (inputPath.isEmpty) {
      return ToolResult.failure('image_path 不能为空');
    }
    final engineStr =
        (arguments['engine'] as String?)?.trim() ?? 'realesrgan_anime';
    final scale = (arguments['scale'] as int?) ?? 4;

    SrModel? model;
    for (final m in SrModel.presets) {
      if (m.engine.name == engineStr && m.scale == scale) {
        model = m;
        break;
      }
    }
    if (model == null) {
      // 引擎不匹配 scale 时回退到默认
      model = SrModel.presets.first;
    }
    try {
      await _useCase.prepare();
      final outputPath = await _useCase.execute(
        inputPath: inputPath,
        model: model,
      );
      return ToolResult.success(
        '已超分放大图片（${model.label}）。输出路径：$outputPath',
        displayText: '已放大：${model.label}',
        followUpHint: '{"output_path":"$outputPath"}',
      );
    } catch (e) {
      return ToolResult.failure('超分失败：$e');
    }
  }
}
