import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

/// A presentation-only fixture: never configures services or sends requests.
class FrontendGenerationFake extends ChangeNotifier
    implements GenerationViewModel {
  @override
  String prompt = '';
  @override
  String negativePrompt = '';
  @override
  String inpaintPrompt = '';
  @override
  String inpaintNegativePrompt = '';
  @override
  GenerationMode generationMode = GenerationMode.textToImage;
  @override
  List<GenerationTask> sessionResults = [];
  @override
  GenerationTask? lastCompletedTask;
  @override
  String? selectedResultTaskId;
  @override
  String? errorMessage;
  @override
  bool isGenerating = false;
  bool processingImage = false;
  @override
  bool get isProcessingImage => processingImage;
  @override
  String? imageProcessingSourceTaskId;
  @override
  String? imageProcessingLabel;
  @override
  String? imageProcessingStatus;
  GenerationTask? importedInpaintTask;
  @override
  int batchCount = 1;
  @override
  String selectedResolution = '832x1216';
  @override
  String selectedModel = 'nai-diffusion-4-5-full';
  @override
  List<CharacterSpec> get characters =>
      generationMode == GenerationMode.inpainting
          ? inpaintCharacters
          : _characters;
  @override
  set characters(List<CharacterSpec> value) {
    if (generationMode == GenerationMode.inpainting) {
      inpaintCharacters = value;
    } else {
      _characters = value;
    }
  }

  List<CharacterSpec> _characters = [];
  @override
  List<CharacterSpec> inpaintCharacters = [];
  @override
  List<String> gptImagePaths = [];
  @override
  List<CharacterReferenceImage> vibeReferences = [];
  @override
  List<PreciseReferenceImage> preciseReferences = [];
  @override
  ReferenceMode referenceMode = ReferenceMode.vibe;
  @override
  bool get isNonNovelAiProvider => false;
  @override
  bool get isNanoProvider => false;
  @override
  bool get isGptProvider => false;
  @override
  bool get isOfficialEndpoint => false;
  @override
  bool get is7877Endpoint => false;
  @override
  bool get isIkunEndpoint => false;
  @override
  bool get isV5Model => selectedModel.contains('diffusion-5');
  @override
  bool get supportsEffortToggle => false;
  @override
  Uint8List? streamPreviewBytes;
  @override
  int? streamPreviewStep;
  @override
  final Map<String, Uint8List> streamPreviews = {};
  @override
  final Map<String, int> streamPreviewSteps = {};
  @override
  bool get isMediumEffort => false;
  @override
  GenerationEffort effort = GenerationEffort.high;
  @override
  Future<void> updateEffort(GenerationEffort value) async {
    effort = value;
    notifyListeners();
  }

  @override
  bool get isTiledImg2Img => false;
  @override
  bool get isTiledCancelling => false;
  @override
  bool get isBatchCancelling => false;
  @override
  bool get isOfficialUpscaling => false;
  @override
  int get batchRemaining => 1;
  @override
  int get pendingCount => 0;
  @override
  int? get officialCostPerImage => null;
  @override
  ImageModelOption? get currentModelOption => imageModelOptions.first;
  @override
  List<ImageModelOption> imageModelOptions = const [
    ImageModelOption(
      modelId: 'nai-diffusion-4-5-full',
      displayName: 'NovelAI 4.5 Full',
      provider: ImageProviderType.novelAi,
      actualModel: 'nai-diffusion-4-5-full',
    ),
  ];
  @override
  List<String> get availableResolutions => ['832x1216', '1024x1024'];
  @override
  bool get supportsPreciseReferences => false;
  @override
  bool get supportsVibeReferences => false;
  @override
  bool get supportsCharacterPrompts => true;
  @override
  GenerationTask? get selectedResult => sessionResults
      .where((task) => task.taskId == selectedResultTaskId)
      .firstOrNull;
  @override
  Future<void> loadModels() async {}
  @override
  Future<void> updatePrompt(String value) async {
    prompt = value;
    notifyListeners();
  }

  @override
  Future<void> updateNegativePrompt(String value) async {
    negativePrompt = value;
    notifyListeners();
  }

  @override
  Future<void> importTaskToInpaint(GenerationTask task) async {
    importedInpaintTask = task;
    generationMode = GenerationMode.inpainting;
    inpaintPrompt = task.prompt;
    inpaintNegativePrompt = task.negativePrompt ?? '';
    characters = List<CharacterSpec>.of(task.characters ?? const []);
    notifyListeners();
  }

  @override
  Future<bool> upscaleWithOfficial(
    int scale, {
    GenerationTask? sourceTask,
  }) async =>
      false;

  @override
  Future<bool> enhanceWithOfficial({
    required double scale,
    required double strength,
    double noise = 0.0,
    bool max = false,
    String? promptOverride,
    GenerationTask? sourceTask,
    void Function(GenerationTask result)? onCompleted,
  }) async =>
      false;

  @override
  Future<String> upscaleFileWithOfficial(
    String inputPath,
    int scale, {
    GenerationTask? sourceTask,
  }) async =>
      inputPath;

  @override
  void selectResult(String taskId) {
    selectedResultTaskId = taskId;
    notifyListeners();
  }

  @override
  void addCharacter() {
    characters = [...characters, const CharacterSpec(prompt: '')];
    notifyListeners();
  }

  @override
  void updateCharacter(int index, CharacterSpec character) {
    characters = [...characters]..[index] = character;
    notifyListeners();
  }

  @override
  void setCharacterPositionAuto(int index) =>
      updateCharacter(index, characters[index].copyWith(clearCenter: true));

  @override
  void setGenerationMode(GenerationMode mode) {
    generationMode = mode;
    notifyListeners();
  }

  @override
  String resolutionLabel(String resolution) => resolution;
  void receive(GenerationTask task) {
    sessionResults = [...sessionResults, task];
    lastCompletedTask = task;
    selectedResultTaskId = task.taskId;
    notifyListeners();
  }

  @override
  void addCompletedWorkspaceResult(GenerationTask task) => receive(task);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GenerationTask frontendResult({
  String id = 'A',
  int? seed,
  String? imagePath,
}) =>
    GenerationTask(
      taskId: id,
      model: 'nai-diffusion-4-5-full',
      prompt: 'silver hair, warm afternoon light, by the window',
      negativePrompt: 'low quality, blurry',
      width: 832,
      height: 1216,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'karras',
      status: 'success',
      seed: seed,
      imagePath: imagePath,
      createdAt: DateTime(2026, 10, 11),
    );
