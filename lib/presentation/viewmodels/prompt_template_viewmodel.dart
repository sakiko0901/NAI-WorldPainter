import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/prompt_template.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_templates.dart';

/// Prompt 模板 ViewModel
class PromptTemplateViewModel extends ChangeNotifier {
  final ManagePromptTemplatesUseCase _manageTemplates;

  PromptTemplateViewModel(this._manageTemplates);

  List<PromptTemplate> _templates = [];
  String? _selectedCategory;
  String _searchQuery = '';
  bool _isLoading = false;
  String? errorMessage;

  List<PromptTemplate> get templates {
    var result = _templates;
    if (_selectedCategory != null) {
      result = result.where((t) => t.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      result = result
          .where((t) =>
              t.name.contains(_searchQuery) || t.content.contains(_searchQuery))
          .toList();
    }
    return result;
  }

  String? get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  /// 加载所有模板
  Future<void> loadTemplates() async {
    _isLoading = true;
    notifyListeners();

    try {
      _templates = await _manageTemplates.getAll();
    } catch (e) {
      errorMessage = '加载模板失败: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 筛选分类
  void filterByCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  /// 搜索
  void search(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// 创建模板
  Future<PromptTemplate?> createTemplate(PromptTemplate template) async {
    try {
      final created = await _manageTemplates.create(template);
      await loadTemplates();
      return created;
    } catch (e) {
      errorMessage = '创建模板失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 更新模板
  Future<PromptTemplate?> updateTemplate(PromptTemplate template) async {
    try {
      final updated = await _manageTemplates.update(template);
      await loadTemplates();
      return updated;
    } catch (e) {
      errorMessage = '更新模板失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 删除模板
  Future<void> deleteTemplate(int id) async {
    try {
      await _manageTemplates.delete(id);
      _templates.removeWhere((t) => t.id == id);
      notifyListeners();
    } catch (e) {
      errorMessage = '删除模板失败: $e';
      notifyListeners();
    }
  }

  /// 使用模板（增加使用计数）
  Future<void> useTemplate(int id) async {
    try {
      await _manageTemplates.incrementUseCount(id);
    } catch (_) {}
  }
}
