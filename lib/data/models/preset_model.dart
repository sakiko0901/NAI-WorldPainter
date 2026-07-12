import 'dart:convert';
import 'package:nai_huishi/domain/entities/preset.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

class PresetModel {
  final int? id;
  final String name;
  final String? description;
  final String category;
  final String model;
  final String prompt;
  final String? negativePrompt;
  final int width;
  final int height;
  final double scale;
  final double cfgRescale;
  final String sampler;
  final String noiseSchedule;
  final List<CharacterSpec>? characters;
  final bool isBuiltin;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PresetModel({
    this.id,
    required this.name,
    this.description,
    required this.category,
    required this.model,
    required this.prompt,
    this.negativePrompt,
    required this.width,
    required this.height,
    required this.scale,
    required this.cfgRescale,
    required this.sampler,
    required this.noiseSchedule,
    this.characters,
    this.isBuiltin = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PresetModel.fromDb(Map<String, dynamic> row) {
    List<CharacterSpec>? chars;
    if (row['characters'] != null && (row['characters'] as String).isNotEmpty) {
      final list = jsonDecode(row['characters'] as String) as List;
      chars = list
          .map((e) => CharacterSpec.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return PresetModel(
      id: row['id'] as int?,
      name: row['name'] as String,
      description: row['description'] as String?,
      category: row['category'] as String,
      model: row['model'] as String,
      prompt: row['prompt'] as String,
      negativePrompt: row['negative_prompt'] as String?,
      width: row['width'] as int,
      height: row['height'] as int,
      scale: (row['scale'] as num).toDouble(),
      cfgRescale: (row['cfg_rescale'] as num).toDouble(),
      sampler: row['sampler'] as String,
      noiseSchedule: row['noise_schedule'] as String,
      characters: chars,
      isBuiltin: (row['is_builtin'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Map<String, dynamic> toDb() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'category': category,
      'model': model,
      'prompt': prompt,
      'negative_prompt': negativePrompt,
      'width': width,
      'height': height,
      'scale': scale,
      'cfg_rescale': cfgRescale,
      'sampler': sampler,
      'noise_schedule': noiseSchedule,
      'characters': characters != null
          ? jsonEncode(characters!.map((c) => c.toJson()).toList())
          : null,
      'is_builtin': isBuiltin ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory PresetModel.fromEntity(Preset entity) {
    return PresetModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      category: entity.category,
      model: entity.model,
      prompt: entity.prompt,
      negativePrompt: entity.negativePrompt,
      width: entity.width,
      height: entity.height,
      scale: entity.scale,
      cfgRescale: entity.cfgRescale,
      sampler: entity.sampler,
      noiseSchedule: entity.noiseSchedule,
      characters: entity.characters,
      isBuiltin: entity.isBuiltin,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  Preset toEntity() {
    return Preset(
      id: id,
      name: name,
      description: description,
      category: category,
      model: model,
      prompt: prompt,
      negativePrompt: negativePrompt,
      width: width,
      height: height,
      scale: scale,
      cfgRescale: cfgRescale,
      sampler: sampler,
      noiseSchedule: noiseSchedule,
      characters: characters,
      isBuiltin: isBuiltin,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
