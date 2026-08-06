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
  final double scale;
  final double cfgRescale;
  final String sampler;
  final String noiseSchedule;
  final int steps;
  final bool useCoords;
  final int? seed;
  final List<CharacterSpec>? characters;
  final List<PreciseReferenceImage> preciseReferences;
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
    required this.scale,
    required this.cfgRescale,
    required this.sampler,
    required this.noiseSchedule,
    this.steps = 28,
    this.useCoords = true,
    this.seed,
    this.characters,
    this.preciseReferences = const [],
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
    final preciseReferencesRaw = row['precise_references'] as String?;
    final preciseReferences =
        preciseReferencesRaw == null || preciseReferencesRaw.isEmpty
            ? const <PreciseReferenceImage>[]
            : (jsonDecode(preciseReferencesRaw) as List)
                .map((e) => PreciseReferenceImage.fromJson(
                      Map<String, dynamic>.from(e as Map),
                    ))
                .toList();

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
      scale: (row['scale'] as num).toDouble(),
      cfgRescale: (row['cfg_rescale'] as num).toDouble(),
      sampler: row['sampler'] as String,
      noiseSchedule: row['noise_schedule'] as String,
      steps: row['steps'] as int? ?? 28,
      useCoords: (row['use_coords'] as int? ?? 1) == 1,
      seed: row['seed'] as int?,
      characters: chars,
      preciseReferences: preciseReferences,
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
      'precise_references': preciseReferences.isEmpty
          ? null
          : _truncate(
              jsonEncode(preciseReferences.map((r) => r.toJson()).toList()),
            ),
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
      scale: entity.scale,
      cfgRescale: entity.cfgRescale,
      sampler: entity.sampler,
      noiseSchedule: entity.noiseSchedule,
      steps: entity.steps,
      useCoords: entity.useCoords,
      seed: entity.seed,
      characters: entity.characters,
      preciseReferences: entity.preciseReferences,
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
      scale: scale,
      cfgRescale: cfgRescale,
      sampler: sampler,
      noiseSchedule: noiseSchedule,
      steps: steps,
      useCoords: useCoords,
      seed: seed,
      characters: characters,
      preciseReferences: preciseReferences,
      status: status,
      imagePath: imagePath,
      imageUrl: imageUrl,
      errorMessage: errorMessage,
      createdAt: createdAt,
      completedAt: completedAt,
    );
  }
}
