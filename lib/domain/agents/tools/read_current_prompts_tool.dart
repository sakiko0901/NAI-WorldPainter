import 'dart:convert';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/prompt_box_accessor.dart';

/// 读取用户当前提示词框内容（4 个框 + version）。
class ReadCurrentPromptsTool extends AgentTool {
  final PromptBoxAccessor _accessor;
  ReadCurrentPromptsTool(this._accessor);

  @override
  String get name => 'read_current_prompts';

  @override
  String get description =>
      '读取用户当前提示词框内容。4 个框：positive（正向主提示词）、negative（负向主提示词）、'
      'inpaint_positive（局部重绘正向）、inpaint_negative（局部重绘负向）。'
      '角色列表会回显每个角色当前的 position:{x,y}，未指定时为 null。'
      '返回 version 字段表示当前版本号，可用于检测后续是否被修改。'
      '\n\n【重要】inpaint_positive 和 inpaint_negative 是"局部重绘"专用框，'
      '只有在局部重绘模式下才有意义；常规文生图模式下这两个框是上次遗留的、不会被使用，'
      '不要基于它们的内容做判断，也不要写入它们。'
      '\n\n当用户说"在现有基础上改"、"加个 XX 效果"、"换成夜晚"等涉及修改现有提示词的请求时调用。'
      '新对话开始时若用户没明确要求基于现有提示词修改，不要主动调用（提示词框可能是上次生图遗留的）。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final isInpainting = _accessor.isInpaintingMode;
    final chars = _accessor.characters;
    final charJson = <Map<String, dynamic>>[];
    for (int i = 0; i < chars.length; i++) {
      final c = chars[i];
      charJson.add({
        'index': i + 1,
        'prompt': c.prompt,
        'uc': c.uc ?? '',
        'enabled': c.enabled,
        'position': c.centerX != null && c.centerY != null
            ? {'x': c.centerX, 'y': c.centerY}
            : null,
      });
    }
    final data = {
      'positive': _accessor.positive,
      'negative': _accessor.negative,
      'inpaint_positive': _accessor.inpaintPositive,
      'inpaint_negative': _accessor.inpaintNegative,
      'characters': charJson,
      'version': _accessor.version,
      'is_inpainting_mode': isInpainting,
    };
    final text = jsonEncode(data);
    final buf = StringBuffer();
    buf.writeln('当前提示词框内容（version=${_accessor.version}，'
        '当前模式：${isInpainting ? "局部重绘" : "文生图"}）：');
    if (_accessor.positive.isNotEmpty) {
      buf.writeln('【正向】');
      buf.writeln(_accessor.positive);
    } else {
      buf.writeln('【正向】（空）');
    }
    if (_accessor.negative.isNotEmpty) {
      buf.writeln('【负向】');
      buf.writeln(_accessor.negative);
    } else {
      buf.writeln('【负向】（空）');
    }
    if (isInpainting) {
      if (_accessor.inpaintPositive.isNotEmpty) {
        buf.writeln('【局部重绘正向】');
        buf.writeln(_accessor.inpaintPositive);
      } else {
        buf.writeln('【局部重绘正向】（空）');
      }
      if (_accessor.inpaintNegative.isNotEmpty) {
        buf.writeln('【局部重绘负向】');
        buf.writeln(_accessor.inpaintNegative);
      } else {
        buf.writeln('【局部重绘负向】（空）');
      }
    } else {
      buf.writeln('【局部重绘正向/负向】当前非局部重绘模式，inpaint 框不会被使用，禁止写入。');
    }
    if (chars.isEmpty) {
      buf.writeln('【多角色】未启用任何角色卡（单角色生图）');
    } else {
      buf.writeln('【多角色】共 ${chars.length} 个角色卡：');
      for (int i = 0; i < chars.length; i++) {
        final c = chars[i];
        final status = c.enabled ? '启用' : '禁用';
        buf.writeln('  角色${i + 1}（$status）：');
        buf.writeln('    prompt：${c.prompt.isEmpty ? "（空）" : c.prompt}');
        if (c.centerX != null && c.centerY != null) {
          buf.writeln(
            '    position：(${c.centerX!.toStringAsFixed(3)}, ${c.centerY!.toStringAsFixed(3)})',
          );
        } else {
          buf.writeln('    position：未指定');
        }
        if (c.uc != null && c.uc!.isNotEmpty) {
          buf.writeln('    uc：${c.uc}');
        }
      }
    }
    return ToolResult.success(
      buf.toString(),
      displayText: '已读取提示词框',
      followUpHint: text,
    );
  }
}
