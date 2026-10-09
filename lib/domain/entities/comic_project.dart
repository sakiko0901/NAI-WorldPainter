import 'package:equatable/equatable.dart';

const comicProjectSchemaVersion = 2;
const comicProjectSupportedSchemaVersions = {1, comicProjectSchemaVersion};
const comicCandidateCountMin = 1;
const comicCandidateCountMax = 10;

enum ComicProjectStatus { editing, generating, exported }

enum ComicPanelStatus { ready, queued, generating, done, failed }

enum ComicOverlayType { whiteCover, bubble, text }

enum ComicBubbleType { speech, thought, narration, shout }

enum ComicBubbleShape { oval, rectangle }

class ComicRect extends Equatable {
  final double x;
  final double y;
  final double width;
  final double height;

  const ComicRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  factory ComicRect.fromJson(Map<String, dynamic> json) => ComicRect(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        width: (json['width'] as num?)?.toDouble() ?? 1,
        height: (json['height'] as num?)?.toDouble() ?? 1,
      );

  @override
  List<Object?> get props => [x, y, width, height];
}

class ComicBrushStroke extends Equatable {
  final List<ComicPoint> points;
  final double width;

  const ComicBrushStroke({required this.points, this.width = 0.04});

  Map<String, dynamic> toJson() => {
        'points': points.map((point) => point.toJson()).toList(),
        'width': width,
      };

  factory ComicBrushStroke.fromJson(Map<String, dynamic> json) =>
      ComicBrushStroke(
        points: (json['points'] as List? ?? const [])
            .whereType<Map>()
            .map((value) =>
                ComicPoint.fromJson(Map<String, dynamic>.from(value)))
            .toList(),
        width: (json['width'] as num?)?.toDouble() ?? 0.04,
      );

  @override
  List<Object?> get props => [points, width];
}

class ComicPoint extends Equatable {
  final double x;
  final double y;

  const ComicPoint({required this.x, required this.y});

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory ComicPoint.fromJson(Map<String, dynamic> json) => ComicPoint(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [x, y];
}

class ComicDialogue extends Equatable {
  final String id;
  final String speaker;
  final String text;
  final bool generateText;

  const ComicDialogue({
    required this.id,
    this.speaker = '',
    required this.text,
    this.generateText = true,
  });

  ComicDialogue copyWith({
    String? id,
    String? speaker,
    String? text,
    bool? generateText,
  }) =>
      ComicDialogue(
        id: id ?? this.id,
        speaker: speaker ?? this.speaker,
        text: text ?? this.text,
        generateText: generateText ?? this.generateText,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'speaker': speaker,
        'text': text,
        'generateText': generateText,
      };

  factory ComicDialogue.fromJson(Map<String, dynamic> json) => ComicDialogue(
        id: json['id'] as String? ?? '',
        speaker: json['speaker'] as String? ?? '',
        text: json['text'] as String? ?? '',
        generateText: json['generateText'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [id, speaker, text, generateText];
}

class ComicOverlay extends Equatable {
  final String id;
  final ComicOverlayType type;
  final ComicRect rect;
  final String text;
  final ComicBubbleType bubbleType;
  final ComicBubbleShape bubbleShape;
  final double tailX;
  final double tailY;
  final double fontSize;
  final String? fontFamily;
  final int textColor;
  final int backgroundColor;
  final int borderColor;
  final double borderWidth;
  final List<ComicBrushStroke> brushStrokes;
  final int zIndex;
  final bool visible;

  const ComicOverlay({
    required this.id,
    required this.type,
    required this.rect,
    this.text = '',
    this.bubbleType = ComicBubbleType.speech,
    this.bubbleShape = ComicBubbleShape.rectangle,
    this.tailX = 0.5,
    this.tailY = 1,
    this.fontSize = 0.05,
    this.fontFamily,
    this.textColor = 0xFF111111,
    this.backgroundColor = 0xFFFFFFFF,
    this.borderColor = 0xFF111111,
    this.borderWidth = 0.006,
    this.brushStrokes = const [],
    this.zIndex = 0,
    this.visible = true,
  });

  ComicOverlay copyWith({
    String? id,
    ComicOverlayType? type,
    ComicRect? rect,
    String? text,
    ComicBubbleType? bubbleType,
    ComicBubbleShape? bubbleShape,
    double? tailX,
    double? tailY,
    double? fontSize,
    String? fontFamily,
    bool clearFontFamily = false,
    int? textColor,
    int? backgroundColor,
    int? borderColor,
    double? borderWidth,
    List<ComicBrushStroke>? brushStrokes,
    int? zIndex,
    bool? visible,
  }) =>
      ComicOverlay(
        id: id ?? this.id,
        type: type ?? this.type,
        rect: rect ?? this.rect,
        text: text ?? this.text,
        bubbleType: bubbleType ?? this.bubbleType,
        bubbleShape: bubbleShape ?? this.bubbleShape,
        tailX: tailX ?? this.tailX,
        tailY: tailY ?? this.tailY,
        fontSize: fontSize ?? this.fontSize,
        fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
        textColor: textColor ?? this.textColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        borderColor: borderColor ?? this.borderColor,
        borderWidth: borderWidth ?? this.borderWidth,
        brushStrokes: brushStrokes ?? this.brushStrokes,
        zIndex: zIndex ?? this.zIndex,
        visible: visible ?? this.visible,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'rect': rect.toJson(),
        'text': text,
        'bubbleType': bubbleType.name,
        'bubbleShape': bubbleShape.name,
        'tailX': tailX,
        'tailY': tailY,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'textColor': textColor,
        'backgroundColor': backgroundColor,
        'borderColor': borderColor,
        'borderWidth': borderWidth,
        'brushStrokes': brushStrokes.map((stroke) => stroke.toJson()).toList(),
        'zIndex': zIndex,
        'visible': visible,
      };

  factory ComicOverlay.fromJson(Map<String, dynamic> json) => ComicOverlay(
        id: json['id'] as String? ?? '',
        type: _enumOrDefault(
          ComicOverlayType.values,
          json['type'] as String?,
          ComicOverlayType.bubble,
        ),
        rect: ComicRect.fromJson(
          Map<String, dynamic>.from(json['rect'] as Map? ?? const {}),
        ),
        text: json['text'] as String? ?? '',
        bubbleType: _enumOrDefault(
          ComicBubbleType.values,
          json['bubbleType'] as String?,
          ComicBubbleType.speech,
        ),
        bubbleShape: _enumOrDefault(
          ComicBubbleShape.values,
          json['bubbleShape'] as String?,
          ComicBubbleShape.rectangle,
        ),
        tailX: (json['tailX'] as num?)?.toDouble() ?? 0.5,
        tailY: (json['tailY'] as num?)?.toDouble() ?? 1,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 0.05,
        fontFamily: json['fontFamily'] as String?,
        textColor: json['textColor'] as int? ?? 0xFF111111,
        backgroundColor: json['backgroundColor'] as int? ?? 0xFFFFFFFF,
        borderColor: json['borderColor'] as int? ?? 0xFF111111,
        borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 0.006,
        brushStrokes: (json['brushStrokes'] as List? ?? const [])
            .whereType<Map>()
            .map((value) =>
                ComicBrushStroke.fromJson(Map<String, dynamic>.from(value)))
            .toList(),
        zIndex: json['zIndex'] as int? ?? 0,
        visible: json['visible'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [
        id,
        type,
        rect,
        text,
        bubbleType,
        bubbleShape,
        tailX,
        tailY,
        fontSize,
        fontFamily,
        textColor,
        backgroundColor,
        borderColor,
        borderWidth,
        brushStrokes,
        zIndex,
        visible,
      ];
}

class ComicCandidate extends Equatable {
  final String id;
  final String taskId;
  final String imagePath;
  final String? taskSnapshotPath;
  final ComicPanelStatus status;
  final int? seed;
  final String? errorMessage;
  final DateTime createdAt;

  const ComicCandidate({
    required this.id,
    required this.taskId,
    this.imagePath = '',
    this.taskSnapshotPath,
    this.status = ComicPanelStatus.queued,
    this.seed,
    this.errorMessage,
    required this.createdAt,
  });

  ComicCandidate copyWith({
    String? imagePath,
    String? taskSnapshotPath,
    ComicPanelStatus? status,
    int? seed,
    String? errorMessage,
    bool clearError = false,
  }) =>
      ComicCandidate(
        id: id,
        taskId: taskId,
        imagePath: imagePath ?? this.imagePath,
        taskSnapshotPath: taskSnapshotPath ?? this.taskSnapshotPath,
        status: status ?? this.status,
        seed: seed ?? this.seed,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'imagePath': imagePath,
        'taskSnapshotPath': taskSnapshotPath,
        'status': status.name,
        'seed': seed,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ComicCandidate.fromJson(Map<String, dynamic> json) => ComicCandidate(
        id: json['id'] as String? ?? '',
        taskId: json['taskId'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
        taskSnapshotPath: json['taskSnapshotPath'] as String?,
        status: _enumOrDefault(
          ComicPanelStatus.values,
          json['status'] as String?,
          ComicPanelStatus.queued,
        ),
        seed: json['seed'] as int?,
        errorMessage: json['errorMessage'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  @override
  List<Object?> get props => [
        id,
        taskId,
        imagePath,
        taskSnapshotPath,
        status,
        seed,
        errorMessage,
        createdAt,
      ];
}

class ComicPanel extends Equatable {
  final String id;
  final int index;
  final String title;
  final String prompt;
  final ComicRect rect;
  final List<ComicDialogue> dialogues;
  final List<ComicCandidate> candidates;
  final String? selectedCandidateId;
  final List<ComicOverlay> overlays;
  final ComicPanelStatus status;

  const ComicPanel({
    required this.id,
    required this.index,
    required this.title,
    this.prompt = '',
    required this.rect,
    this.dialogues = const [],
    this.candidates = const [],
    this.selectedCandidateId,
    this.overlays = const [],
    this.status = ComicPanelStatus.ready,
  });

  ComicCandidate? get selectedCandidate {
    for (final candidate in candidates) {
      if (candidate.id == selectedCandidateId) return candidate;
    }
    return null;
  }

  ComicPanel copyWith({
    int? index,
    String? title,
    String? prompt,
    ComicRect? rect,
    List<ComicDialogue>? dialogues,
    List<ComicCandidate>? candidates,
    String? selectedCandidateId,
    bool clearSelectedCandidate = false,
    List<ComicOverlay>? overlays,
    ComicPanelStatus? status,
  }) =>
      ComicPanel(
        id: id,
        index: index ?? this.index,
        title: title ?? this.title,
        prompt: prompt ?? this.prompt,
        rect: rect ?? this.rect,
        dialogues: dialogues ?? this.dialogues,
        candidates: candidates ?? this.candidates,
        selectedCandidateId: clearSelectedCandidate
            ? null
            : (selectedCandidateId ?? this.selectedCandidateId),
        overlays: overlays ?? this.overlays,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'index': index,
        'title': title,
        'prompt': prompt,
        'rect': rect.toJson(),
        'dialogues': dialogues.map((value) => value.toJson()).toList(),
        'candidates': candidates.map((value) => value.toJson()).toList(),
        'selectedCandidateId': selectedCandidateId,
        'overlays': overlays.map((value) => value.toJson()).toList(),
        'status': status.name,
      };

  factory ComicPanel.fromJson(Map<String, dynamic> json) => ComicPanel(
        id: json['id'] as String? ?? '',
        index: json['index'] as int? ?? 1,
        title: json['title'] as String? ?? '分镜',
        prompt: json['prompt'] as String? ?? '',
        rect: ComicRect.fromJson(
          Map<String, dynamic>.from(json['rect'] as Map? ?? const {}),
        ),
        dialogues: (json['dialogues'] as List? ?? const [])
            .whereType<Map>()
            .map((value) =>
                ComicDialogue.fromJson(Map<String, dynamic>.from(value)))
            .toList(),
        candidates: (json['candidates'] as List? ?? const [])
            .whereType<Map>()
            .map((value) =>
                ComicCandidate.fromJson(Map<String, dynamic>.from(value)))
            .toList(),
        selectedCandidateId: json['selectedCandidateId'] as String?,
        overlays: (json['overlays'] as List? ?? const [])
            .whereType<Map>()
            .map((value) =>
                ComicOverlay.fromJson(Map<String, dynamic>.from(value)))
            .toList(),
        status: _enumOrDefault(
          ComicPanelStatus.values,
          json['status'] as String?,
          ComicPanelStatus.ready,
        ),
      );

  @override
  List<Object?> get props => [
        id,
        index,
        title,
        prompt,
        rect,
        dialogues,
        candidates,
        selectedCandidateId,
        overlays,
        status,
      ];
}

class ComicProject extends Equatable {
  final String id;
  final String title;
  final int canvasWidth;
  final int canvasHeight;
  final String globalPrompt;
  final String negativePrompt;
  final String model;
  final String? endpointId;
  final String protocol;
  final String resolution;
  final double scale;
  final double cfgRescale;
  final String sampler;
  final String noiseSchedule;
  final int steps;
  final int? seed;
  final int candidateCount;
  final List<ComicPanel> panels;
  final ComicProjectStatus status;
  final String? coverPath;
  final String? lastExportPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ComicProject({
    required this.id,
    required this.title,
    this.canvasWidth = 1600,
    this.canvasHeight = 2400,
    this.globalPrompt = '',
    this.negativePrompt = '',
    this.model = '',
    this.endpointId,
    this.protocol = '',
    this.resolution = '832x1216',
    this.scale = 5,
    this.cfgRescale = 0,
    this.sampler = 'k_euler',
    this.noiseSchedule = 'native',
    this.steps = 28,
    this.seed,
    this.candidateCount = comicCandidateCountMin,
    this.panels = const [],
    this.status = ComicProjectStatus.editing,
    this.coverPath,
    this.lastExportPath,
    required this.createdAt,
    required this.updatedAt,
  });

  ComicProject copyWith({
    String? title,
    int? canvasWidth,
    int? canvasHeight,
    String? globalPrompt,
    String? negativePrompt,
    String? model,
    String? endpointId,
    bool clearEndpoint = false,
    String? protocol,
    String? resolution,
    double? scale,
    double? cfgRescale,
    String? sampler,
    String? noiseSchedule,
    int? steps,
    int? seed,
    bool clearSeed = false,
    int? candidateCount,
    List<ComicPanel>? panels,
    ComicProjectStatus? status,
    String? coverPath,
    bool clearCover = false,
    String? lastExportPath,
    bool clearLastExport = false,
    DateTime? updatedAt,
  }) =>
      ComicProject(
        id: id,
        title: title ?? this.title,
        canvasWidth: canvasWidth ?? this.canvasWidth,
        canvasHeight: canvasHeight ?? this.canvasHeight,
        globalPrompt: globalPrompt ?? this.globalPrompt,
        negativePrompt: negativePrompt ?? this.negativePrompt,
        model: model ?? this.model,
        endpointId: clearEndpoint ? null : (endpointId ?? this.endpointId),
        protocol: protocol ?? this.protocol,
        resolution: resolution ?? this.resolution,
        scale: scale ?? this.scale,
        cfgRescale: cfgRescale ?? this.cfgRescale,
        sampler: sampler ?? this.sampler,
        noiseSchedule: noiseSchedule ?? this.noiseSchedule,
        steps: steps ?? this.steps,
        seed: clearSeed ? null : (seed ?? this.seed),
        candidateCount: _candidateCount(candidateCount ?? this.candidateCount),
        panels: panels ?? this.panels,
        status: status ?? this.status,
        coverPath: clearCover ? null : (coverPath ?? this.coverPath),
        lastExportPath:
            clearLastExport ? null : (lastExportPath ?? this.lastExportPath),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': comicProjectSchemaVersion,
        'id': id,
        'title': title,
        'canvas': {'width': canvasWidth, 'height': canvasHeight},
        'globalPrompt': globalPrompt,
        'negativePrompt': negativePrompt,
        'model': model,
        'endpointId': endpointId,
        'protocol': protocol,
        'resolution': resolution,
        'scale': scale,
        'cfgRescale': cfgRescale,
        'sampler': sampler,
        'noiseSchedule': noiseSchedule,
        'steps': steps,
        'seed': seed,
        'candidateCount': _candidateCount(candidateCount),
        'panels': panels.map((value) => value.toJson()).toList(),
        'status': status.name,
        'coverPath': coverPath,
        'lastExportPath': lastExportPath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ComicProject.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 1;
    if (!comicProjectSupportedSchemaVersions.contains(schemaVersion)) {
      throw const FormatException('不支持的漫画工程版本');
    }
    final canvas =
        Map<String, dynamic>.from(json['canvas'] as Map? ?? const {});
    return ComicProject(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名漫画',
      canvasWidth: canvas['width'] as int? ?? 1600,
      canvasHeight: canvas['height'] as int? ?? 2400,
      globalPrompt: json['globalPrompt'] as String? ?? '',
      negativePrompt: json['negativePrompt'] as String? ?? '',
      model: json['model'] as String? ?? '',
      endpointId: json['endpointId'] as String?,
      protocol: json['protocol'] as String? ?? '',
      resolution: json['resolution'] as String? ?? '832x1216',
      scale: (json['scale'] as num?)?.toDouble() ?? 5,
      cfgRescale: (json['cfgRescale'] as num?)?.toDouble() ?? 0,
      sampler: json['sampler'] as String? ?? 'k_euler',
      noiseSchedule: json['noiseSchedule'] as String? ?? 'native',
      steps: json['steps'] as int? ?? 28,
      seed: json['seed'] as int?,
      candidateCount: _candidateCount(json['candidateCount'] as int? ?? 1),
      panels: (json['panels'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => ComicPanel.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      status: _enumOrDefault(
        ComicProjectStatus.values,
        json['status'] as String?,
        ComicProjectStatus.editing,
      ),
      coverPath: json['coverPath'] as String?,
      lastExportPath: json['lastExportPath'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        canvasWidth,
        canvasHeight,
        globalPrompt,
        negativePrompt,
        model,
        endpointId,
        protocol,
        resolution,
        scale,
        cfgRescale,
        sampler,
        noiseSchedule,
        steps,
        seed,
        candidateCount,
        panels,
        status,
        coverPath,
        lastExportPath,
        createdAt,
        updatedAt,
      ];
}

T _enumOrDefault<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

int _candidateCount(int value) =>
    value.clamp(comicCandidateCountMin, comicCandidateCountMax);
