import 'package:nai_huishi/domain/entities/comic_project.dart';

abstract class ComicProjectRepository {
  Future<List<ComicProject>> getAll();
  Future<ComicProject?> getById(String id);
  Future<ComicProject> create({
    required String title,
    int canvasWidth = 1600,
    int canvasHeight = 2400,
  });
  Future<void> save(ComicProject project);
  Future<void> delete(String id);
}
