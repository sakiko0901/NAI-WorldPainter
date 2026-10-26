import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/agents/prompt_box_accessor.dart';

/// 写入指定提示词框。append=true 追加，false 替换。
class WritePromptTool extends AgentTool {
  final PromptBoxAccessor _accessor;
  WritePromptTool(this._accessor);

  @override
  String get name => 'write_prompt';

  @override
  String get description => '把生成的提示词写入指定的提示词框。target 取值：'
      'positive（正向主提示词）、negative（负向主提示词）、'
      'inpaint_positive（局部重绘正向）、inpaint_negative（局部重绘负向）、'
      'character_1 ~ character_6（多角色各自的 prompt 框）、'
      'character_1_uc ~ character_6_uc（多角色各自的负向框）。'
      'mode=append（默认）追加到现有内容末尾，mode=replace 覆盖现有内容。'
      '\n\n【重要】inpaint_positive 和 inpaint_negative 是"局部重绘"专用框，仅当用户明确要求修改局部/重绘/修图时才能写入。'
      '若当前不是局部重绘模式（即文生图模式），调写 inpaint 框会被拒绝。'
      '常规生图请求只写 positive / negative。'
      '\n\n【多角色场景】当用户要求 2 人及以上生图时，每个角色的外貌、服装、动作应分别写入 character_1、character_2 等独立框，'
      '不要全部塞进 positive——避免多角色外貌混淆。多角色 prompt 不应再重复 positive 里的通用画质词。'
      '若 character_N 序号超出当前角色数，会自动补齐到对应数量。'
      '\n多角色场景下 character_N 是首选 target，positive 只放通用画质词（masterpiece / best quality 等）与画风词；'
      '角色名、发色、瞳色、服装、动作一律写入对应 character_N。'
      '\n【角色坐标】${AppConstants.assistantCharacterPositionPolicy}'
      'character_N 正向框支持可选 position:{x,y}，x/y 是 0..1 的归一化画布中心坐标（x 向右、y 向下）。'
      '\n\n【修改已有内容必须 read-then-write】修改用户现有提示词时，必须先调 `read_current_prompts` 读取目标框当前内容，'
      '基于实际内容决定 append 还是 replace，不要凭记忆/想象盲写；全新创作无需读取历史内容，可直接写入，新角色默认省略 position。'
      '\n\n【append 自动去重】append 模式会自动跳过已存在的 tag（按 tag 基础名比较，忽略权重符号），'
      '但仍建议你先 read 确认现状，避免重复添加相似 tag。'
      '\n\n【何时用 replace】当用户要求"换成 X"、"删掉 Y"、"重新编排"等需要改动中间或开头部分时，用 replace 覆盖整个框。'
      'replace 前必须先 read 全部原内容，再基于原内容做精细修改后整体写回——不要丢失用户已有内容。'
      '\n\n本工具不会触发图片生成，用户需手动点击"生成"按钮。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'description': '要写入的提示词框名称。可选值：positive / negative / '
                'inpaint_positive / inpaint_negative / '
                'character_1..character_6 / character_1_uc..character_6_uc',
          },
          'content': {
            'type': 'string',
            'description': '要写入的提示词内容（NovelAI 英文 tag）',
          },
          'mode': {
            'type': 'string',
            'enum': ['append', 'replace'],
            'description': 'append 追加到现有内容末尾（默认），replace 覆盖现有内容',
          },
          'position': {
            'type': 'object',
            'description':
                '默认省略，交给 V5 自动布局。仅当用户明确要求手动定位或指定坐标时使用，不能根据画面内容主动推算。仅用于 character_N 正向框，x 向右、y 向下，范围 0..1。',
            'properties': {
              'x': {'type': 'number', 'minimum': 0, 'maximum': 1},
              'y': {'type': 'number', 'minimum': 0, 'maximum': 1},
            },
            'required': ['x', 'y'],
            'additionalProperties': false,
          },
        },
        'required': ['target', 'content'],
      };

  /// 校验 target 名称合法（4 个主框 + character_N + character_N_uc）。
  static bool _isValidTarget(String t) {
    if (const {'positive', 'negative', 'inpaint_positive', 'inpaint_negative'}
        .contains(t)) {
      return true;
    }
    return RegExp(r'^character_([1-6])(_uc)?$').hasMatch(t);
  }

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final target = (arguments['target'] as String?)?.trim() ?? '';
    final content = (arguments['content'] as String?)?.trim() ?? '';
    final modeStr = (arguments['mode'] as String?)?.trim() ?? 'append';
    final append = modeStr == 'append';
    if (target.isEmpty) {
      return ToolResult.failure('target 不能为空');
    }
    if (!_isValidTarget(target)) {
      return ToolResult.failure(
          'target 非法：$target。合法取值：positive / negative / inpaint_positive / inpaint_negative / '
          'character_1..character_6 / character_1_uc..character_6_uc');
    }
    if (content.isEmpty) {
      return ToolResult.failure('content 不能为空');
    }

    final hasPosition = arguments.containsKey('position');
    double? centerX;
    double? centerY;
    if (hasPosition) {
      if (!RegExp(r'^character_[1-6]$').hasMatch(target)) {
        return ToolResult.failure(
          'position 仅可用于 character_1..character_6 正向角色框，不能用于 $target。',
        );
      }
      final rawPosition = arguments['position'];
      if (rawPosition is! Map ||
          rawPosition.keys.any((key) => key != 'x' && key != 'y')) {
        return ToolResult.failure(
          'position 必须是仅含 x、y 的对象，且两个值都在 0..1 范围内。',
        );
      }
      final x = rawPosition['x'];
      final y = rawPosition['y'];
      if (x is! num || y is! num) {
        return ToolResult.failure('position 必须同时提供数值 x 和 y。');
      }
      centerX = x.toDouble();
      centerY = y.toDouble();
      if (!centerX.isFinite ||
          !centerY.isFinite ||
          centerX < 0 ||
          centerX > 1 ||
          centerY < 0 ||
          centerY > 1) {
        return ToolResult.failure(
          'position 的 x、y 必须是有限数值且都在 0..1 范围内。',
        );
      }
    }

    final characterMatch = RegExp(r'^character_([1-6])$').firstMatch(target);
    try {
      final newVersion = await _accessor.writePrompt(
        target: target,
        content: content,
        append: append,
        centerX: centerX,
        centerY: centerY,
      );
      final targetLabel = _targetLabel(target);
      var positionResult = '';
      if (characterMatch != null) {
        if (centerX != null && centerY != null) {
          positionResult =
              '，位置已设为 (${centerX.toStringAsFixed(2)}, ${centerY.toStringAsFixed(2)})';
        } else {
          final index = int.parse(characterMatch.group(1)!) - 1;
          final existing = _accessor.characters[index];
          if (existing.centerX != null && existing.centerY != null) {
            positionResult =
                '，保留现有位置 (${existing.centerX!.toStringAsFixed(2)}, ${existing.centerY!.toStringAsFixed(2)})';
          } else {
            positionResult = '，未指定坐标，由绘图模型自动布局';
          }
        }
      }
      return ToolResult.success(
        '已${append ? "追加" : "替换"}到$targetLabel提示词框$positionResult（新版本 v$newVersion）。',
        displayText: '已${append ? "追加" : "替换"}到$targetLabel框$positionResult',
      );
    } on InpaintModeGuardError catch (e) {
      return ToolResult.failure(e.toString());
    } on ArgumentError catch (e) {
      return ToolResult.failure(e.message?.toString() ?? e.toString());
    }
  }

  static String _targetLabel(String target) {
    switch (target) {
      case 'positive':
        return '正向';
      case 'negative':
        return '负向';
      case 'inpaint_positive':
        return '局部重绘正向';
      case 'inpaint_negative':
        return '局部重绘负向';
      default:
        final m = RegExp(r'^character_(\d+)(_uc)?$').firstMatch(target);
        if (m != null) {
          final n = m.group(1);
          final isUc = m.group(2) == '_uc';
          return '角色$n${isUc ? "负向" : ""}提示词';
        }
        return target;
    }
  }
}
