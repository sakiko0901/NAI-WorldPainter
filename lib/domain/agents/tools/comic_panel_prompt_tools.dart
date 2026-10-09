import 'package:nai_huishi/domain/agents/agent_tool.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';

class ComicPanelPromptTools {
  ComicPanel _panel;
  final Future<void> Function(ComicPanel panel) _save;

  ComicPanelPromptTools({
    required ComicPanel panel,
    required Future<void> Function(ComicPanel panel) save,
  })  : _panel = panel,
        _save = save;

  AgentTool get read => _ReadComicPanelPromptTool(() => _panel);
  AgentTool get write => _WriteComicPanelPromptTool(
        panel: () => _panel,
        save: (panel) async {
          _panel = panel;
          await _save(panel);
        },
      );
}

class _ReadComicPanelPromptTool extends AgentTool {
  final ComicPanel Function() _panel;

  _ReadComicPanelPromptTool(this._panel);

  @override
  String get name => 'read_comic_panel_prompt';

  @override
  String get description => '读取当前漫画分镜的标题、已有英文 Tag 提示词和台词。只能读取当前已打开分镜。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final panel = _panel();
    final dialogue = panel.dialogues
        .where((item) => item.text.trim().isNotEmpty)
        .map((item) => item.text.trim())
        .join(' / ');
    return ToolResult.success(
      '分镜标题：${panel.title}\n当前 Tag：${panel.prompt}\n台词：$dialogue',
      displayText: '已读取当前分镜 Tag',
    );
  }
}

class _WriteComicPanelPromptTool extends AgentTool {
  final ComicPanel Function() _panel;
  final Future<void> Function(ComicPanel panel) _save;

  _WriteComicPanelPromptTool({
    required ComicPanel Function() panel,
    required Future<void> Function(ComicPanel panel) save,
  })  : _panel = panel,
        _save = save;

  @override
  String get name => 'write_comic_panel_prompt';

  @override
  String get description =>
      '将英文 NovelAI/Danbooru Tag 写入当前漫画分镜。mode=append 追加并去掉完全重复 tag；mode=replace 覆盖当前分镜 Tag。只能修改当前已打开分镜。';

  @override
  bool get requireConfirmation => true;

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description': '要写入当前分镜的英文 NovelAI/Danbooru Tag',
          },
          'mode': {
            'type': 'string',
            'enum': ['append', 'replace'],
            'description': 'append 追加，replace 覆盖当前分镜提示词',
          },
        },
        'required': ['content'],
      };

  @override
  Future<ToolResult> call(Map<String, dynamic> arguments) async {
    final content = (arguments['content'] as String?)?.trim() ?? '';
    final mode = (arguments['mode'] as String?)?.trim() ?? 'append';
    if (content.isEmpty) return ToolResult.failure('content 不能为空');
    if (mode != 'append' && mode != 'replace') {
      return ToolResult.failure('mode 只能是 append 或 replace');
    }
    final panel = _panel();
    final prompt =
        mode == 'replace' ? content : _appendTags(panel.prompt, content);
    await _save(panel.copyWith(prompt: prompt));
    return ToolResult.success(
      '已${mode == 'append' ? '追加' : '覆盖'}当前分镜 Tag：$prompt',
      displayText: '已${mode == 'append' ? '追加' : '覆盖'}当前分镜 Tag',
    );
  }

  String _appendTags(String existing, String next) {
    final tags = <String>[];
    final seen = <String>{};
    for (final source in [existing, next]) {
      for (final raw in source.split(',')) {
        final tag = raw.trim();
        if (tag.isEmpty) continue;
        final key = tag.toLowerCase();
        if (seen.add(key)) tags.add(tag);
      }
    }
    return tags.join(', ');
  }
}
