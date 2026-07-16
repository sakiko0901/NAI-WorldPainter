import 'package:equatable/equatable.dart';

enum GenerationMode {
  textToImage,
  inpainting,
}

enum ImageProviderType {
  novelAi,
  gpt,
  nanoBanana,
}

class GenerationTask extends Equatable {
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
  final String status;
  final String? imagePath;
  final String? imageUrl;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;
  final GenerationMode mode;
  final String? sourceImagePath;
  final String? maskImagePath;
  final double? inpaintStrength;
  final String? responseFormat;
  final ImageProviderType providerType;
  final List<String>? gptImagePaths;
  final String? nanoImageSize;

  const GenerationTask({
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
    required this.status,
    this.imagePath,
    this.imageUrl,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
    this.mode = GenerationMode.textToImage,
    this.sourceImagePath,
    this.maskImagePath,
    this.inpaintStrength,
    this.responseFormat,
    this.providerType = ImageProviderType.novelAi,
    this.gptImagePaths,
    this.nanoImageSize,
  });

  GenerationTask copyWith({
    int? id,
    String? taskId,
    String? model,
    String? endpointId,
    String? protocol,
    String? prompt,
    String? negativePrompt,
    int? width,
    int? height,
    String? size,
    double? scale,
    double? cfgRescale,
    String? sampler,
    String? noiseSchedule,
    int? steps,
    bool? useCoords,
    int? seed,
    List<CharacterSpec>? characters,
    List<CharacterReferenceImage>? vibeReferences,
    List<PreciseReferenceImage>? preciseReferences,
    String? status,
    String? imagePath,
    String? imageUrl,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? completedAt,
    GenerationMode? mode,
    String? sourceImagePath,
    String? maskImagePath,
    double? inpaintStrength,
    String? responseFormat,
    ImageProviderType? providerType,
    List<String>? gptImagePaths,
    String? nanoImageSize,
  }) {
    return GenerationTask(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      model: model ?? this.model,
      endpointId: endpointId ?? this.endpointId,
      protocol: protocol ?? this.protocol,
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      width: width ?? this.width,
      height: height ?? this.height,
      size: size ?? this.size,
      scale: scale ?? this.scale,
      cfgRescale: cfgRescale ?? this.cfgRescale,
      sampler: sampler ?? this.sampler,
      noiseSchedule: noiseSchedule ?? this.noiseSchedule,
      steps: steps ?? this.steps,
      useCoords: useCoords ?? this.useCoords,
      seed: seed ?? this.seed,
      characters: characters ?? this.characters,
      vibeReferences: vibeReferences ?? this.vibeReferences,
      preciseReferences: preciseReferences ?? this.preciseReferences,
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      mode: mode ?? this.mode,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      maskImagePath: maskImagePath ?? this.maskImagePath,
      inpaintStrength: inpaintStrength ?? this.inpaintStrength,
      responseFormat: responseFormat ?? this.responseFormat,
      providerType: providerType ?? this.providerType,
      gptImagePaths: gptImagePaths ?? this.gptImagePaths,
      nanoImageSize: nanoImageSize ?? this.nanoImageSize,
    );
  }

  @override
  List<Object?> get props => [taskId];
}

class PreciseReferenceImage extends Equatable {
  static const types = {'character', 'style', 'character&style'};

  final String path;
  final String referenceType;
  final double strength;
  final double fidelity;

  const PreciseReferenceImage({
    required this.path,
    this.referenceType = 'character&style',
    this.strength = 1.0,
    this.fidelity = 1.0,
  });

  PreciseReferenceImage copyWith({
    String? path,
    String? referenceType,
    double? strength,
    double? fidelity,
  }) =>
      PreciseReferenceImage(
        path: path ?? this.path,
        referenceType: referenceType ?? this.referenceType,
        strength: strength ?? this.strength,
        fidelity: fidelity ?? this.fidelity,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'reference_type': referenceType,
        'strength': strength,
        'fidelity': fidelity,
      };

  factory PreciseReferenceImage.fromJson(Map<String, dynamic> json) {
    final referenceType = json['reference_type'] as String?;
    return PreciseReferenceImage(
      path: json['path'] as String? ?? '',
      referenceType:
          types.contains(referenceType) ? referenceType! : 'character&style',
      strength: (json['strength'] as num?)?.toDouble() ?? 1.0,
      fidelity: (json['fidelity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  List<Object?> get props => [path, referenceType, strength, fidelity];
}

class CharacterReferenceImage extends Equatable {
  final String path;
  final double strength;
  final double informationExtracted;

  const CharacterReferenceImage({
    required this.path,
    this.strength = 0.6,
    this.informationExtracted = 1.0,
  });

  CharacterReferenceImage copyWith({
    String? path,
    double? strength,
    double? informationExtracted,
  }) =>
      CharacterReferenceImage(
        path: path ?? this.path,
        strength: strength ?? this.strength,
        informationExtracted: informationExtracted ?? this.informationExtracted,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'strength': strength,
        'information_extracted': informationExtracted,
      };

  factory CharacterReferenceImage.fromJson(Map<String, dynamic> json) =>
      CharacterReferenceImage(
        path: json['path'] as String? ?? '',
        strength: (json['strength'] as num?)?.toDouble() ?? 0.6,
        informationExtracted:
            (json['information_extracted'] as num?)?.toDouble() ?? 1.0,
      );

  @override
  List<Object?> get props => [path, strength, informationExtracted];
}

/// 多人物坐标规格
class CharacterSpec extends Equatable {
  final String prompt;
  final String? uc;
  final double? centerX;
  final double? centerY;
  final bool enabled;
  final List<CharacterReferenceImage> referenceImages;

  const CharacterSpec({
    required this.prompt,
    this.uc,
    this.centerX,
    this.centerY,
    this.enabled = true,
    this.referenceImages = const [],
  });

  CharacterSpec copyWith({
    String? prompt,
    String? uc,
    double? centerX,
    double? centerY,
    bool clearUc = false,
    bool clearCenter = false,
    bool? enabled,
    List<CharacterReferenceImage>? referenceImages,
  }) {
    return CharacterSpec(
      prompt: prompt ?? this.prompt,
      uc: clearUc ? null : (uc ?? this.uc),
      centerX: clearCenter ? null : (centerX ?? this.centerX),
      centerY: clearCenter ? null : (centerY ?? this.centerY),
      enabled: enabled ?? this.enabled,
      referenceImages: referenceImages ?? this.referenceImages,
    );
  }

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        if (uc != null) 'uc': uc,
        if (centerX != null) 'center_x': centerX,
        if (centerY != null) 'center_y': centerY,
        'enabled': enabled,
        if (referenceImages.isNotEmpty)
          'reference_images':
              referenceImages.map((image) => image.toJson()).toList(),
      };

  factory CharacterSpec.fromJson(Map<String, dynamic> json) => CharacterSpec(
        prompt: json['prompt'] as String,
        uc: json['uc'] as String?,
        centerX: json['center_x'] != null
            ? (json['center_x'] as num).toDouble()
            : null,
        centerY: json['center_y'] != null
            ? (json['center_y'] as num).toDouble()
            : null,
        enabled: json['enabled'] as bool? ?? true,
        referenceImages: (json['reference_images'] as List?)
                ?.whereType<Map>()
                .map((image) => CharacterReferenceImage.fromJson(
                    Map<String, dynamic>.from(image)))
                .toList() ??
            const [],
      );

  @override
  List<Object?> get props =>
      [prompt, uc, centerX, centerY, enabled, referenceImages];
}
