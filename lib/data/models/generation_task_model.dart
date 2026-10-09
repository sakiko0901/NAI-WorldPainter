import 'dart:convert';
import 'package:nai_huishi/domain/entities/generation_task.dart';

class GenerationTaskModel {
  final int? id;
  final String taskId;
  final String model;
  final String? endpointId;
  final String? protocol;
  final String prompt;
  final String? negativePrompt;
  final int width;
  final int height;
  final String? size;
  final double scale;
  final double cfgRescale;
  final String sampler;
  final String noiseSchedule;
  final int steps;
  final bool useCoords;
  final int? seed;
  final List<CharacterSpec>? characters;
  final List<CharacterReferenceImage> vibeReferences;
  final List<PreciseReferenceImage> preciseReferences;
  final GenerationMode mode;
  final String? sourceImagePath;
  final String? maskImagePath;
  final double? inpaintStrength;
  final String? img2imgSourceImagePath;
  final double? img2imgStrength;
  final String? responseFormat;
  final ImageProviderType providerType;
  final bool disabledOriginalImage;
  final bool colorCorrect;
  final String status;
  final String? imagePath;
  final String? imageUrl;
  final String? errorMessage;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime? completedAt;

  const GenerationTaskModel({
    this.id,
    required this.taskId,
    required this.model,
    this.endpointId,
    this.protocol,
    required this.prompt,
    this.negativePrompt,
    required this.width,
    required this.height,
    this.size,
    required this.scale,
    required this.cfgRescale,
    required this.sampler,
    required this.noiseSchedule,
    this.steps = 28,
    this.useCoords = true,
    this.seed,
    this.characters,
    this.vibeReferences = const [],
    this.preciseReferences = const [],
    this.mode = GenerationMode.textToImage,
    this.sourceImagePath,
    this.maskImagePath,
    this.inpaintStrength,
    this.img2imgSourceImagePath,
    this.img2imgStrength,
    this.responseFormat,
    this.providerType = ImageProviderType.novelAi,
    this.disabledOriginalImage = false,
    this.colorCorrect = true,
    required this.status,
    this.imagePath,
    this.imageUrl,
    this.errorMessage,
    this.isFavorite = false,
    required this.createdAt,
    this.completedAt,
  });

  /// 从数据库行转 Model
  factory GenerationTaskModel.fromDb(Map<String, dynamic> row) {
    List<CharacterSpec>? chars;
    if (row['characters'] != null && (row['characters'] as String).isNotEmpty) {
      final list = jsonDecode(row['characters'] as String) as List;
      chars = list
          .map((e) => CharacterSpec.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final vibeReferencesRaw = row['vibe_references'] as String?;
    final vibeReferences =
        vibeReferencesRaw == null || vibeReferencesRaw.isEmpty
            ? const <CharacterReferenceImage>[]
            : (jsonDecode(vibeReferencesRaw) as List)
                .map((e) => CharacterReferenceImage.fromJson(
                      Map<String, dynamic>.from(e as Map),
                    ))
                .toList();
    final preciseReferencesRaw = row['precise_references'] as String?;
    final preciseReferences =
        preciseReferencesRaw == null || preciseReferencesRaw.isEmpty
            ? const <PreciseReferenceImage>[]
            : (jsonDecode(preciseReferencesRaw) as List)
                .map((e) => PreciseReferenceImage.fromJson(
                      Map<String, dynamic>.from(e as Map),
                    ))
                .toList();
    final modeName = row['mode'] as String?;
    final providerTypeName = row['provider_type'] as String?;

    return GenerationTaskModel(
      id: row['id'] as int?,
      taskId: row['task_id'] as String,
      model: row['model'] as String,
      endpointId: row['endpoint_id'] as String?,
      protocol: row['protocol'] as String?,
      prompt: row['prompt'] as String,
      negativePrompt: row['negative_prompt'] as String?,
      width: row['width'] as int,
      height: row['height'] as int,
      size: row['size'] as String?,
      scale: (row['scale'] as num).toDouble(),
      cfgRescale: (row['cfg_rescale'] as num).toDouble(),
      sampler: row['sampler'] as String,
      noiseSchedule: row['noise_schedule'] as String,
      steps: row['steps'] as int? ?? 28,
      useCoords: (row['use_coords'] as int? ?? 1) == 1,
      seed: row['seed'] as int?,
      characters: chars,
      vibeReferences: vibeReferences,
      preciseReferences: preciseReferences,
      mode: GenerationMode.values.firstWhere(
        (value) => value.name == modeName,
        orElse: () => GenerationMode.textToImage,
      ),
      sourceImagePath: row['source_image_path'] as String?,
      maskImagePath: row['mask_image_path'] as String?,
      inpaintStrength: (row['inpaint_strength'] as num?)?.toDouble(),
      img2imgSourceImagePath: row['img2img_source_image_path'] as String?,
      img2imgStrength: (row['img2img_strength'] as num?)?.toDouble(),
      responseFormat: row['response_format'] as String?,
      disabledOriginalImage: (row['disabled_original_image'] as int? ?? 0) == 1,
      colorCorrect: (row['color_correct'] as int? ?? 1) == 1,
      providerType: ImageProviderType.values.firstWhere(
        (value) => value.name == providerTypeName,
        orElse: () => ImageProviderType.novelAi,
      ),
      status: row['status'] as String,
      imagePath: row['image_path'] as String?,
      imageUrl: row['image_url'] as String?,
      errorMessage: row['error_message'] as String?,
      isFavorite: (row['is_favorite'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      completedAt: row['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['completed_at'] as int)
          : null,
    );
  }

  /// Android CursorWindow 单行上限约 1~2MB，对长文本字段做截断保护，
  /// 防止异常长 prompt / 错误堆栈 / 角色引用 JSON 把整行撑爆导致后续
  /// `SELECT *` 抛 DatabaseException(Row too big to fit into CursorWindow)。
  static const int _maxTextLength = 64 * 1024; // 64KB
  static String? _truncate(String? text) {
    if (text == null) return null;
    if (text.length <= _maxTextLength) return text;
    return '${text.substring(0, _maxTextLength - 16)}…[truncated]';
  }

  /// 转数据库行
  Map<String, dynamic> toDb() {
    return {
      if (id != null) 'id': id,
      'task_id': taskId,
      'model': model,
      'endpoint_id': endpointId,
      'protocol': protocol,
      'prompt': _truncate(prompt) ?? '',
      'negative_prompt': _truncate(negativePrompt),
      'width': width,
      'height': height,
      'size': size,
      'scale': scale,
      'cfg_rescale': cfgRescale,
      'sampler': sampler,
      'noise_schedule': noiseSchedule,
      'steps': steps,
      'use_coords': useCoords ? 1 : 0,
      'seed': seed,
      'characters': _truncate(
        characters != null && characters!.isNotEmpty
            ? jsonEncode(characters!.map((c) => c.toJson()).toList())
            : null,
      ),
      'vibe_references': vibeReferences.isEmpty
          ? null
          : _truncate(
              jsonEncode(vibeReferences.map((r) => r.toJson()).toList()),
            ),
      'precise_references': preciseReferences.isEmpty
          ? null
          : _truncate(
              jsonEncode(preciseReferences.map((r) => r.toJson()).toList()),
            ),
      'mode': mode.name,
      'source_image_path': sourceImagePath,
      'mask_image_path': maskImagePath,
      'inpaint_strength': inpaintStrength,
      'img2img_source_image_path': img2imgSourceImagePath,
      'img2img_strength': img2imgStrength,
      'response_format': responseFormat,
      'provider_type': providerType.name,
      'disabled_original_image': disabledOriginalImage ? 1 : 0,
      'color_correct': colorCorrect ? 1 : 0,
      'status': status,
      'image_path': imagePath,
      'image_url': imageUrl,
      'error_message': _truncate(errorMessage),
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
    };
  }

  /// 从 Domain Entity 转 Model
  factory GenerationTaskModel.fromEntity(GenerationTask entity) {
    return GenerationTaskModel(
      id: entity.id,
      taskId: entity.taskId,
      model: entity.model,
      endpointId: entity.endpointId,
      protocol: entity.protocol,
      prompt: entity.prompt,
      negativePrompt: entity.negativePrompt,
      width: entity.width,
      height: entity.height,
      size: entity.size,
      scale: entity.scale,
      cfgRescale: entity.cfgRescale,
      sampler: entity.sampler,
      noiseSchedule: entity.noiseSchedule,
      steps: entity.steps,
      useCoords: entity.useCoords,
      seed: entity.seed,
      characters: entity.characters,
      vibeReferences: entity.vibeReferences,
      preciseReferences: entity.preciseReferences,
      mode: entity.mode,
      sourceImagePath: entity.sourceImagePath,
      maskImagePath: entity.maskImagePath,
      inpaintStrength: entity.inpaintStrength,
      img2imgSourceImagePath: entity.img2imgSourceImagePath,
      img2imgStrength: entity.img2imgStrength,
      responseFormat: entity.responseFormat,
      providerType: entity.providerType,
      disabledOriginalImage: entity.disabledOriginalImage,
      colorCorrect: entity.colorCorrect,
      status: entity.status,
      imagePath: entity.imagePath,
      imageUrl: entity.imageUrl,
      errorMessage: entity.errorMessage,
      createdAt: entity.createdAt,
      completedAt: entity.completedAt,
    );
  }

  /// 转 Domain Entity
  GenerationTask toEntity() {
    return GenerationTask(
      id: id,
      taskId: taskId,
      model: model,
      endpointId: endpointId,
      protocol: protocol,
      prompt: prompt,
      negativePrompt: negativePrompt,
      width: width,
      height: height,
      size: size,
      scale: scale,
      cfgRescale: cfgRescale,
      sampler: sampler,
      noiseSchedule: noiseSchedule,
      steps: steps,
      useCoords: useCoords,
      seed: seed,
      characters: characters,
      vibeReferences: vibeReferences,
      preciseReferences: preciseReferences,
      mode: mode,
      sourceImagePath: sourceImagePath,
      maskImagePath: maskImagePath,
      inpaintStrength: inpaintStrength,
      img2imgSourceImagePath: img2imgSourceImagePath,
      img2imgStrength: img2imgStrength,
      responseFormat: responseFormat,
      providerType: providerType,
      disabledOriginalImage: disabledOriginalImage,
      colorCorrect: colorCorrect,
      status: status,
      imagePath: imagePath,
      imageUrl: imageUrl,
      errorMessage: errorMessage,
      createdAt: createdAt,
      completedAt: completedAt,
    );
  }
}
