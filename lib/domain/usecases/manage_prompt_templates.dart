import 'package:nai_huishi/domain/entities/prompt_template.dart';
import 'package:nai_huishi/domain/repositories/prompt_template_repository.dart';

class ManagePromptTemplatesUseCase {
  final PromptTemplateRepository _repo;

  ManagePromptTemplatesUseCase(this._repo);

  Future<List<PromptTemplate>> getAll() => _repo.getAllTemplates();
  Future<PromptTemplate?> getById(int id) => _repo.getTemplate(id);
  Future<PromptTemplate> create(PromptTemplate template) =>
      _repo.createTemplate(template);
  Future<PromptTemplate> update(PromptTemplate template) =>
      _repo.updateTemplate(template);
  Future<void> delete(int id) => _repo.deleteTemplate(id);
  Future<List<PromptTemplate>> getByCategory(String category) =>
      _repo.getTemplatesByCategory(category);
  Future<List<PromptTemplate>> search(String query) =>
      _repo.searchTemplates(query);
  Future<void> incrementUseCount(int id) => _repo.incrementUseCount(id);
}
