import 'package:nai_huishi/domain/entities/comic_project.dart';
import 'package:nai_huishi/domain/repositories/comic_project_repository.dart';

class ManageComicProjectsUseCase {
  final ComicProjectRepository _repository;

  ManageComicProjectsUseCase(this._repository);

  Future<List<ComicProject>> getAll() => _repository.getAll();
  Future<ComicProject?> getById(String id) => _repository.getById(id);
  Future<ComicProject> create({
    required String title,
    int canvasWidth = 1600,
    int canvasHeight = 2400,
  }) =>
      _repository.create(
        title: title,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      );
  Future<void> save(ComicProject project) => _repository.save(project);
  Future<void> delete(String id) => _repository.delete(id);
}
