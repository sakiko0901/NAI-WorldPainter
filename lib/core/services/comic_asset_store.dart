import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/domain/entities/comic_project.dart';

class ComicAssetStore {
  static const _uuid = Uuid();

  Future<Directory> projectDirectory(String projectId) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(documents.path, AppConstants.comicProjectsDirName, projectId),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> writeProject(ComicProject project) async {
    final directory = await projectDirectory(project.id);
    final file = File(p.join(directory.path, 'project.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
      flush: true,
    );
    return file.path;
  }

  Future<ComicProject> readProject(String path) async {
    final file = File(path);
    if (!await file.exists()) throw StateError('漫画工程文件不可用');
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw const FormatException('漫画工程文件格式无效');
    return ComicProject.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<String> copyAsset(String projectId, String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('引用图片不可用，请重新选择');
    final root = await projectDirectory(projectId);
    final assets = Directory(p.join(root.path, 'assets'));
    await assets.create(recursive: true);
    final extension = p.extension(source.path).isEmpty
        ? '.png'
        : p.extension(source.path).toLowerCase();
    final destination = File(p.join(assets.path, '${_uuid.v4()}$extension'));
    await source.copy(destination.path);
    return destination.path;
  }

  Future<String> candidatePath(
    String projectId,
    String panelId,
    String candidateId,
  ) async {
    final root = await projectDirectory(projectId);
    final directory = Directory(p.join(root.path, 'candidates', panelId));
    await directory.create(recursive: true);
    return p.join(directory.path, '$candidateId.png');
  }

  Future<String> taskSnapshotPath(String projectId, String candidateId) async {
    final root = await projectDirectory(projectId);
    final directory = Directory(p.join(root.path, 'tasks'));
    await directory.create(recursive: true);
    return p.join(directory.path, '$candidateId.json');
  }

  Future<String> exportPagePath(String projectId) async {
    final root = await projectDirectory(projectId);
    final directory = Directory(p.join(root.path, 'exports'));
    await directory.create(recursive: true);
    return p.join(
      directory.path,
      'page_${DateTime.now().millisecondsSinceEpoch}.png',
    );
  }

  Future<String> exportPanelPath(String projectId, String panelId) async {
    final root = await projectDirectory(projectId);
    final directory = Directory(p.join(root.path, 'exports', 'panels'));
    await directory.create(recursive: true);
    return p.join(
      directory.path,
      '${panelId}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
  }

  Future<void> deletePanelAssets(String projectId, String panelId) async {
    final root = await projectDirectory(projectId);
    final candidates = Directory(p.join(root.path, 'candidates', panelId));
    if (await candidates.exists()) await candidates.delete(recursive: true);

    final panelExports = Directory(p.join(root.path, 'exports', 'panels'));
    if (await panelExports.exists()) {
      await for (final entity in panelExports.list()) {
        if (p.basename(entity.path).startsWith('${panelId}_')) {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  Future<void> deleteProject(String projectId) async {
    final directory = await projectDirectory(projectId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
