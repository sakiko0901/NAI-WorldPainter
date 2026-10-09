import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/services/comic_asset_store.dart';
import 'package:nai_huishi/core/utils/comic_storyboard_importer.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/services/comic_generation_coordinator.dart';
import 'package:nai_huishi/domain/services/comic_rasterizer.dart';
import 'package:nai_huishi/domain/usecases/manage_comic_projects.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

class ComicProjectViewModel extends ChangeNotifier {
  static const _uuid = Uuid();

  final ManageComicProjectsUseCase _manage;
  final ComicGenerationCoordinator _coordinator;
  final ComicRasterizer _rasterizer;
  final ComicAssetStore _assetStore;
  final SaveImageUseCase _saveImage;
  final GenerationViewModel _generation;

  ComicProjectViewModel({
    required ManageComicProjectsUseCase manage,
    required ComicGenerationCoordinator coordinator,
    required ComicRasterizer rasterizer,
    required ComicAssetStore assetStore,
    required SaveImageUseCase saveImage,
    required GenerationViewModel generation,
  })  : _manage = manage,
        _coordinator = coordinator,
        _rasterizer = rasterizer,
        _assetStore = assetStore,
        _saveImage = saveImage,
        _generation = generation;

  List<ComicProject> projects = const [];
  ComicProject? project;
  bool isLoading = false;
  bool isGenerating = false;
  String? error;

  List<ImageModelOption> get modelOptions => _generation.imageModelOptions
      .where((option) => option.provider.name == 'novelAi')
      .toList();

  Future<void> loadProjects() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      projects = await _manage.getAll();
    } catch (e) {
      error = '读取漫画项目失败：$e';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<ComicProject> create(String title) async {
    final created = await _manage.create(title: title);
    project = created;
    _generation.addListener(_onGenerationDefaultsAvailable);
    await _saveProject();
    await loadProjects();
    return project!;
  }

  Future<void> open(String id) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      project = await _manage.getById(id);
      if (project == null) {
        error = '漫画项目不存在或工程文件不可用';
      } else {
        _generation.addListener(_onGenerationDefaultsAvailable);
      }
    } catch (e) {
      error = '打开漫画项目失败：$e';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _manage.delete(id);
    if (project?.id == id) project = null;
    await loadProjects();
  }

  Future<void> deletePanel(String panelId) async {
    final current = _requireProject();
    ComicPanel? target;
    for (final panel in current.panels) {
      if (panel.id == panelId) {
        target = panel;
        break;
      }
    }
    if (target == null) throw StateError('分镜不存在');
    if (target.status == ComicPanelStatus.generating || isGenerating) {
      throw StateError('当前分镜正在生成，无法删除');
    }
    final panels = current.panels
        .where((panel) => panel.id != panelId)
        .toList()
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(index: entry.key + 1))
        .toList();
    project = current.copyWith(panels: panels);
    await _saveProject();
    await _assetStore.deletePanelAssets(current.id, panelId);
  }

  Future<void> importStoryboard(String source) async {
    final current = _requireProject();
    final panels = ComicStoryboardImporter.parse(source);
    if (panels.isEmpty) throw const FormatException('未找到有效分镜提示词');
    project = current.copyWith(panels: panels);
    await _saveProject();
  }

  Future<void> addPanel() async {
    final current = _requireProject();
    final index = current.panels.length + 1;
    final panel = ComicPanel(
      id: _uuid.v4(),
      index: index,
      title: '分镜 $index',
      rect: const ComicRect(x: 0.08, y: 0.08, width: 0.84, height: 0.48),
    );
    project = current.copyWith(panels: [...current.panels, panel]);
    await _saveProject();
  }

  Future<void> updateProject(ComicProject value) async {
    project = value;
    await _saveProject();
  }

  Future<void> updatePanel(ComicPanel value) async {
    final current = _requireProject();
    project = current.copyWith(
      panels: current.panels
          .map((panel) => panel.id == value.id ? value : panel)
          .toList(),
    );
    await _saveProject();
  }

  Future<void> selectCandidate(String panelId, String candidateId) async {
    final current = _requireProject();
    ComicPanel? selectedPanel;
    for (final panel in current.panels) {
      if (panel.id == panelId) {
        selectedPanel = panel;
        break;
      }
    }
    if (selectedPanel == null ||
        !selectedPanel.candidates.any(
          (candidate) =>
              candidate.id == candidateId &&
              candidate.status == ComicPanelStatus.done,
        )) {
      throw StateError('只能选择已生成完成的候选图');
    }
    project = current.copyWith(
      panels: current.panels.map((panel) {
        return panel.id == panelId
            ? panel.copyWith(selectedCandidateId: candidateId)
            : panel;
      }).toList(),
    );
    await _saveProject();
  }

  Future<void> generatePanel(String panelId, {int? count}) async {
    final current = _requireProject();
    if (current.model.trim().isEmpty) {
      throw StateError('请先在统一设置中选择 NovelAI 模型');
    }
    isGenerating = true;
    error = null;
    notifyListeners();
    try {
      project = await _coordinator.generatePanel(
        current,
        panelId,
        count: count,
        onChanged: (value) {
          final active = project;
          if (active == null ||
              !active.panels.any((panel) => panel.id == panelId)) {
            return;
          }
          project = value;
          notifyListeners();
        },
      );
      await _saveProject();
    } catch (e) {
      error = '生成漫画分镜失败：$e';
    }
    isGenerating = false;
    notifyListeners();
  }

  Future<String> exportProject() async {
    final current = _requireProject();
    final output = await _assetStore.exportPagePath(current.id);
    for (final panel in current.panels) {
      final candidate = panel.selectedCandidate;
      if (candidate == null || candidate.imagePath.isEmpty) continue;
      final panelPath = await _assetStore.exportPanelPath(current.id, panel.id);
      await File(panelPath).writeAsBytes(
        await _rasterizer.renderPanel(panel, candidate.imagePath),
        flush: true,
      );
    }
    await File(output).writeAsBytes(
      await _rasterizer.renderProject(current),
      flush: true,
    );
    project = current.copyWith(
      lastExportPath: output,
      status: ComicProjectStatus.exported,
    );
    await _saveProject();
    return output;
  }

  Future<bool> saveExportToGallery() async {
    final path = _requireProject().lastExportPath;
    if (path == null || !await File(path).exists()) return false;
    return _saveImage.saveToGallery(path);
  }

  void _onGenerationDefaultsAvailable() {
    final current = project;
    if (current == null || current.model.isNotEmpty) return;
    final option = _generation.currentModelOption;
    if (option == null) return;
    project = current.copyWith(
      model: option.actualModel,
      endpointId: option.endpointId,
      protocol: option.protocol ?? '',
      resolution: _generation.selectedResolution,
      scale: _generation.scale,
      cfgRescale: _generation.cfgRescale,
      sampler: _generation.selectedSampler,
      noiseSchedule: _generation.selectedNoiseSchedule,
      steps: _generation.steps,
      seed: _generation.seed,
    );
    _saveProject();
  }

  @override
  void dispose() {
    _generation.removeListener(_onGenerationDefaultsAvailable);
    super.dispose();
  }

  Future<void> _saveProject() async {
    final current = _requireProject();
    project = current.copyWith(updatedAt: DateTime.now());
    await _manage.save(project!);
    notifyListeners();
  }

  ComicProject _requireProject() {
    final current = project;
    if (current == null) throw StateError('请先打开漫画项目');
    return current;
  }
}
