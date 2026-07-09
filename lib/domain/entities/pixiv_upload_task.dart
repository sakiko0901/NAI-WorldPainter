import 'package:equatable/equatable.dart';

/// Pixiv 单次发布任务的状态
enum PixivUploadStatus {
  pending,    // 在队列里等待
  uploading,  // 正在调用 Pixiv API
  cooldown,   // 上传成功，等待冷却时间
  completed,  // 已成功（拿到 illustId）
  failed,     // 失败终止
  canceled,   // 用户取消
}

/// 单条 Pixiv 上传任务
class PixivUploadTask extends Equatable {
  final String id;
  final List<String> imagePaths;
  final String title;
  final String caption;
  final List<String> tags;
  final bool isR18;
  final bool allowTagEdit;
  final bool stripMetadata;
  final PixivUploadStatus status;
  final String? illustId;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? cooldownUntil;

  const PixivUploadTask({
    required this.id,
    required this.imagePaths,
    required this.title,
    required this.caption,
    required this.tags,
    required this.isR18,
    required this.allowTagEdit,
    required this.stripMetadata,
    this.status = PixivUploadStatus.pending,
    this.illustId,
    this.error,
    required this.createdAt,
    this.completedAt,
    this.cooldownUntil,
  });

  PixivUploadTask copyWith({
    String? title,
    String? caption,
    List<String>? tags,
    bool? isR18,
    bool? allowTagEdit,
    bool? stripMetadata,
    PixivUploadStatus? status,
    String? illustId,
    String? error,
    DateTime? completedAt,
    DateTime? cooldownUntil,
    bool clearError = false,
    bool clearCooldown = false,
  }) {
    return PixivUploadTask(
      id: id,
      imagePaths: imagePaths,
      title: title ?? this.title,
      caption: caption ?? this.caption,
      tags: tags ?? this.tags,
      isR18: isR18 ?? this.isR18,
      allowTagEdit: allowTagEdit ?? this.allowTagEdit,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      status: status ?? this.status,
      illustId: illustId ?? this.illustId,
      error: clearError ? null : (error ?? this.error),
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      cooldownUntil: clearCooldown ? null : (cooldownUntil ?? this.cooldownUntil),
    );
  }

  @override
  List<Object?> get props => [
        id,
        imagePaths,
        title,
        caption,
        tags,
        isR18,
        allowTagEdit,
        stripMetadata,
        status,
        illustId,
        error,
        createdAt,
        completedAt,
        cooldownUntil,
      ];
}
