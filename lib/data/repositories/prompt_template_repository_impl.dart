import 'package:sqflite/sqflite.dart';
import 'package:nai_huishi/domain/entities/prompt_template.dart';
import 'package:nai_huishi/domain/repositories/prompt_template_repository.dart';
import 'package:nai_huishi/data/models/prompt_template_model.dart';

class PromptTemplateRepositoryImpl implements PromptTemplateRepository {
  final Database _db;

  PromptTemplateRepositoryImpl(this._db);

  static const String _table = 'prompt_templates';

  @override
  Future<List<PromptTemplate>> getAllTemplates() async {
    final rows =
        await _db.query(_table, orderBy: 'use_count DESC, updated_at DESC');
    return rows.map((r) => PromptTemplateModel.fromDb(r).toEntity()).toList();
  }

  @override
  Future<PromptTemplate?> getTemplate(int id) async {
    final rows =
        await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return PromptTemplateModel.fromDb(rows.first).toEntity();
  }

  @override
  Future<PromptTemplate> createTemplate(PromptTemplate template) async {
    final model = PromptTemplateModel.fromEntity(template);
    final id = await _db.insert(_table, model.toDb());
    return template.copyWith(id: id);
  }

  @override
  Future<PromptTemplate> updateTemplate(PromptTemplate template) async {
    final model = PromptTemplateModel.fromEntity(template);
    await _db.update(_table, model.toDb(),
        where: 'id = ?', whereArgs: [template.id]);
    return template;
  }

  @override
  Future<void> deleteTemplate(int id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<PromptTemplate>> getTemplatesByCategory(String category) async {
    final rows = await _db.query(
      _table,
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'use_count DESC, name',
    );
    return rows.map((r) => PromptTemplateModel.fromDb(r).toEntity()).toList();
  }

  @override
  Future<List<PromptTemplate>> searchTemplates(String query) async {
    final rows = await _db.query(
      _table,
      where: 'name LIKE ? OR content LIKE ? OR tags LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'use_count DESC',
    );
    return rows.map((r) => PromptTemplateModel.fromDb(r).toEntity()).toList();
  }

  @override
  Future<void> incrementUseCount(int id) async {
    await _db.rawUpdate(
      'UPDATE $_table SET use_count = use_count + 1, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }
}
