import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/image_tag_result.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/image_tag_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/vibe_encoding_viewmodel.dart';
import 'package:nai_huishi/presentation/pages/image_metadata_editor_page.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

/// 图片解析页面：导入图片 → 选择分析方式（NAI 元数据 / WD-Tagger）→ 选择标签 → 复制 / 导入文生图
class ImageTagPage extends StatefulWidget {
  final VoidCallback? onNavigateToGenerate;

  const ImageTagPage({super.key, this.onNavigateToGenerate});

  @override
  State<ImageTagPage> createState() => _ImageTagPageState();
}

class _ImageTagPageState extends State<ImageTagPage> {
  static const _metadataLabels = <String, String>{
    'seed': '随机种子',
    'steps': '迭代步数',
    'step': '迭代步数',
    'sampler': '采样器',
    'scale': '引导比例',
    'cfg_rescale': '引导重缩放',
    'noise_schedule': '噪声调度',
    'width': '图像宽度',
    'height': '图像高度',
    'Source': '来源',
    'Software': '生成软件',
  };

  late final ImageTagViewModel _vm;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _vm = sl<ImageTagViewModel>();
    _vm.addListener(_onChanged);
    _vm.loadCache();
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickImage() async {
    if (_vm.isAnalyzing) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _vm.setImagePath(picked.path);
  }

  Future<void> _analyze() async {
    if (_vm.imagePath == null) {
      showFloatingToast(context, '请先选择图片', icon: CupertinoIcons.photo);
      return;
    }
    await _vm.analyze();
    if (!mounted) return;
    if (_vm.error != null) {
      showFloatingToast(context, _vm.error!,
          icon: CupertinoIcons.exclamationmark_circle);
    } else if (_vm.result != null) {
      showFloatingToast(context, '分析完成', icon: CupertinoIcons.checkmark_circle);
    }
  }

  Future<void> _copySelected() async {
    final r = _vm.result;
    if (r == null) return;
    final positive = r.selectedGeneralTags;
    final negative = r.selectedNegativeTags;
    final parts = <String>[];
    if (positive.isNotEmpty) parts.add('【正向】\n$positive');
    if (negative.isNotEmpty) parts.add('【负向】\n$negative');
    for (final entry in (r.characters ?? const <CharacterSpec>[]).indexed) {
      final character = entry.$2;
      if (character.prompt.trim().isNotEmpty) {
        parts.add('【角色 ${entry.$1 + 1}】\n${character.prompt.trim()}');
      }
      if (character.uc?.trim().isNotEmpty == true) {
        parts.add('【角色 ${entry.$1 + 1} 负向】\n${character.uc!.trim()}');
      }
    }
    if (parts.isEmpty) {
      showFloatingToast(context, '没有可复制的标签',
          icon: CupertinoIcons.exclamationmark_circle);
      return;
    }
    await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    if (!mounted) return;
    showFloatingToast(context, '已复制全部解析内容', icon: CupertinoIcons.doc_on_doc);
  }

  Future<void> _copyTags(String text, {String label = '已复制'}) async {
    if (text.isEmpty) {
      showFloatingToast(context, '没有选中的标签',
          icon: CupertinoIcons.exclamationmark_circle);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showFloatingToast(context, label, icon: CupertinoIcons.doc_on_doc);
  }

  Future<void> _importToGenerate() async {
    final r = _vm.result;
    if (r == null) return;
    final positive = r.selectedGeneralTags;
    final negative = r.selectedNegativeTags;

    // 角色 prompt 收集（只针对 NAI 元数据有 characters 时）
    List<String>? charPrompts;
    List<String>? charNegatives;
    if (r.characters != null && r.characters!.isNotEmpty) {
      charPrompts = r.characters!.map((c) => c.prompt).toList();
      charNegatives = r.characters!.map((c) => c.uc ?? '').toList();
    }

    final genVm = sl<GenerationViewModel>();
    await genVm.replaceAll(
      positive: positive,
      negative: negative,
      characterPrompts: charPrompts,
      characterNegatives: charNegatives,
    );

    if (!mounted) return;
    showFloatingToast(context, '已导入文生图', icon: CupertinoIcons.checkmark_circle);
    widget.onNavigateToGenerate?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('图片解析'),
        actions: [
          IconButton(
            tooltip: '修改图片标签',
            icon: const Icon(CupertinoIcons.pencil_circle, size: 22),
            onPressed: () => Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => const ImageMetadataEditorPage(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildPreview(isDark),
            const SizedBox(height: 18),
            _buildModeSelector(isDark),
            if (_vm.mode == TagAnalysisMode.wdTagger) ...[
              const SizedBox(height: 14),
              _buildWdSettings(isDark),
            ],
            const SizedBox(height: 18),
            _buildAnalyzeButton(),
            if (_vm.error != null) ...[
              const SizedBox(height: 12),
              _buildError(isDark),
            ],
            if (_vm.result != null) ...[
              const SizedBox(height: 22),
              _buildResultSection(isDark),
            ],
          ],
        ),
      ),
    );
  }

  // ── 图片预览 ──
  Widget _buildPreview(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final imagePath = _vm.imagePath;
    Widget child;
    if (imagePath == null || !File(imagePath).existsSync()) {
      child = _buildPlaceholder(isDark);
    } else {
      child = Image.file(File(imagePath), fit: BoxFit.contain);
    }
    final preview = GestureDetector(
      onTap: _pickImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(color: cardColor, child: child),
      ),
    );
    if (imagePath == null || !File(imagePath).existsSync()) {
      return AspectRatio(aspectRatio: 1, child: preview);
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final previewHeight = (screenHeight * 0.58).clamp(380.0, 640.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      height: previewHeight,
      child: preview,
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    final hint = isDark ? Colors.white54 : Colors.black38;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(CupertinoIcons.photo_on_rectangle, size: 48, color: hint),
        const SizedBox(height: 12),
        Text('点击选择图片', style: TextStyle(color: hint, fontSize: 15)),
      ],
    );
  }

  // ── 分析方式 ──
  Widget _buildModeSelector(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text('分析方式',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: cardColor,
            child: Column(
              children: [
                _modeTile(TagAnalysisMode.naiMetadata, 'NAI 原图分析',
                    '读取 NovelAI 隐藏元数据，原始 prompt / 角色 / 参数', isDark),
                Divider(
                    height: 1,
                    thickness: 0.6,
                    indent: 16,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.07)),
                _modeTile(TagAnalysisMode.wdTagger, 'WD-Tagger 识别',
                    '本地 AI 模型识别图片标签，无需网络', isDark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeTile(TagAnalysisMode m, String title, String desc, bool isDark) {
    final selected = _vm.mode == m;
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: _vm.isAnalyzing ? null : () => _vm.setMode(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 22,
              color: selected
                  ? primary
                  : (isDark ? Colors.white30 : Colors.black26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WD-Tagger 设置 ──
  Widget _buildWdSettings(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 在线模型说明
          Row(
            children: [
              Icon(CupertinoIcons.cloud, size: 16, color: primary),
              const SizedBox(width: 8),
              const Text('SwinV2 v3（在线分析）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '通过 Hugging Face Space 在线推理，无需下载模型',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('通用阈值',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(_vm.generalThreshold.toStringAsFixed(2),
                  style: TextStyle(
                      fontSize: 13,
                      color: primary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: _vm.generalThreshold,
            min: 0.1,
            max: 0.9,
            divisions: 80,
            onChanged:
                _vm.isAnalyzing ? null : (v) => _vm.setGeneralThreshold(v),
          ),
          Row(
            children: [
              const Text('角色阈值',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(_vm.characterThreshold.toStringAsFixed(2),
                  style: TextStyle(
                      fontSize: 13,
                      color: primary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: _vm.characterThreshold,
            min: 0.1,
            max: 0.99,
            divisions: 89,
            onChanged:
                _vm.isAnalyzing ? null : (v) => _vm.setCharacterThreshold(v),
          ),
        ],
      ),
    );
  }

  // ── 开始分析按钮 ──
  Widget _buildAnalyzeButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: _vm.isAnalyzing ? null : _analyze,
        child: _vm.isAnalyzing
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('分析中...',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              )
            : const Text('开始分析',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(_vm.error ?? '',
          style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
    );
  }

  // ── 分析结果区 ──
  Widget _buildResultSection(bool isDark) {
    final r = _vm.result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.metadata != null && r.metadata!.isNotEmpty) ...[
          _buildMetadataCard(r, isDark),
          const SizedBox(height: 16),
        ],
        // 翻译按钮
        if (_vm.tagTranslations.isEmpty && !_vm.isTranslating) ...[
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _vm.translateTags,
              icon: const Icon(CupertinoIcons.globe, size: 18),
              label: const Text('翻译标签为中文',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_vm.isTranslating) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('正在翻译标签...', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (r.general.isNotEmpty) ...[
          _buildTagsBlock(
            title: '正向标签',
            tags: r.general,
            isNegative: false,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
        ],
        if (r.negativeEntries.isNotEmpty) ...[
          _buildTagsBlock(
            title: '负向标签',
            tags: r.negativeEntries,
            isNegative: true,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
        ],
        if (r.character.isNotEmpty) ...[
          _buildCharacterTagsBlock(r.character, isDark),
          const SizedBox(height: 16),
        ],
        if (r.characters != null && r.characters!.isNotEmpty) ...[
          _buildMultiCharacterBlock(r, isDark),
          const SizedBox(height: 16),
        ],
        if (r.vibeEncodings.isNotEmpty) ...[
          _buildVibeEncodingsBlock(r.vibeEncodings, isDark),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 6),
        _buildBottomActions(),
      ],
    );
  }

  // ── 元数据卡片（NAI 模式才有）──
  Widget _buildMetadataCard(ImageTagResult r, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final entries = r.metadata!.entries.toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.info_circle,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              const Text('生成参数',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(_metadataLabels[e.key] ?? e.key,
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: SelectableText(
                      e.value.toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 标签块（正向 / 负向 通用渲染）──
  Widget _buildTagsBlock({
    required String title,
    required List<TagEntry> tags,
    required bool isNegative,
    required bool isDark,
  }) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final selectedCount = tags.where((t) => t.selected).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('$selectedCount / ${tags.length}',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54)),
              const Spacer(),
              _miniBtn(
                  icon: CupertinoIcons.checkmark_alt_circle,
                  label: '全选',
                  onTap: () => isNegative
                      ? _vm.selectAllNegative()
                      : _vm.selectAllGeneral()),
              const SizedBox(width: 6),
              _miniBtn(
                  icon: CupertinoIcons.circle,
                  label: '反选',
                  onTap: () =>
                      isNegative ? _vm.invertNegative() : _vm.invertGeneral()),
              const SizedBox(width: 6),
              _miniBtn(
                  icon: CupertinoIcons.doc_on_doc,
                  label: '复制',
                  onTap: () => _copyTags(tags
                      .where((t) => t.selected)
                      .map((t) => t.tag)
                      .join(', '))),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int i = 0; i < tags.length; i++)
                _tagChip(
                  entry: tags[i],
                  onTap: () => _vm.toggleTag(
                    _vm.result!.source,
                    generalIndex: isNegative ? null : i,
                    negativeIndex: isNegative ? i : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 角色标签（WD-Tagger 识别出来的角色）──
  Widget _buildCharacterTagsBlock(List<TagEntry> tags, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final selectedCount = tags.where((t) => t.selected).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('角色识别',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('$selectedCount / ${tags.length}',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54)),
              const Spacer(),
              _miniBtn(
                  icon: CupertinoIcons.doc_on_doc,
                  label: '复制',
                  onTap: () => _copyTags(tags
                      .where((t) => t.selected)
                      .map((t) => t.tag)
                      .join(', '))),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int i = 0; i < tags.length; i++)
                _tagChip(
                  entry: tags[i],
                  onTap: () =>
                      _vm.toggleTag(_vm.result!.source, characterIndex: i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 多角色块（NAI 元数据多角色）──
  Widget _buildMultiCharacterBlock(ImageTagResult r, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.person_2,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              const Text('多角色',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${r.characters!.length} 个',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54)),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < r.characters!.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildCharacterRow(
                i + 1, r.characters![i].prompt, r.characters![i].uc, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildCharacterRow(int idx, String prompt, String? uc, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('角色 $idx',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            _miniBtn(
                icon: CupertinoIcons.doc_on_doc,
                label: '复制',
                onTap: () => _copyTags(prompt)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(prompt,
              style: const TextStyle(fontSize: 12, height: 1.4)),
        ),
        if (uc != null && uc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text('负向',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              _miniBtn(
                  icon: CupertinoIcons.doc_on_doc,
                  label: '复制',
                  onTap: () => _copyTags(uc)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(uc,
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ],
      ],
    );
  }

  Future<void> _saveVibeEncodings(List<String> encodings) async {
    final sourceImagePath = _vm.imagePath;
    if (sourceImagePath == null || sourceImagePath.isEmpty) {
      showFloatingToast(context, '请先选择图片', icon: CupertinoIcons.photo);
      return;
    }
    if (encodings.isEmpty) return;
    final fileName = sourceImagePath.replaceAll('\\', '/').split('/').last;
    final dot = fileName.lastIndexOf('.');
    final titlePrefix = dot > 0 ? fileName.substring(0, dot) : fileName;
    try {
      final viewModel = sl<VibeEncodingViewModel>();
      final created = await viewModel.createManyFromEncodings(
        titlePrefix: titlePrefix,
        sourceImagePath: sourceImagePath,
        encodedVibes: encodings,
      );
      if (!mounted) return;
      showFloatingToast(
        context,
        '已保存 ${created.length} 个氛围编码',
        icon: CupertinoIcons.checkmark_circle_fill,
      );
    } catch (e) {
      if (!mounted) return;
      showFloatingToast(
        context,
        '保存氛围编码失败：$e',
        icon: CupertinoIcons.exclamationmark_circle,
      );
    }
  }

  Widget _buildVibeEncodingsBlock(List<String> encodings, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.waveform,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              const Text('氛围编码',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${encodings.length} 个',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54)),
              const Spacer(),
              _miniBtn(
                icon: CupertinoIcons.archivebox,
                label: '保存',
                onTap: () => _saveVibeEncodings(encodings),
              ),
              const SizedBox(width: 6),
              _miniBtn(
                icon: CupertinoIcons.doc_on_doc,
                label: '全部复制',
                onTap: () => _copyTags(
                  encodings.join('\n'),
                  label: '已复制氛围编码',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '这是可复用的 Vibe 编码数据，不是普通提示词；使用相同编码可跳过重复编码。',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          for (final entry in encodings.indexed) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('编码 ${entry.$1 + 1}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                _miniBtn(
                  icon: CupertinoIcons.doc_on_doc,
                  label: '复制',
                  onTap: () => _copyTags(
                    entry.$2,
                    label: '已复制氛围编码 ${entry.$1 + 1}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              entry.$2.length > 96 ? '${entry.$2.substring(0, 96)}…' : entry.$2,
              maxLines: 3,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 底部按钮区 ──
  Widget _buildBottomActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: _importToGenerate,
            icon: const Icon(CupertinoIcons.paintbrush, size: 20),
            label: const Text('导入到文生图',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _copySelected,
            icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
            label: const Text('复制全部选中',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // ── 通用小按钮 ──
  Widget _miniBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13, color: isDark ? Colors.white70 : Colors.black54),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── 单个 tag chip ──
  Widget _tagChip({required TagEntry entry, required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final selected = entry.selected;
    final showConfidence = entry.confidence < 1.0;
    final translation = _vm.tagTranslations[entry.tag];
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.18)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            width: selected ? 1 : 0.5,
            color: selected
                ? primary.withValues(alpha: 0.7)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.10)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(CupertinoIcons.checkmark_circle_fill,
                    size: 12, color: primary),
              ),
            Text(
              entry.tag,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? primary
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            if (translation != null) ...[
              const SizedBox(width: 4),
              Text(
                translation,
                style: TextStyle(
                  fontSize: 11,
                  color: selected
                      ? primary.withValues(alpha: 0.65)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.45)
                          : Colors.black45),
                ),
              ),
            ],
            if (showConfidence) ...[
              const SizedBox(width: 4),
              Text(
                '${(entry.confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  color: selected
                      ? primary.withValues(alpha: 0.7)
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
