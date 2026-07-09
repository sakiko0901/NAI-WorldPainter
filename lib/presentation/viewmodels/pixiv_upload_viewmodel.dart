import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:nai_huishi/core/services/pixiv_upload_queue_service.dart';
import 'package:nai_huishi/data/datasources/local/nai_metadata_parser.dart';
import 'package:nai_huishi/data/datasources/local/pixiv_title_generator.dart';
import 'package:nai_huishi/domain/entities/pixiv_settings.dart';
import 'package:nai_huishi/domain/entities/pixiv_upload_task.dart';
import 'package:nai_huishi/domain/usecases/manage_pixiv_settings.dart';
import 'package:nai_huishi/domain/usecases/suggest_pixiv_tags.dart';
import 'package:nai_huishi/domain/usecases/upload_to_pixiv.dart';

/// 单次发布页 ViewModel
class PixivUploadViewModel extends ChangeNotifier {
  final UploadToPixivUseCase _upload;
  final SuggestPixivTagsUseCase _suggest;
  final ManagePixivSettingsUseCase _settingsUC;
  final PixivTitleGenerator _titleGen;
  final PixivUploadQueueService _queue;

  PixivUploadViewModel({
    required UploadToPixivUseCase upload,
    required SuggestPixivTagsUseCase suggest,
    required ManagePixivSettingsUseCase settingsUC,
    required PixivTitleGenerator titleGen,
    required PixivUploadQueueService queue,
  })  : _upload = upload,
        _suggest = suggest,
        _settingsUC = settingsUC,
        _titleGen = titleGen,
        _queue = queue;

  // ── 状态 ──
  PixivSettings? settings;
  final List<String> imagePaths = [];
  final TextEditingController titleCtrl = TextEditingController();
  final TextEditingController captionCtrl = TextEditingController();
  final List<String> tags = [];
  bool isR18 = false;
  bool allowTagEdit = true;
  bool stripMetadata = false;

  // 上传状态
  bool isUploading = false;
  String? error;
  String? lastIllustId;

  // 元数据解析
  String? detectedPrompt;
  bool hasNaiMetadata = false;

  Future<void> init() async {
    settings = await _settingsUC.load();
    isR18 = settings!.r18Default;
    allowTagEdit = settings!.allowTagEdit;
    stripMetadata = settings!.stripMetadata;
    notifyListeners();
  }

  bool get canUpload =>
      !isUploading &&
      imagePaths.isNotEmpty &&
      titleCtrl.text.trim().isNotEmpty &&
      (settings?.hasCredentials ?? false);

  // ── 图片管理 ──
  Future<void> addImages(List<String> paths) async {
    for (final p in paths) {
      if (!imagePaths.contains(p)) imagePaths.add(p);
      if (imagePaths.length >= 4) break;
    }
    // 解析最后一张的元数据
    if (imagePaths.isNotEmpty) {
      await _parseLastImageMetadata();
    }
    notifyListeners();
  }

  void removeImage(int index) {
    if (index < 0 || index >= imagePaths.length) return;
    imagePaths.removeAt(index);
    if (imagePaths.isEmpty) {
      detectedPrompt = null;
      hasNaiMetadata = false;
    }
    notifyListeners();
  }

  Future<void> _parseLastImageMetadata() async {
    final r = await NaiMetadataParser.parse(imagePaths.last);
    if (r != null) {
      detectedPrompt = r.general.map((e) => e.tag).join(', ');
      hasNaiMetadata = true;
    } else {
      detectedPrompt = null;
      hasNaiMetadata = false;
    }
  }

  // ── 自动填充 ──
  Future<void> autoFillTitle() async {
    if (detectedPrompt == null || detectedPrompt!.isEmpty) return;
    final title = await _titleGen.generate(
      prompt: detectedPrompt!,
      isR18: isR18,
    );
    titleCtrl.text = title;
    notifyListeners();
  }

  void autoFillCaption() {
    final s = settings;
    if (s == null) return;
    final buf = StringBuffer();
    if (s.captionPrefix.isNotEmpty) buf.write(s.captionPrefix);

    final prompt = detectedPrompt;
    if (prompt != null && prompt.isNotEmpty) {
      // 抽样
      final cleaned = prompt
          .replaceAll(RegExp(r'[\[\]\{\}]'), '')
          .split(RegExp(r',\s*'))
          .where((t) => t.trim().isNotEmpty)
          .toList();
      List<String> sampled;
      if (s.repTagsPercent >= 1.0) {
        sampled = cleaned;
      } else {
        final n = (cleaned.length * s.repTagsPercent).round();
        cleaned.shuffle(Random());
        sampled = cleaned.take(n).toList();
        final drop = cleaned.length - n;
        if (drop > 0 && s.repTagsFill.isNotEmpty) {
          sampled.addAll(List.filled(drop, s.repTagsFill));
        }
      }
      if (buf.isNotEmpty) buf.write('\n----------\n');
      buf.write(sampled.join(', '));
    }
    captionCtrl.text = buf.toString();
    notifyListeners();
  }

  Future<void> fetchSuggestedTags() async {
    if (imagePaths.isEmpty) return;
    error = null;
    notifyListeners();
    try {
      final suggested = await _suggest.call(imagePaths.last);
      final defaults = settings?.defaultTags ?? const [];
      final merged = <String>{...defaults, ...suggested}.toList();
      // 最多 10 个
      if (merged.length > 10) {
        merged.shuffle(Random());
        tags
          ..clear()
          ..addAll(merged.take(10));
      } else {
        tags
          ..clear()
          ..addAll(merged);
      }
    } catch (e) {
      error = '获取推荐标签失败: $e';
    }
    notifyListeners();
  }

  void addTag(String tag) {
    final t = tag.trim();
    if (t.isEmpty || tags.contains(t)) return;
    tags.add(t);
    notifyListeners();
  }

  void removeTag(String tag) {
    tags.remove(tag);
    notifyListeners();
  }

  void setR18(bool v) {
    isR18 = v;
    notifyListeners();
  }

  void setAllowTagEdit(bool v) {
    allowTagEdit = v;
    notifyListeners();
  }

  void setStripMetadata(bool v) {
    stripMetadata = v;
    notifyListeners();
  }

  // ── 提交 ──
  PixivUploadTask _buildTask() {
    return PixivUploadTask(
      id: const Uuid().v4(),
      imagePaths: List<String>.from(imagePaths),
      title: titleCtrl.text.trim(),
      caption: captionCtrl.text,
      tags: List<String>.from(tags),
      isR18: isR18,
      allowTagEdit: allowTagEdit,
      stripMetadata: stripMetadata,
      createdAt: DateTime.now(),
    );
  }

  /// 立即上传（前台 await，UI 显示 loading）
  Future<String?> uploadNow() async {
    if (!canUpload) return null;
    isUploading = true;
    error = null;
    lastIllustId = null;
    notifyListeners();
    try {
      final task = _buildTask();
      final result = await _upload.call(task);
      lastIllustId = result.illustId;
      isUploading = false;
      notifyListeners();
      return result.illustId;
    } catch (e) {
      error = e.toString();
      isUploading = false;
      notifyListeners();
      return null;
    }
  }

  /// 加入队列（后台依次执行）
  void enqueue() {
    if (imagePaths.isEmpty || titleCtrl.text.trim().isEmpty) return;
    _queue.enqueue(_buildTask());
  }

  void reset() {
    imagePaths.clear();
    titleCtrl.clear();
    captionCtrl.clear();
    tags.clear();
    detectedPrompt = null;
    hasNaiMetadata = false;
    error = null;
    lastIllustId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    captionCtrl.dispose();
    super.dispose();
  }
}
