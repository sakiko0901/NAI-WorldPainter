import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/core/utils/image_utils.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/vibe_encoding.dart';
import 'package:nai_huishi/domain/entities/tiled_img2img.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/vibe_encoding_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_drawer.dart';
import 'package:nai_huishi/presentation/widgets/fullscreen_image_preview.dart';
import 'package:nai_huishi/presentation/widgets/img2img_crop_dialog.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';
import 'package:nai_huishi/presentation/pages/inpaint_workspace_page.dart';
import 'package:nai_huishi/presentation/pages/advanced_parameters_page.dart';
import 'package:nai_huishi/presentation/widgets/generation_result_card.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/navigation/studio_page_route.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';
import 'package:nai_huishi/data/datasources/local/workspace_image_importer.dart';
import 'package:nai_huishi/presentation/widgets/character_position_editor.dart';

class GeneratePage extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  final VoidCallback? onOpenAssistant;

  const GeneratePage({super.key, this.onNavigate, this.onOpenAssistant});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  late final GenerationViewModel _vm;
  late final ImagePicker _imagePicker;
  late final ScrollController _scrollController;
  bool _isPreparingImg2Img = false;
  bool _isImportingWorkspaceImage = false;
  bool _isGenerationSettingsOpen = false;
  bool _hasOpenedInpaint = false;
  String? _img2ImgOriginalPath;

  @override
  void initState() {
    super.initState();
    _imagePicker = ImagePicker();
    _scrollController = ScrollController();
    _vm = sl<GenerationViewModel>();
    _knownResultCount = _vm.sessionResults.length;
    _wasGenerating = _vm.isGenerating;
    _hasOpenedInpaint = _vm.generationMode == GenerationMode.inpainting;

    // 我们不再直接使用 TextEditingController 以避免频繁重绘导致光标丢失。我们只传 initialValue 并在 onChanged 派发事件。
    // 但是 prompt 和 negative prompt 由于需要切换 Tab，如果频繁注销重建会导致光标和焦点丢失，所以这两个主输入框保留 controller
    _promptController.text = _vm.prompt;
    _negativeController.text = _vm.negativePrompt;
    _inpaintPromptController.text = _vm.inpaintPrompt;
    _inpaintNegativeController.text = _vm.inpaintNegativePrompt;
    _vm.addListener(_onVmChanged);
    InpaintWorkspaceCard.gestureActive.addListener(_onInpaintGestureChanged);
    _vm.loadModels();
    if (_vm.selectedResult != null || _vm.lastCompletedTask != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _revealLatestResult());
    }
  }

  late final TextEditingController _promptController = TextEditingController();
  late final TextEditingController _negativeController =
      TextEditingController();
  late final TextEditingController _inpaintPromptController =
      TextEditingController();
  late final TextEditingController _inpaintNegativeController =
      TextEditingController();
  late final FocusNode _promptFocusNode = FocusNode();
  late final FocusNode _negativeFocusNode = FocusNode();
  late final FocusNode _inpaintPromptFocusNode = FocusNode();
  late final FocusNode _inpaintNegativeFocusNode = FocusNode();
  final GlobalKey _resultSectionKey = GlobalKey();
  final GlobalKey _inpaintSectionKey = GlobalKey();

  /// 局部重绘工作区手势激活（绘制遮罩/拖框/移动图片）时锁定页面滚动。
  bool _inpaintWorkspaceLocked = false;
  bool _characterPositionLocked = false;
  int _knownResultCount = 0;
  String? _shownGenerationError;
  bool _wasGenerating = false;
  bool _userScrolledDuringGeneration = false;

  void _syncPromptControllers() {
    _promptController.text = _vm.prompt;
    _negativeController.text = _vm.negativePrompt;
    _inpaintPromptController.text = _vm.inpaintPrompt;
    _inpaintNegativeController.text = _vm.inpaintNegativePrompt;
  }

  void _closeChatDrawer() {
    setState(() => _isChatDrawerOpen = false);
    _syncPromptControllers();
  }

  void _onVmChanged() {
    _hasOpenedInpaint =
        _hasOpenedInpaint || _vm.generationMode == GenerationMode.inpainting;
    if (_promptController.text != _vm.prompt && !_promptFocusNode.hasFocus) {
      _promptController.text = _vm.prompt;
    }
    if (_negativeController.text != _vm.negativePrompt &&
        !_negativeFocusNode.hasFocus) {
      _negativeController.text = _vm.negativePrompt;
    }
    if (_inpaintPromptController.text != _vm.inpaintPrompt &&
        !_inpaintPromptFocusNode.hasFocus) {
      _inpaintPromptController.text = _vm.inpaintPrompt;
    }
    if (_inpaintNegativeController.text != _vm.inpaintNegativePrompt &&
        !_inpaintNegativeFocusNode.hasFocus) {
      _inpaintNegativeController.text = _vm.inpaintNegativePrompt;
    }

    final resultArrived = _vm.sessionResults.length > _knownResultCount;
    final generationStarted = _vm.isGenerating && !_wasGenerating;
    if (generationStarted) {
      _userScrolledDuringGeneration = false;
    }
    _knownResultCount = _vm.sessionResults.length;
    _wasGenerating = _vm.isGenerating;

    final error = _vm.errorMessage;
    if (error != null && error.isNotEmpty && error != _shownGenerationError) {
      _shownGenerationError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showFloatingToast(context, error);
      });
    } else if (error == null) {
      _shownGenerationError = null;
    }

    if (mounted) setState(() {});
    if (resultArrived && !_userScrolledDuringGeneration && !_isEditingPrompt) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _revealLatestResult(),
      );
    }
  }

  Future<void> _revealLatestResult() async {
    if (!mounted || _userScrolledDuringGeneration || _isEditingPrompt) return;
    final resultContext = _resultSectionKey.currentContext;
    if (resultContext == null) return;
    await Scrollable.ensureVisible(
      resultContext,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 1,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  /// 局部重绘工作区手势激活状态变化 → 刷新页面（滚动锁定随之切换）。
  void _onInpaintGestureChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _isEditingPrompt =>
      _promptFocusNode.hasFocus ||
      _negativeFocusNode.hasFocus ||
      _inpaintPromptFocusNode.hasFocus ||
      _inpaintNegativeFocusNode.hasFocus;

  bool get _isImageOperationBusy => _vm.isGenerating || _vm.isProcessingImage;
  bool _isChatDrawerOpen = false;

  void _showToast(String message) {
    showFloatingToast(context, message);
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    InpaintWorkspaceCard.gestureActive.removeListener(_onInpaintGestureChanged);
    _promptController.dispose();
    _negativeController.dispose();
    _promptFocusNode.dispose();
    _negativeFocusNode.dispose();
    _inpaintPromptController.dispose();
    _inpaintNegativeController.dispose();
    _inpaintPromptFocusNode.dispose();
    _inpaintNegativeFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final imagePath = (_vm.selectedResult ?? _vm.lastCompletedTask)?.imagePath;
    return Stack(
      children: [
        Positioned.fill(
          child: StudioBackground(
            image: imagePath != null && File(imagePath).existsSync()
                ? ResizeImage(FileImage(File(imagePath)), width: 600)
                : null,
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leadingWidth: 100,
            leading: widget.onNavigate == null
                ? null
                : TextButton.icon(
                    onPressed: () => widget.onNavigate!(0),
                    icon: const Icon(Icons.photo_library_outlined, size: 20),
                    label: const Text('画廊', style: TextStyle(fontSize: 14)),
                  ),
            actions: [
              IconButton(
                tooltip: '生成参数',
                icon: const Icon(Icons.tune),
                onPressed:
                    _isImageOperationBusy ? null : _openGenerationSettings,
              ),
            ],
          ),
          bottomNavigationBar: _isChatDrawerOpen || keyboardOpen
              ? null
              : _buildFloatingBottomBar(),
          body: LayoutBuilder(builder: (context, constraints) {
            final textExtra =
                ((MediaQuery.textScalerOf(context).scale(14) - 14) * 5)
                    .clamp(0.0, 72.0);
            final thumbnails = _vm.sessionResults.length > 1 ? 48.0 : 0.0;
            final workspaceHeight =
                (constraints.maxHeight - 210 - textExtra - thumbnails)
                    .clamp(220.0, 536.0)
                    .toDouble();
            final displayedImage = _vm.selectedResult ?? _vm.lastCompletedTask;
            final imageHeight = displayedImage != null &&
                    displayedImage.width > 0 &&
                    displayedImage.height > 0
                ? ((constraints.maxWidth - 48) *
                        displayedImage.height /
                        displayedImage.width)
                    .clamp(160.0, MediaQuery.sizeOf(context).height * 0.85)
                    .toDouble()
                : workspaceHeight;
            return Stack(
              children: [
                BackdropGroup(
                    child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (_vm.isGenerating &&
                        notification is UserScrollNotification &&
                        notification.direction != ScrollDirection.idle) {
                      _userScrolledDuringGeneration = true;
                    }
                    return false;
                  },
                  child: ListView(
                    key: const PageStorageKey('creation-scroll'),
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: _characterPositionLocked ||
                            (_vm.generationMode == GenerationMode.inpainting &&
                                (_inpaintWorkspaceLocked ||
                                    InpaintWorkspaceCard.gestureActive.value))
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    children: [
                      _buildModeSection(),
                      const SizedBox(height: 12),
                      if (_vm.generationMode != GenerationMode.inpainting) ...[
                        _buildResultSection(workspaceHeight: imageHeight),
                        const SizedBox(height: 12),
                        _buildPromptSection(),
                        const SizedBox(height: 12),
                        if (!_vm.isNonNovelAiProvider &&
                            _vm.supportsCharacterPrompts) ...[
                          _CharacterControlSection(
                            vm: _vm,
                            imageAspectRatio: _outputAspectRatio,
                            onPositionGestureChanged: (active) {
                              if (mounted &&
                                  active != _characterPositionLocked) {
                                setState(
                                    () => _characterPositionLocked = active);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!_vm.isNonNovelAiProvider &&
                            (_vm.supportsVibeReferences ||
                                _vm.supportsPreciseReferences))
                          _CharacterReferenceSection(
                              vm: _vm,
                              imagePicker: _imagePicker,
                              onShowMessage: _showToast),
                        if (_vm.isNonNovelAiProvider)
                          _buildGptReferenceImageSection(),
                      ],
                      if (_hasOpenedInpaint)
                        Offstage(
                          key: const ValueKey('retained-inpaint-workspace'),
                          offstage:
                              _vm.generationMode != GenerationMode.inpainting,
                          child: _buildInpaintingSection(),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                )),
                if (_isChatDrawerOpen)
                  ChatDrawer(
                      onClose: _closeChatDrawer,
                      parentResizesForKeyboard: true),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildModeSection() {
    // 统一重绘工作区目前只支持 NovelAI。
    final allowInpainting = !_vm.isNonNovelAiProvider;

    final glass = FrostedTheme.of(context);
    return FrostedSurface(
      radius: 12,
      padding: const EdgeInsets.all(4),
      child: allowInpainting
          ? CupertinoSlidingSegmentedControl<GenerationMode>(
              groupValue: _vm.generationMode,
              backgroundColor: Colors.transparent,
              thumbColor: glass.selection,
              children: {
                GenerationMode.textToImage: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 12,
                  ),
                  child: Text(
                    '文生图',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _vm.generationMode == GenerationMode.textToImage
                          ? glass.onSelection
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                GenerationMode.inpainting: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 12,
                  ),
                  child: Text(
                    '局部重绘',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _vm.generationMode == GenerationMode.inpainting
                          ? glass.onSelection
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              },
              onValueChanged: (value) {
                if (value != null && !_isImageOperationBusy) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _characterPositionLocked = false;
                  _vm.setGenerationMode(value);
                }
              },
            )
          : Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: glass.selection,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '文生图',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: glass.onSelection,
                ),
              ),
            ),
    );
  }

  Widget _buildInpaintingSection() {
    return KeyedSubtree(
      key: _inpaintSectionKey,
      child: const InpaintWorkspaceCard(),
    );
  }

  Widget _buildGptReferenceImageSection() {
    final images = _vm.gptImagePaths;
    final canAdd = images.length < 16;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.photo_on_rectangle,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: 8),
              Text(
                '参考图（可选，${images.length}/16）',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (images.isNotEmpty)
                TextButton.icon(
                  onPressed: _vm.clearGptImages,
                  icon: Icon(CupertinoIcons.xmark_circle, size: 14),
                  label: Text('清空', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            '上传参考图后走图像编辑接口，提示词描述修改意图。最多16张。',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.5),
              height: 1.5,
            ),
          ),
          if (images.isNotEmpty) ...[
            SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openImagePreview(
                          context,
                          imagePath: images[index],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(images[index]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _vm.removeGptImage(index),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          SizedBox(height: 12),
          if (canAdd)
            OutlinedButton.icon(
              onPressed: () async {
                final files = await _imagePicker.pickMultiImage();
                if (files.isEmpty) return;
                final added = _vm.addGptImages(files.map((file) => file.path));
                if (!mounted) return;
                if (added < files.length) {
                  _showToast('已添加 $added 张参考图，自动忽略重复图片并限制最多 16 张');
                }
              },
              icon: Icon(CupertinoIcons.plus, size: 16),
              label: Text('批量添加参考图'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickImg2ImgSource() async {
    if (_isPreparingImg2Img) return;
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    if (_vm.img2ImgMode == Img2ImgMode.tiled) {
      await _useImg2ImgOriginal(picked.path);
    } else {
      final applied = await _cropImg2ImgSource(picked.path);
      if (applied) _img2ImgOriginalPath = picked.path;
    }
  }

  Future<void> _useImg2ImgOriginal(String sourcePath) async {
    setState(() => _isPreparingImg2Img = true);
    try {
      final source = File(sourcePath);
      final decoded = img.decodeImage(await source.readAsBytes());
      if (decoded == null) {
        throw const FormatException('无法读取图片，请选择有效的 PNG 或 JPEG 图片');
      }
      if (!mounted) return;
      _vm.setImg2ImgSourceImagePath(sourcePath);
      _img2ImgOriginalPath = sourcePath;
    } catch (error) {
      if (mounted) _showToast('图片处理失败：$error');
    } finally {
      if (mounted) setState(() => _isPreparingImg2Img = false);
    }
  }

  Future<void> _recropImg2ImgSource() async {
    final path = _img2ImgOriginalPath ?? _vm.img2imgSourceImagePath;
    if (path == null || _isPreparingImg2Img) return;
    await _cropImg2ImgSource(path);
  }

  Future<bool> _cropImg2ImgSource(String sourcePath) async {
    var applied = false;
    setState(() => _isPreparingImg2Img = true);
    try {
      final source = File(sourcePath);
      final decoded = img.decodeImage(await source.readAsBytes());
      if (decoded == null) {
        throw const FormatException('无法读取图片，请选择有效的 PNG 或 JPEG 图片');
      }
      if (!mounted) return false;
      setState(() => _isPreparingImg2Img = false);
      final crop = await showDialog<Img2ImgCropResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Img2ImgCropDialog(
          imagePath: sourcePath,
          imageWidth: decoded.width,
          imageHeight: decoded.height,
          initialTargetIndex: switch (_vm.selectedResolution) {
            '832x1216' => 0,
            '1216x832' => 2,
            _ => 1,
          },
        ),
      );
      if (crop == null || !mounted) return false;
      setState(() => _isPreparingImg2Img = true);
      final path = await ImageUtils.cropImg2ImgSource(
        source,
        cropX: crop.x,
        cropY: crop.y,
        cropWidth: crop.width,
        cropHeight: crop.height,
        targetWidth: crop.targetWidth,
        targetHeight: crop.targetHeight,
      );
      if (!mounted) return false;
      _vm.setImg2ImgSourceImagePath(path);
      _showToast('源图已裁剪为 ${crop.targetWidth}×${crop.targetHeight}');
      applied = true;
    } catch (error) {
      if (mounted) _showToast('图片处理失败：$error');
    } finally {
      if (mounted) setState(() => _isPreparingImg2Img = false);
    }
    return applied;
  }

  Future<void> _openExpandedPromptEditor({
    required String title,
    required String initialValue,
    required Future<void> Function(String value) onSubmitted,
  }) async {
    final controller = TextEditingController(text: initialValue);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
            ),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(CupertinoIcons.xmark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: null,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: 15, height: 1.6),
                      decoration: const InputDecoration(
                        hintText: '请输入提示词...',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await onSubmitted(controller.text);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                      },
                      icon: const Icon(CupertinoIcons.check_mark),
                      label: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    controller.dispose();
  }

  Widget _buildPromptField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required ValueChanged<String> onChanged,
    required Color textColor,
    required String editorTitle,
    required Future<void> Function(String value) onExpandedSubmit,
  }) {
    return Stack(
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          minLines: 6,
          maxLines: 14,
          style: TextStyle(fontSize: 14, height: 1.5, color: textColor),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.55),
            ),
            fillColor: Colors.transparent,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.only(right: 48),
          ),
          onChanged: onChanged,
        ),
        Positioned(
          top: 0,
          right: -4,
          child: IconButton(
            onPressed: () => _openExpandedPromptEditor(
              title: editorTitle,
              initialValue: controller.text,
              onSubmitted: onExpandedSubmit,
            ),
            tooltip: '放大编辑',
            visualDensity: VisualDensity.standard,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(
              CupertinoIcons.arrow_up_left_arrow_down_right,
              size: 15,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPromptSection() {
    final theme = Theme.of(context);
    Widget editor({required bool negative}) => Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(negative ? '负向提示词' : '正向提示词',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _buildPromptField(
              controller: negative ? _negativeController : _promptController,
              focusNode: negative ? _negativeFocusNode : _promptFocusNode,
              hintText: negative ? '不希望出现的内容' : '描述画面、风格与构图',
              onChanged: negative ? _vm.updateNegativePrompt : _vm.updatePrompt,
              textColor: theme.colorScheme.onSurface,
              editorTitle: negative ? '负向提示词' : '正向提示词',
              onExpandedSubmit:
                  negative ? _vm.updateNegativePrompt : _vm.updatePrompt,
            ),
          ]),
        );
    return FrostedSurface(
      radius: 18,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        editor(negative: false),
        if (!_vm.isNonNovelAiProvider) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          editor(negative: true),
        ],
      ]),
    );
  }

  BoxDecoration _selectBoxDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFFD8E3F3),
        width: 1,
      ),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: const Color(0xFF94A3B8).withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
    );
  }

  Color _dropdownColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1C1C21)
        : Colors.white;
  }

  TextStyle _dropdownTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        );
  }

  Widget _dropdownShell({required Widget child}) {
    return Container(
      decoration: _selectBoxDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    );
  }

  Widget _buildImg2ImgSection() {
    final path = _vm.img2imgSourceImagePath;
    final file = path == null ? null : File(path);
    final hasImage = file?.existsSync() ?? false;
    final theme = Theme.of(context);
    final isTiled = _vm.img2ImgMode == Img2ImgMode.tiled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '图生图',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<Img2ImgMode>(
          segments: const [
            ButtonSegment(value: Img2ImgMode.normal, label: Text('普通图生图')),
            ButtonSegment(value: Img2ImgMode.tiled, label: Text('分块高清重绘')),
          ],
          selected: {_vm.img2ImgMode},
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? theme.colorScheme.primary.withValues(alpha: 0.18)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.selected)
                    ? theme.colorScheme.primary.withValues(alpha: 0.7)
                    : theme.colorScheme.outline.withValues(alpha: 0.28),
              ),
            ),
          ),
          onSelectionChanged: (selection) =>
              _vm.updateImg2ImgMode(selection.first),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.35,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: hasImage
              ? Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _openImagePreview(context, imagePath: path),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          file!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isTiled ? '已选择分块原图' : '已启用图生图',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isTiled ? '将整张原图分块高清重绘，约放大 1.6 倍' : '点击缩略图可查看大图',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            children: [
                              if (!isTiled)
                                TextButton(
                                  onPressed: _isPreparingImg2Img
                                      ? null
                                      : _recropImg2ImgSource,
                                  child: const Text('重新裁剪'),
                                ),
                              TextButton(
                                onPressed: _isPreparingImg2Img
                                    ? null
                                    : _pickImg2ImgSource,
                                child: const Text('替换'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _vm.setImg2ImgSourceImagePath(null),
                                child: const Text('移除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : OutlinedButton.icon(
                  onPressed: _isPreparingImg2Img ? null : _pickImg2ImgSource,
                  icon: _isPreparingImg2Img
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.photo_on_rectangle, size: 17),
                  label: Text(
                    _isPreparingImg2Img
                        ? '正在压缩图片…'
                        : (isTiled ? '上传分块原图' : '上传图生图源图'),
                  ),
                ),
        ),
        if (hasImage) ...[
          const SizedBox(height: 12),
          _PremiumSlider(
            label: '图生图强度',
            value: _vm.img2imgStrength,
            min: isTiled ? 0.1 : 0.01,
            max: isTiled ? 0.6 : 1.0,
            divisions: isTiled ? 50 : 99,
            onChanged: _vm.updateImg2ImgStrength,
          ),
          Text(
            isTiled ? '数值过高会导致块间不一致，建议 0.2–0.4' : '数值越高，生成结果越偏离原图。',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (isTiled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '自动按 640×640 分块、320 重叠，每块输出 1024×1024，处理耗时较长。',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildModelSection({bool initiallyExpanded = true}) {
    return _PremiumAccordion(
      title: '模型与基础参数',
      icon: CupertinoIcons.cube_box,
      initiallyExpanded: initiallyExpanded,
      children: [
        Text(
          'AI 模型',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 8),
        _dropdownShell(
          child: Builder(
            builder: (context) {
              final uniqueOptions = <String, ImageModelOption>{};
              for (final opt in _vm.imageModelOptions) {
                uniqueOptions.putIfAbsent(opt.modelId, () => opt);
              }
              final modelOptions = uniqueOptions.values.toList();
              final modelIds = modelOptions.map((opt) => opt.modelId).toList();
              final selectedModel = modelIds.contains(_vm.selectedModel)
                  ? _vm.selectedModel
                  : (modelIds.isNotEmpty ? modelIds.first : null);

              return DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(22),
                  value: selectedModel,
                  icon: Icon(CupertinoIcons.chevron_down, size: 16),
                  dropdownColor: _dropdownColor(context),
                  style: _dropdownTextStyle(context),
                  items: modelOptions.map((opt) {
                    String tag;
                    switch (opt.provider) {
                      case ImageProviderType.gpt:
                        tag = '[GPT] ';
                      case ImageProviderType.nanoBanana:
                        tag = '[Nano] ';
                      case ImageProviderType.novelAi:
                        tag = '';
                    }
                    final epName = (opt.endpointName != null &&
                            opt.endpointName!.isNotEmpty)
                        ? '[${opt.endpointName}] '
                        : '';
                    return DropdownMenuItem(
                      value: opt.modelId,
                      child: Text(
                        '$tag$epName${opt.displayName}',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) _vm.updateSelectedModel(v);
                  },
                ),
              );
            },
          ),
        ),
        SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              '图像尺寸',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              _vm.selectedResolution,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        GestureDetector(
          onLongPress: _showCustomResolutionDialog,
          child: _dropdownShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                borderRadius: BorderRadius.circular(22),
                value: _vm.availableResolutions.contains(_vm.selectedResolution)
                    ? _vm.selectedResolution
                    : null,
                hint: Text(
                  _vm.resolutionLabel(_vm.selectedResolution),
                  style: _dropdownTextStyle(context),
                ),
                icon: Icon(CupertinoIcons.chevron_down, size: 16),
                dropdownColor: _dropdownColor(context),
                style: _dropdownTextStyle(context),
                items: _vm.availableResolutions
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(_vm.resolutionLabel(r)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) _vm.updateSelectedResolution(v);
                },
              ),
            ),
          ),
        ),
        if (_vm.isNanoProvider) ...[
          SizedBox(height: 16),
          Row(
            children: [
              Text(
                '图片质量',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                _vm.selectedNanoImageSize,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _dropdownShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                borderRadius: BorderRadius.circular(22),
                value: _vm.selectedNanoImageSize,
                icon: Icon(CupertinoIcons.chevron_down, size: 16),
                dropdownColor: _dropdownColor(context),
                style: _dropdownTextStyle(context),
                items: ApiConstants.nanoImageSizes
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(_vm.nanoImageSizeLabel(s)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) _vm.updateSelectedNanoImageSize(v);
                },
              ),
            ),
          ),
        ],
        if ((_vm.is7877Endpoint ||
                _vm.isIkunEndpoint ||
                _vm.isOfficialEndpoint) &&
            _vm.generationMode == GenerationMode.textToImage) ...[
          SizedBox(height: 20),
          _buildImg2ImgSection(),
        ],
        if (_vm.is7877Endpoint)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _vm.isV5Model
                  ? 'V5 渠道固定单张生成，步数最多 28，画面总像素不超过 1024×1024；不支持 Vibe 与角色参考。'
                  : '7877 Images',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        SizedBox(height: 20),
        if (_vm.isOfficialEndpoint && _vm.officialCostPerImage != null) ...[
          Row(
            children: [
              Text(
                '预计消耗',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${_vm.officialCostPerImage! * _vm.batchCount} Anlas'
                '（${_vm.officialCostPerImage!}/张${_vm.batchCount > 1 ? ' × ${_vm.batchCount}' : ''}）',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
        ],
        Row(
          children: [
            Text(
              '批量生成',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '${_vm.batchCount} 张',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.black.withValues(alpha: 0.3),
            thumbColor: Colors.white,
            overlayColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: _vm.batchCount.toDouble().clamp(
                  1.0,
                  AppConstants.maxBatchCount.toDouble(),
                ),
            min: 1,
            max: AppConstants.maxBatchCount.toDouble(),
            divisions: AppConstants.maxBatchCount - 1,
            onChanged: _vm.isGenerating
                ? null
                : (v) => _vm.updateBatchCount(v.round()),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            '同一组提示词连续出图，每张间隔 1 秒',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  /// 工作台上方的官方超分按钮：点击弹出倍率选择（2x / 4x）。
  /// 结果区的"局部重绘"按钮：把图片与完整提示词快照导入工作区并跳转。
  Future<void> _importResultToInpaint(GenerationTask displayTask) async {
    final path = displayTask.imagePath;
    if (path == null || !File(path).existsSync()) {
      _showToast('当前图片不可用');
      return;
    }
    try {
      await _vm.importTaskToInpaint(displayTask);
    } catch (error) {
      if (mounted) {
        _showToast(error.toString().replaceFirst('Bad state: ', ''));
      }
      return;
    }
    if (!mounted) return;
    _showToast('已导入局部重绘');
    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    final context = _inpaintSectionKey.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
  }

  /// 长按尺寸框弹出的自定义画幅弹窗：输入宽×高，边长须为 64 的倍数。
  Future<void> _showCustomResolutionDialog() async {
    final widthController = TextEditingController();
    final heightController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void validateAndClose() {
              final w = int.tryParse(widthController.text.trim());
              final h = int.tryParse(heightController.text.trim());
              if (w == null || h == null) {
                setDialogState(() => errorText = '请输入有效的宽度和高度');
                return;
              }
              if (w < 64 || h < 64 || w > 1920 || h > 1920) {
                setDialogState(() => errorText = '边长需在 64 到 1920 之间');
                return;
              }
              if (w % 64 != 0 || h % 64 != 0) {
                setDialogState(() => errorText = '边长需为 64 的倍数');
                return;
              }
              Navigator.pop(ctx, true);
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                '自定义画幅',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '边长需为 64 的倍数（64–1920）',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widthController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '宽度',
                            hintText: '如 832',
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('×'),
                      ),
                      Expanded(
                        child: TextField(
                          controller: heightController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '高度',
                            hintText: '如 1216',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: validateAndClose,
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final width = int.tryParse(widthController.text.trim());
    final height = int.tryParse(heightController.text.trim());
    if (width == null || height == null) return;
    final error = await _vm.addCustomResolution(width, height);
    if (!mounted) return;
    if (error != null) {
      _showToast(error);
    } else {
      _showToast('已添加自定义画幅 ${width}×$height');
    }
  }

  /// 工作台的官方 Enhance 按钮：按提示词重绘放大（仅官方渠道显示）。
  Future<void> _showEnhanceSheet({required GenerationTask sourceTask}) async {
    final sourceId = sourceTask.taskId;
    double magnitude = 0.3;
    double noise = 0.1;
    bool useMax = false;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enhance · 重绘放大',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '使用原图提示词（为空时取当前草稿）与当前模型设置重绘，消耗 Anlas。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '重绘幅度 ${(magnitude * 100).round()}%'
                      '（低 ≈ 贴原图，高 ≈ 改得多）',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Slider(
                      value: magnitude,
                      min: 0.05,
                      max: 0.6,
                      divisions: 55,
                      onChanged: (v) => setSheetState(() => magnitude = v),
                    ),
                    Text(
                      '细节噪声 ${(noise * 100).round()}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Slider(
                      value: noise,
                      min: 0,
                      max: 0.5,
                      divisions: 50,
                      onChanged: (v) => setSheetState(() => noise = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Max 放大（V5）',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '服务端放大到 2× / 像素上限，Opus 也扣 Anlas',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      value: useMax,
                      onChanged: (v) => setSheetState(() => useMax = v),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('开始 Enhance'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;
    if ((_vm.selectedResult ?? _vm.lastCompletedTask)?.taskId != sourceId) {
      _showToast('当前结果已变化，请重新选择要增强的图片');
      return;
    }
    final ok = await _vm.enhanceWithOfficial(
      scale: useMax ? 1.0 : 1.5,
      strength: magnitude,
      noise: noise,
      max: useMax,
      sourceTask: sourceTask,
    );
    if (!mounted) return;
    if (ok) {
      _showToast('Enhance 完成，已加入本次结果');
    } else {
      _showToast(_vm.errorMessage ?? '无法开始 Enhance，请稍后重试');
    }
  }

  Future<void> _showOfficialUpscaleSheet({
    required GenerationTask sourceTask,
  }) async {
    final sourceId = sourceTask.taskId;
    final scale = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '官方超分',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '使用 NovelAI 官方接口放大当前图片，消耗 Anlas。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(CupertinoIcons.zoom_in),
                  title: const Text('2 倍放大'),
                  subtitle: const Text('单次超分，速度较快'),
                  onTap: () => Navigator.of(ctx).pop(2),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(CupertinoIcons.arrow_up_right_square),
                  title: const Text('4 倍放大'),
                  subtitle: const Text('连续两遍超分，耗时更长'),
                  onTap: () => Navigator.of(ctx).pop(4),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (scale == null || !mounted) return;
    if ((_vm.selectedResult ?? _vm.lastCompletedTask)?.taskId != sourceId) {
      _showToast('当前结果已变化，请重新选择要放大的图片');
      return;
    }
    final ok = await _vm.upscaleWithOfficial(scale, sourceTask: sourceTask);
    if (!mounted) return;
    if (ok) {
      _showToast('超分完成，已加入本次结果');
    } else {
      _showToast(_vm.errorMessage ?? '无法开始超分，请稍后重试');
    }
  }

  Widget _buildResultSection({required double workspaceHeight}) {
    final task = _vm.selectedResult ?? _vm.lastCompletedTask;
    final hasLocalImage =
        task?.imagePath != null && File(task!.imagePath!).existsSync();
    // 流式帧只在对应任务的占位卡上显示
    final taskStreamBytes =
        task == null ? null : _vm.streamPreviews[task.taskId];
    final taskStreamStep =
        task == null ? null : _vm.streamPreviewSteps[task.taskId];
    return GenerationResultCard(
      key: _resultSectionKey,
      workspaceHeight: workspaceHeight,
      task: task,
      results: _vm.sessionResults,
      generating: _vm.isGenerating,
      processing: _vm.isProcessingImage,
      processingSourceTaskId: _vm.imageProcessingSourceTaskId,
      processingLabel: _vm.imageProcessingLabel,
      processingStatus: _vm.imageProcessingStatus,
      error: _vm.errorMessage,
      streamPreviewBytes: taskStreamBytes,
      streamPreviewStep: taskStreamStep,
      effort: _vm.supportsEffortToggle && !_isImageOperationBusy
          ? _vm.effort
          : null,
      onEffortChanged: _vm.supportsEffortToggle && !_isImageOperationBusy
          ? (value) => _vm.updateEffort(value)
          : null,
      onImport: _isImageOperationBusy || _isImportingWorkspaceImage
          ? null
          : _importWorkspaceImage,
      onSelect: (result) => _vm.selectResult(result.taskId),
      onPreview: task == null
          ? null
          : () => _openImagePreview(
                context,
                imagePath: task.imagePath,
                imageUrl: task.imageUrl,
              ),
      onSave: task == null || _isImageOperationBusy
          ? null
          : () async {
              final path = await _vm.saveImage(task);
              if (mounted && path != null) _showToast('已保存到相册');
            },
      onInpaint:
          hasLocalImage && !_vm.isNonNovelAiProvider && !_isImageOperationBusy
              ? (result) {
                  _vm.selectResult(result.taskId);
                  return _importResultToInpaint(result);
                }
              : null,
      onUpscale: hasLocalImage && !_isImageOperationBusy
          ? (result) {
              _vm.selectResult(result.taskId);
              return _showOfficialUpscaleSheet(sourceTask: result);
            }
          : null,
      onEnhance:
          hasLocalImage && _vm.isOfficialEndpoint && !_isImageOperationBusy
              ? (result) {
                  _vm.selectResult(result.taskId);
                  return _showEnhanceSheet(sourceTask: result);
                }
              : null,
      onDelete: task == null || _isImageOperationBusy
          ? null
          : (result) => _confirmDeleteResult(result),
    );
  }

  /// 删除工作区当前图片前弹窗确认。
  Future<void> _confirmDeleteResult(GenerationTask result) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除图片'),
        content: const Text('从工作区移除当前显示的图片？历史记录不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_isImageOperationBusy) {
      _showToast('生成中请稍后删除');
      return;
    }
    _vm.removeSessionResult(result.taskId);
    _showToast('已从工作区移除');
  }

  double get _outputAspectRatio {
    final parts = _vm.selectedResolution.split(RegExp(r'[xX×]'));
    if (parts.length != 2) return 1;
    final width = double.tryParse(parts[0].trim());
    final height = double.tryParse(parts[1].trim());
    return width != null && height != null && width > 0 && height > 0
        ? width / height
        : 1;
  }

  Future<void> _importWorkspaceImage() async {
    if (_isImageOperationBusy || _isImportingWorkspaceImage) return;
    setState(() => _isImportingWorkspaceImage = true);
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final image = await compute(WorkspaceImageImporter.read, picked.path);
      if (!mounted) return;
      if (!_vm.displayImportedImage(image)) {
        _showToast('当前正在生成，请稍后导入图片');
      }
    } catch (_) {
      if (mounted) _showToast('图片导入失败，请选择有效图片');
    } finally {
      if (mounted) setState(() => _isImportingWorkspaceImage = false);
    }
  }

  void _openImagePreview(
    BuildContext context, {
    String? imagePath,
    String? imageUrl,
  }) {
    showFullscreenImagePreview(
      context,
      imagePath: imagePath,
      imageUrl: imageUrl,
    );
  }

  Widget _buildFloatingBottomBar() {
    final theme = Theme.of(context);
    final cancelling =
        _vm.isTiledImg2Img ? _vm.isTiledCancelling : _vm.isBatchCancelling;
    final progress = _vm.isTiledImg2Img
        ? '${_vm.tiledCompleted}/${_vm.tiledTotal}'
        : '${(_vm.batchCount - _vm.batchRemaining + 1).clamp(1, _vm.batchCount)}/${_vm.batchCount}';
    final model = _vm.currentModelOption?.displayName ?? '选择模型';
    final cost = _vm.officialCostPerImage;
    return FrostedSurface(
      radius: 0,
      child: SafeArea(
        top: false,
        bottom: widget.onNavigate == null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                key: const ValueKey('generate-primary-button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onPressed: cancelling ||
                        _isImportingWorkspaceImage ||
                        _vm.isProcessingImage
                    ? null
                    : () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        if (_vm.isGenerating) {
                          _vm.isTiledImg2Img
                              ? _vm.cancelTiledImg2Img()
                              : _vm.cancelBatch();
                        } else {
                          _vm.generate();
                        }
                      },
                icon: _vm.isProcessingImage
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _vm.isGenerating
                            ? Icons.stop_circle_outlined
                            : Icons.auto_awesome,
                      ),
                label: Text(
                  _isImportingWorkspaceImage
                      ? '正在导入图片…'
                      : _vm.isProcessingImage
                          ? '正在处理图片…'
                          : _vm.isGenerating
                              ? (cancelling
                                  ? '正在停止后续任务…'
                                  : '停止后续生成 · $progress')
                              : (_vm.batchCount > 1
                                  ? '生成 ${_vm.batchCount} 张图片'
                                  : '生成图片'),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$model · ${_vm.selectedResolution} · ${_vm.batchCount} 张'
                '${cost == null ? ' · 预计 —' : ' · 预计 ${cost * _vm.batchCount} Anlas'}',
                key: const ValueKey('generation-summary'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  height: 1.35,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openGenerationSettings() async {
    if (_isGenerationSettingsOpen || _isImageOperationBusy) return;
    _isGenerationSettingsOpen = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await Navigator.of(context).push<void>(studioPageRoute<void>(
        context: context,
        name: '/generation-settings',
        builder: (_) => _GenerationSettingsPage(
          vm: _vm,
          buildModelSection: () => _buildModelSection(),
        ),
      ));
    } finally {
      _isGenerationSettingsOpen = false;
    }
  }
}

class _GenerationSettingsPage extends StatelessWidget {
  final GenerationViewModel vm;
  final Widget Function() buildModelSection;

  const _GenerationSettingsPage({
    required this.vm,
    required this.buildModelSection,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('generation-settings-page'),
      appBar: AppBar(
        title: const Text('生成参数'),
        flexibleSpace:
            const FrostedSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const StudioBackground(),
          SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: vm,
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyedSubtree(
                      key: const ValueKey('generation_settings_model'),
                      child: buildModelSection(),
                    ),
                    const SizedBox(height: 12),
                    FrostedSurface(
                      blur: 0,
                      child: ListTile(
                        leading: const Icon(Icons.tune),
                        title: const Text('采样与高级参数'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AdvancedParametersPage(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumAccordion extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _PremiumAccordion({
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<_PremiumAccordion> createState() => _PremiumAccordionState();
}

class _PremiumAccordionState extends State<_PremiumAccordion>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 240),
      vsync: this,
    );
    _iconTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    if (_isExpanded) _controller.value = 1.0;
  }

  void _toggle() {
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      blur: 0,
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }
}

class _PremiumSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _PremiumSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.black.withValues(alpha: 0.3),
            thumbColor: Colors.white,
            overlayColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            showValueIndicator: ShowValueIndicator.never, // 移除丑陋气泡
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _CharacterReferenceSection extends StatelessWidget {
  final GenerationViewModel vm;
  final ImagePicker imagePicker;
  final ValueChanged<String> onShowMessage;

  const _CharacterReferenceSection({
    required this.vm,
    required this.imagePicker,
    required this.onShowMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final vibeActive =
        !vm.supportsPreciseReferences || vm.referenceMode == ReferenceMode.vibe;
    return _PremiumAccordion(
      title: '参考图像',
      icon: CupertinoIcons.photo_on_rectangle,
      initiallyExpanded: false,
      children: [
        _ReferenceModePanel(
          title: '氛围转移（${vm.vibeReferences.length}/${vm.maxVibeReferences}）',
          icon: CupertinoIcons.photo,
          isActive: vibeActive,
          onTap: () => _switchMode(context, ReferenceMode.vibe),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: vm.vibeReferences.length >= vm.maxVibeReferences
                    ? null
                    : () => _showVibeSourceMenu(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(
                    color: colors.primary.withValues(alpha: 0.45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(CupertinoIcons.add, size: 17),
                label: Text(
                  vm.vibeReferences.isEmpty ? '添加氛围参考图' : '继续添加氛围参考图',
                ),
              ),
              for (final entry in vm.vibeReferences.asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ReferenceImageCard(
                    image: entry.value,
                    onReplace: () =>
                        _showVibeSourceMenu(context, replaceIndex: entry.key),
                    onUpdate: (reference) =>
                        vm.updateVibeReference(entry.key, reference),
                    onDelete: () => vm.removeVibeReference(entry.key),
                  ),
                ),
            ],
          ),
        ),
        if (vm.supportsPreciseReferences) ...[
          const SizedBox(height: 12),
          _ReferenceModePanel(
            title: '精密参照图像',
            icon: CupertinoIcons.person_crop_rectangle,
            isActive: !vibeActive,
            onTap: () => _switchMode(context, ReferenceMode.precise),
            trailing: IconButton.outlined(
              tooltip: '导入参照图像',
              onPressed: () => _addPreciseReference(),
              style: IconButton.styleFrom(
                foregroundColor: colors.primary,
                side: BorderSide(color: colors.primary.withValues(alpha: 0.45)),
                visualDensity: VisualDensity.standard,
              ),
              icon: const Icon(CupertinoIcons.add, size: 19),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in vm.preciseReferences.asMap().entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _PreciseReferenceCard(
                      image: entry.value,
                      onReplace: () => _replacePreciseReference(entry.key),
                      onUpdate: (reference) =>
                          vm.updatePreciseReference(entry.key, reference),
                      onDelete: () => vm.removePreciseReference(entry.key),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _switchMode(BuildContext context, ReferenceMode target) async {
    if (vm.referenceMode == target) return;
    final hasCurrentReferences = vm.referenceMode == ReferenceMode.vibe
        ? vm.vibeReferences.isNotEmpty
        : vm.preciseReferences.isNotEmpty;
    if (hasCurrentReferences) {
      final targetLabel = target == ReferenceMode.vibe ? '氛围转移' : '精密参照图像';
      final currentLabel =
          vm.referenceMode == ReferenceMode.vibe ? '氛围参考图' : '精密参照图像';
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text('切换为$targetLabel？'),
          content: Text('切换后会清空当前的$currentLabel。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('清空并切换'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await vm.switchReferenceMode(target);
    if (!context.mounted) return;
    onShowMessage(target == ReferenceMode.vibe ? '已切换为氛围转移' : '已切换为精密参照图像');
  }

  Future<void> _showVibeSourceMenu(
    BuildContext context, {
    int? replaceIndex,
  }) async {
    final source = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择氛围来源'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'image'),
            child: const Text('选择本地图片'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'library'),
            child: const Text('从 Vibe 编码库选择'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (source == 'image') {
      await _pickVibes(replaceIndex: replaceIndex);
    } else if (source == 'library' && context.mounted) {
      final selected = await _showVibeLibraryPicker(
        context,
        maxSelection: replaceIndex == null
            ? vm.maxVibeReferences - vm.vibeReferences.length
            : 1,
      );
      if (selected.isEmpty) return;
      if (replaceIndex == null) {
        final added = await vm.addVibeEncodings(selected);
        if (context.mounted && added < selected.length) {
          onShowMessage('已添加 $added 条氛围参考，最多 ${vm.maxVibeReferences} 条');
        }
      } else {
        await vm.replaceVibeReferenceWithEncoding(replaceIndex, selected.first);
      }
    }
  }

  Future<List<VibeEncoding>> _showVibeLibraryPicker(
    BuildContext context, {
    required int maxSelection,
  }) async {
    final viewModel = sl<VibeEncodingViewModel>();
    await viewModel.load();
    if (!context.mounted) return const [];
    return await showModalBottomSheet<List<VibeEncoding>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _VibeEncodingMultiPicker(
            encodings: viewModel.encodings,
            maxSelection: maxSelection,
          ),
        ) ??
        const [];
  }

  Future<void> _pickVibes({int? replaceIndex}) async {
    if (replaceIndex == null) {
      final images = await imagePicker.pickMultiImage();
      final added = await vm.addVibeReferences(
        images.map((image) => image.path),
      );
      if (images.isNotEmpty && added < images.length) {
        onShowMessage('已添加 $added 条氛围参考，最多 ${vm.maxVibeReferences} 条');
      }
      return;
    }
    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await vm.replaceVibeReferenceWithPath(replaceIndex, image.path);
    }
  }

  Future<void> _addPreciseReference() async {
    final picked = await imagePicker.pickImage(source: ImageSource.gallery);
    if (picked != null) await vm.addPreciseReference(picked.path);
  }

  Future<void> _replacePreciseReference(int index) async {
    final picked = await imagePicker.pickImage(source: ImageSource.gallery);
    if (picked != null) await vm.replacePreciseReference(index, picked.path);
  }
}

class _VibeEncodingMultiPicker extends StatefulWidget {
  final List<VibeEncoding> encodings;
  final int maxSelection;

  const _VibeEncodingMultiPicker({
    required this.encodings,
    required this.maxSelection,
  });

  @override
  State<_VibeEncodingMultiPicker> createState() =>
      _VibeEncodingMultiPickerState();
}

class _VibeEncodingMultiPickerState extends State<_VibeEncodingMultiPicker> {
  final Set<int> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '选择 Vibe 编码',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_selectedIds.length}/${widget.maxSelection}',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.encodings.isEmpty
                  ? const Center(child: Text('暂无已保存的氛围编码'))
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: widget.encodings.length,
                      itemBuilder: (context, index) {
                        final encoding = widget.encodings[index];
                        final id = encoding.id;
                        final selected =
                            id != null && _selectedIds.contains(id);
                        return InkWell(
                          onTap: id == null
                              ? null
                              : () => setState(() {
                                    if (selected) {
                                      _selectedIds.remove(id);
                                    } else if (_selectedIds.length <
                                        widget.maxSelection) {
                                      _selectedIds.add(id);
                                    }
                                  }),
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(encoding.thumbnailPath),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(CupertinoIcons.photo),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    encoding.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              if (selected)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Icon(
                                    CupertinoIcons.check_mark_circled_solid,
                                    color: theme.colorScheme.primary,
                                    size: 24,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            widget.encodings
                                .where(
                                  (encoding) =>
                                      encoding.id != null &&
                                      _selectedIds.contains(encoding.id),
                                )
                                .toList(),
                          ),
                  child: Text('添加 ${_selectedIds.length} 条编码'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceModePanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final Widget child;
  final Widget? trailing;

  const _ReferenceModePanel({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = isActive ? colors.primary : colors.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isActive ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isActive
                ? colors.primary.withValues(alpha: 0.1)
                : colors.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 19, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  const Spacer(),
                  if (isActive && trailing != null) trailing!,
                  if (!isActive)
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                ],
              ),
              if (isActive) ...[const SizedBox(height: 12), child],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceImageCard extends StatelessWidget {
  final CharacterReferenceImage image;
  final VoidCallback onReplace;
  final ValueChanged<CharacterReferenceImage> onUpdate;
  final VoidCallback onDelete;

  const _ReferenceImageCard({
    required this.image,
    required this.onReplace,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewPath = image.thumbnailPath?.isNotEmpty == true
        ? image.thumbnailPath!
        : image.path;
    final sourceLabel = image.vibeLibraryId != null ? '已保存编码' : '首次生成时自动编码并保存';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () =>
                    showFullscreenImagePreview(context, imagePath: previewPath),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(previewPath),
                    width: 82,
                    height: 108,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 82,
                      height: 108,
                      color: theme.colorScheme.errorContainer,
                      child: Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    if (image.title?.isNotEmpty == true)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          image.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        sourceLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: onReplace,
                          icon: const Icon(
                            CupertinoIcons.arrow_2_circlepath,
                            size: 15,
                          ),
                          label: const Text('替换'),
                        ),
                        IconButton(
                          tooltip: '删除参考图',
                          onPressed: onDelete,
                          icon: const Icon(CupertinoIcons.trash, size: 17),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ReferenceSlider(
            label: '参考强度',
            value: image.strength,
            onChanged: (value) => onUpdate(image.copyWith(strength: value)),
          ),
          _ReferenceSlider(
            label: '信息提取',
            value: image.informationExtracted,
            onChanged: (value) =>
                onUpdate(image.copyWith(informationExtracted: value)),
          ),
        ],
      ),
    );
  }
}

class _PreciseReferenceCard extends StatelessWidget {
  final PreciseReferenceImage image;
  final VoidCallback onReplace;
  final ValueChanged<PreciseReferenceImage> onUpdate;
  final VoidCallback onDelete;

  const _PreciseReferenceCard({
    required this.image,
    required this.onReplace,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.outlined(
                tooltip: '删除参照图像',
                onPressed: onDelete,
                style: IconButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.45),
                  ),
                ),
                icon: const Icon(CupertinoIcons.trash, size: 17),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('有效', style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(width: 6),
                    Icon(CupertinoIcons.check_mark, size: 16),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: image.referenceType,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(
                      value: 'character&style',
                      child: Text('角色与画风'),
                    ),
                    DropdownMenuItem(value: 'character', child: Text('角色')),
                    DropdownMenuItem(value: 'style', child: Text('画风')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onUpdate(image.copyWith(referenceType: value));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () =>
                    showFullscreenImagePreview(context, imagePath: image.path),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(image.path),
                    width: 106,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 106,
                      height: 160,
                      color: theme.colorScheme.errorContainer,
                      child: Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: TextButton.icon(
                    onPressed: onReplace,
                    icon: const Icon(
                      CupertinoIcons.arrow_2_circlepath,
                      size: 15,
                    ),
                    label: const Text('替换图片'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PreciseReferenceSlider(
            label: '强度',
            value: image.strength,
            onChanged: (value) => onUpdate(image.copyWith(strength: value)),
          ),
        ],
      ),
    );
  }
}

class _PreciseReferenceSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _PreciseReferenceSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$label: ${value.toStringAsFixed(1)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Slider(
            value: value.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            onChanged: onChanged,
          ),
        ],
      );
}

class _ReferenceSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _ReferenceSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
}

class _CharacterControlSection extends StatefulWidget {
  final GenerationViewModel vm;
  final double imageAspectRatio;
  final ValueChanged<bool> onPositionGestureChanged;

  const _CharacterControlSection(
      {required this.vm,
      required this.imageAspectRatio,
      required this.onPositionGestureChanged});

  @override
  State<_CharacterControlSection> createState() =>
      _CharacterControlSectionState();
}

class _CharacterControlSectionState extends State<_CharacterControlSection>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _expanded = false;
  late AnimationController _controller;
  late Animation<double> _iconTurns;
  final Set<int> _expandedCards = {};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 240),
      vsync: this,
    );
    _iconTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  void _toggle() {
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final characters = widget.vm.characters;
    final enabledCount = characters.where((c) => c.enabled).length;
    if (!widget.vm.supportsCharacterPrompts) return const SizedBox.shrink();

    return FrostedSurface(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.person_3,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '角色提示词',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (enabledCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$enabledCount',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: '添加角色',
                    onPressed: characters.length >= 6
                        ? null
                        : () {
                            widget.vm.addCharacter();
                            final index = widget.vm.characters.length - 1;
                            widget.vm.setCharacterPositionAuto(index);
                            setState(() {
                              _expandedCards.add(index);
                              _expanded = true;
                            });
                            _controller.duration =
                                MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 240);
                            _controller.forward();
                          },
                    icon: const Icon(Icons.add),
                  ),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (characters.isNotEmpty)
                    for (final entry in characters.asMap().entries)
                      _CharacterCard(
                        key: ValueKey('character_${entry.key}'),
                        index: entry.key,
                        character: entry.value,
                        freePosition: widget.vm.isV5Model,
                        imageAspectRatio: widget.imageAspectRatio,
                        onPositionGestureChanged:
                            widget.onPositionGestureChanged,
                        expanded: _expandedCards.contains(entry.key),
                        onToggleExpanded: () {
                          setState(() {
                            if (_expandedCards.contains(entry.key)) {
                              _expandedCards.remove(entry.key);
                            } else {
                              _expandedCards.add(entry.key);
                            }
                          });
                        },
                        onMoveUp: entry.key == 0
                            ? null
                            : () => widget.vm.moveCharacterUp(entry.key),
                        onMoveDown: entry.key == characters.length - 1
                            ? null
                            : () => widget.vm.moveCharacterDown(entry.key),
                        onToggleEnabled: () =>
                            widget.vm.toggleCharacterEnabled(entry.key),
                        onDelete: () {
                          widget.vm.removeCharacter(entry.key);
                          setState(() => _expandedCards.remove(entry.key));
                        },
                        onChanged: (character) =>
                            widget.vm.updateCharacter(entry.key, character),
                        onAutoPosition: () =>
                            widget.vm.setCharacterPositionAuto(entry.key),
                        onGridPosition: (row, col) => widget.vm
                            .setCharacterGridPosition(entry.key, row, col),
                        onAddReference: (path) =>
                            widget.vm.addCharacterReference(entry.key, path),
                        onReplaceReference: (referenceIndex, path) =>
                            widget.vm.replaceCharacterReference(
                          entry.key,
                          referenceIndex,
                          path,
                        ),
                        onUpdateReference: (referenceIndex, reference) =>
                            widget.vm.updateCharacterReference(
                          entry.key,
                          referenceIndex,
                          reference,
                        ),
                        onRemoveReference: (referenceIndex) =>
                            widget.vm.removeCharacterReference(
                          entry.key,
                          referenceIndex,
                        ),
                        onOpenExpandedEditor: ({
                          required title,
                          required initialValue,
                          required onSubmitted,
                        }) =>
                            showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (ctx) {
                            final controller = TextEditingController(
                              text: initialValue,
                            );
                            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
                            final theme = Theme.of(ctx);
                            return Padding(
                              padding: EdgeInsets.only(bottom: bottom),
                              child: Container(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.sizeOf(ctx).height * 0.88,
                                ),
                                margin: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  12,
                                  18,
                                  18,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.08),
                                  ),
                                ),
                                child: SafeArea(
                                  top: false,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.35),
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    theme.colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                            icon: const Icon(
                                              CupertinoIcons.xmark,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: controller,
                                          autofocus: true,
                                          minLines: null,
                                          maxLines: null,
                                          expands: true,
                                          textAlignVertical:
                                              TextAlignVertical.top,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            height: 1.6,
                                          ),
                                          decoration: const InputDecoration(
                                            hintText: '请输入提示词...',
                                            alignLabelWithHint: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: () async {
                                            await onSubmitted(
                                              controller.text,
                                            );
                                            if (!ctx.mounted) return;
                                            Navigator.of(ctx).pop();
                                          },
                                          icon: const Icon(
                                            CupertinoIcons.check_mark,
                                          ),
                                          label: const Text('完成'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }
}

class _CharacterCard extends StatefulWidget {
  final int index;
  final CharacterSpec character;
  final bool freePosition;
  final double imageAspectRatio;
  final ValueChanged<bool> onPositionGestureChanged;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onToggleEnabled;
  final VoidCallback onDelete;
  final ValueChanged<CharacterSpec> onChanged;
  final VoidCallback onAutoPosition;
  final void Function(int row, int col) onGridPosition;
  final Future<void> Function(String path) onAddReference;
  final Future<void> Function(int referenceIndex, String path)
      onReplaceReference;
  final Future<void> Function(
    int referenceIndex,
    CharacterReferenceImage reference,
  ) onUpdateReference;
  final Future<void> Function(int referenceIndex) onRemoveReference;
  final Future<void> Function({
    required String title,
    required String initialValue,
    required Future<void> Function(String value) onSubmitted,
  }) onOpenExpandedEditor;

  const _CharacterCard({
    super.key,
    required this.index,
    required this.character,
    required this.freePosition,
    required this.imageAspectRatio,
    required this.onPositionGestureChanged,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleEnabled,
    required this.onDelete,
    required this.onChanged,
    required this.onAutoPosition,
    required this.onGridPosition,
    required this.onAddReference,
    required this.onReplaceReference,
    required this.onUpdateReference,
    required this.onRemoveReference,
    required this.onOpenExpandedEditor,
  });

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  int _tabIndex = 0;
  late final TextEditingController _promptController;
  late final TextEditingController _ucController;
  late final FocusNode _promptFocusNode;
  late final FocusNode _ucFocusNode;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.character.prompt);
    _ucController = TextEditingController(text: widget.character.uc ?? '');
    _promptFocusNode = FocusNode();
    _ucFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _CharacterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_promptFocusNode.hasFocus &&
        _promptController.text != widget.character.prompt) {
      _promptController.text = widget.character.prompt;
    }
    final uc = widget.character.uc ?? '';
    if (!_ucFocusNode.hasFocus && _ucController.text != uc) {
      _ucController.text = uc;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _ucController.dispose();
    _promptFocusNode.dispose();
    _ucFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickAndAddReference() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) await widget.onAddReference(image.path);
  }

  Future<void> _pickAndReplaceReference(int referenceIndex) async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) {
      await widget.onReplaceReference(referenceIndex, image.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positionLabel = widget.freePosition &&
            widget.character.centerX != null
        ? '${(widget.character.centerX! * 100).round()}%, ${(widget.character.centerY! * 100).round()}%'
        : _positionLabel(widget.character.centerX, widget.character.centerY);
    final bool isEnabled = widget.character.enabled;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.3)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isEnabled
              ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEnabled
                            ? theme.colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.25),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '角色${widget.index + 1}',
                            style: TextStyle(
                              color: isEnabled
                                  ? theme.colorScheme.onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            positionLabel == null
                                ? 'AI决定位置'
                                : '位置 $positionLabel',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onToggleEnabled,
                      icon: Icon(
                        isEnabled
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        size: 18,
                      ),
                      color: isEnabled
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.35),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onDelete,
                      icon: Icon(CupertinoIcons.trash, size: 18),
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.35),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                    Icon(
                      widget.expanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.35),
                    ),
                    SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              children: [
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _buildTabButton(0, '正向'),
                      SizedBox(width: 8),
                      _buildTabButton(1, '负向'),
                      SizedBox(width: 8),
                      _buildTabButton(2, '位置'),
                      SizedBox(width: 8),
                      _buildTabButton(3, '参考'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: _CharacterTabContent(
                    index: _tabIndex,
                    children: [
                      Stack(
                        children: [
                          TextField(
                            controller: _promptController,
                            focusNode: _promptFocusNode,
                            minLines: 10,
                            maxLines: 18,
                            style: TextStyle(fontSize: 13, height: 1.5),
                            decoration: InputDecoration(
                              hintText: '描述该角色的外观...',
                              hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.55),
                              ),
                              filled: true,
                              fillColor: FrostedTheme.of(context).field,
                              contentPadding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                36,
                                12,
                              ),
                            ),
                            onChanged: (value) => widget.onChanged(
                              widget.character.copyWith(prompt: value),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: -4,
                            child: IconButton(
                              onPressed: () => widget.onOpenExpandedEditor(
                                title: '编辑角色 ${widget.index + 1} Prompt',
                                initialValue: _promptController.text,
                                onSubmitted: (value) async {
                                  widget.onChanged(
                                    widget.character.copyWith(prompt: value),
                                  );
                                },
                              ),
                              tooltip: '放大编辑',
                              visualDensity: VisualDensity.standard,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              icon: Icon(
                                CupertinoIcons.arrow_up_left_arrow_down_right,
                                size: 15,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Stack(
                        children: [
                          TextField(
                            controller: _ucController,
                            focusNode: _ucFocusNode,
                            minLines: 10,
                            maxLines: 18,
                            style: TextStyle(fontSize: 13, height: 1.5),
                            decoration: InputDecoration(
                              hintText: '描述该角色不需要的特征...',
                              hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.55),
                              ),
                              filled: true,
                              fillColor: FrostedTheme.of(context).field,
                              contentPadding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                36,
                                12,
                              ),
                            ),
                            onChanged: (value) => widget.onChanged(
                              widget.character.copyWith(
                                uc: value.isEmpty ? null : value,
                                clearUc: value.isEmpty,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: -4,
                            child: IconButton(
                              onPressed: () => widget.onOpenExpandedEditor(
                                title: '编辑角色 ${widget.index + 1} UContent',
                                initialValue: _ucController.text,
                                onSubmitted: (value) async {
                                  widget.onChanged(
                                    widget.character.copyWith(
                                      uc: value.isEmpty ? null : value,
                                      clearUc: value.isEmpty,
                                    ),
                                  );
                                },
                              ),
                              tooltip: '放大编辑',
                              visualDensity: VisualDensity.standard,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              icon: Icon(
                                CupertinoIcons.arrow_up_left_arrow_down_right,
                                size: 15,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ],
                      ),
                      CharacterPositionEditor(
                        continuous: widget.freePosition,
                        roleNumber: widget.index + 1,
                        aspectRatio: widget.imageAspectRatio,
                        x: widget.character.centerX,
                        y: widget.character.centerY,
                        onAuto: widget.onAutoPosition,
                        onGestureActive: widget.onPositionGestureChanged,
                        onChanged: (point) {
                          if (widget.freePosition) {
                            widget.onChanged(widget.character.copyWith(
                                centerX: point.dx, centerY: point.dy));
                          } else {
                            widget.onGridPosition(
                                ((point.dy - .1) / .2).round().clamp(0, 4),
                                ((point.dx - .1) / .2).round().clamp(0, 4));
                          }
                        },
                      ),
                      _CharacterReferencePanel(
                        references: widget.character.referenceImages,
                        onAdd: _pickAndAddReference,
                        onReplace: _pickAndReplaceReference,
                        onUpdate: widget.onUpdateReference,
                        onDelete: widget.onRemoveReference,
                      ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.black.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '排序',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: widget.onMoveUp,
                        icon: Icon(CupertinoIcons.arrow_up, size: 16),
                        color: widget.onMoveUp == null
                            ? Colors.white12
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onMoveDown,
                        icon: Icon(CupertinoIcons.arrow_down, size: 16),
                        color: widget.onMoveDown == null
                            ? Colors.white12
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            crossFadeState: widget.expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isSelected = _tabIndex == index;
    return Expanded(
      child: Semantics(
          button: true,
          selected: isSelected,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _tabIndex = index);
            },
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? FrostedTheme.of(context).selection
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? FrostedTheme.of(context).onSelection
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )),
    );
  }
}

class _CharacterTabContent extends StatelessWidget {
  final int index;
  final List<Widget> children;
  const _CharacterTabContent({required this.index, required this.children});

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++)
            Offstage(
              offstage: i != index,
              child: TickerMode(enabled: i == index, child: children[i]),
            ),
        ]),
      );
}

class _CharacterReferencePanel extends StatelessWidget {
  final List<CharacterReferenceImage> references;
  final Future<void> Function() onAdd;
  final Future<void> Function(int referenceIndex) onReplace;
  final Future<void> Function(
    int referenceIndex,
    CharacterReferenceImage reference,
  ) onUpdate;
  final Future<void> Function(int referenceIndex) onDelete;

  const _CharacterReferencePanel({
    required this.references,
    required this.onAdd,
    required this.onReplace,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '角色精细参考会在兼容渠道中作为全局角色参考提交。',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(CupertinoIcons.add, size: 17),
          label: Text(references.isEmpty ? '添加角色精细参考' : '继续添加角色精细参考'),
        ),
        for (final entry in references.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _CharacterReferenceCard(
              image: entry.value,
              onReplace: () => onReplace(entry.key),
              onUpdate: (reference) => onUpdate(entry.key, reference),
              onDelete: () => onDelete(entry.key),
            ),
          ),
      ],
    );
  }
}

class _CharacterReferenceCard extends StatelessWidget {
  final CharacterReferenceImage image;
  final VoidCallback onReplace;
  final ValueChanged<CharacterReferenceImage> onUpdate;
  final VoidCallback onDelete;

  const _CharacterReferenceCard({
    required this.image,
    required this.onReplace,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () =>
                    showFullscreenImagePreview(context, imagePath: image.path),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(image.path),
                    width: 82,
                    height: 108,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 82,
                      height: 108,
                      color: theme.colorScheme.errorContainer,
                      child: Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '角色精细参考',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: onReplace,
                      icon: const Icon(
                        CupertinoIcons.arrow_2_circlepath,
                        size: 15,
                      ),
                      label: const Text('替换图片'),
                    ),
                    IconButton(
                      tooltip: '删除角色精细参考',
                      onPressed: onDelete,
                      icon: const Icon(CupertinoIcons.trash, size: 17),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ReferenceSlider(
            label: '参考强度',
            value: image.strength,
            onChanged: (value) => onUpdate(image.copyWith(strength: value)),
          ),
          _ReferenceSlider(
            label: '信息提取',
            value: image.informationExtracted,
            onChanged: (value) =>
                onUpdate(image.copyWith(informationExtracted: value)),
          ),
        ],
      ),
    );
  }
}

String _gridLabel(int row, int col) =>
    '${String.fromCharCode(65 + col)}${row + 1}';

String? _positionLabel(double? x, double? y) {
  final index = _positionIndex(x, y);
  return index == null ? null : _gridLabel(index.$1, index.$2);
}

(int, int)? _positionIndex(double? x, double? y) {
  if (x == null || y == null) return null;
  final col = ((x - 0.1) / 0.2).round().clamp(0, 4);
  final row = ((y - 0.1) / 0.2).round().clamp(0, 4);
  return (row, col);
}
