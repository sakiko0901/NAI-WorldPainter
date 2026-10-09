import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/services/comic_asset_store.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/repositories/comic_project_repository.dart';

class ComicProjectRepositoryImpl implements ComicProjectRepository {
  static const _uuid = Uuid();
  static const _projectTable = 'comic_projects';
  static const _panelTable = 'comic_panels';
  static const _candidateTable = 'comic_candidates';

  final Database _db;
  final ComicAssetStore _assetStore;

  ComicProjectRepositoryImpl(this._db, this._assetStore);

  @override
  Future<List<ComicProject>> getAll() async {
    final rows = await _db.query(
      _projectTable,
      orderBy: 'updated_at DESC',
    );
    final projects = <ComicProject>[];
    for (final row in rows) {
      final path = row['project_json_path'] as String;
      try {
        projects.add(await _assetStore.readProject(path));
      } catch (_) {
        // An unavailable project file remains indexed so the user can remove it.
        projects.add(_metadataProject(row));
      }
    }
    return projects;
  }

  @override
  Future<ComicProject?> getById(String id) async {
    final rows = await _db.query(
      _projectTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final path = rows.first['project_json_path'] as String;
    return _assetStore.readProject(path);
  }

  @override
  Future<ComicProject> create({
    required String title,
    int canvasWidth = 1600,
    int canvasHeight = 2400,
  }) async {
    final now = DateTime.now();
    final project = ComicProject(
      id: _uuid.v4(),
      title: title.trim().isEmpty ? '未命名漫画' : title.trim(),
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      createdAt: now,
      updatedAt: now,
    );
    await save(project);
    return project;
  }

  @override
  Future<void> save(ComicProject project) async {
    final updated = project.copyWith(updatedAt: DateTime.now());
    final projectPath = await _assetStore.writeProject(updated);
    await _db.transaction((txn) async {
      await txn.insert(
        _projectTable,
        _projectRow(updated, projectPath),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final existingPanels = await txn.query(
        _panelTable,
        columns: ['id'],
        where: 'project_id = ?',
        whereArgs: [updated.id],
      );
      for (final panel in existingPanels) {
        await txn.delete(
          _candidateTable,
          where: 'panel_id = ?',
          whereArgs: [panel['id']],
        );
      }
      await txn.delete(
        _panelTable,
        where: 'project_id = ?',
        whereArgs: [updated.id],
      );
      for (final panel in updated.panels) {
        await txn.insert(_panelTable, _panelRow(updated.id, panel));
        for (final candidate in panel.candidates) {
          await txn.insert(
            _candidateTable,
            _candidateRow(panel.id, candidate, panel.selectedCandidateId),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  @override
  Future<void> delete(String id) async {
    await _db.transaction((txn) async {
      final panels = await txn.query(
        _panelTable,
        columns: ['id'],
        where: 'project_id = ?',
        whereArgs: [id],
      );
      for (final panel in panels) {
        await txn.delete(
          _candidateTable,
          where: 'panel_id = ?',
          whereArgs: [panel['id']],
        );
      }
      await txn.delete(_panelTable, where: 'project_id = ?', whereArgs: [id]);
      await txn.delete(_projectTable, where: 'id = ?', whereArgs: [id]);
    });
    await _assetStore.deleteProject(id);
  }

  ComicProject _metadataProject(Map<String, Object?> row) {
    final timestamp =
        DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int);
    return ComicProject(
      id: row['id'] as String,
      title: row['title'] as String,
      canvasWidth: row['canvas_width'] as int,
      canvasHeight: row['canvas_height'] as int,
      status: ComicProjectStatus.values.byName(row['status'] as String),
      coverPath: row['cover_path'] as String?,
      lastExportPath: row['last_export_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: timestamp,
    );
  }

  Map<String, Object?> _projectRow(ComicProject project, String projectPath) =>
      {
        'id': project.id,
        'title': project.title,
        'schema_version': comicProjectSchemaVersion,
        'project_json_path': projectPath,
        'canvas_width': project.canvasWidth,
        'canvas_height': project.canvasHeight,
        'panel_count': project.panels.length,
        'status': project.status.name,
        'cover_path': project.coverPath,
        'last_export_path': project.lastExportPath,
        'created_at': project.createdAt.millisecondsSinceEpoch,
        'updated_at': project.updatedAt.millisecondsSinceEpoch,
      };

  Map<String, Object?> _panelRow(String projectId, ComicPanel panel) => {
        'id': panel.id,
        'project_id': projectId,
        'panel_index': panel.index,
        'status': panel.status.name,
        'candidate_count': panel.candidates.length,
        'selected_candidate_id': panel.selectedCandidateId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

  Map<String, Object?> _candidateRow(
    String panelId,
    ComicCandidate candidate,
    String? selectedCandidateId,
  ) =>
      {
        'id': candidate.id,
        'panel_id': panelId,
        'task_id': candidate.taskId,
        'image_path': candidate.imagePath,
        'task_snapshot_path': candidate.taskSnapshotPath,
        'status': candidate.status.name,
        'seed': candidate.seed,
        'error_message': candidate.errorMessage,
        'created_at': candidate.createdAt.millisecondsSinceEpoch,
        'completed_at': candidate.status == ComicPanelStatus.done
            ? DateTime.now().millisecondsSinceEpoch
            : null,
        'is_selected': candidate.id == selectedCandidateId ? 1 : 0,
      };
}
