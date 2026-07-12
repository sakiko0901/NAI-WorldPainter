import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/artist_prompt.dart';
import 'package:nai_huishi/domain/usecases/manage_artist_prompts.dart';

enum ArtistPromptSortMode { recent, name, hot }

class ArtistPromptViewModel extends ChangeNotifier {
  final ManageArtistPromptsUseCase _useCase;

  ArtistPromptViewModel(this._useCase);

  List<ArtistPrompt> artists = [];
  List<String> categories = [];
  String currentCategory = '全部';
  String searchQuery = '';
  ArtistPromptSortMode sortMode = ArtistPromptSortMode.recent;
  Map<int, double> selectedWeights = {};
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      artists = await _useCase.getAll();
      categories = await _useCase.getCategories();
      errorMessage = null;
    } catch (e) {
      errorMessage = '加载画师串失败: $e';
    }
    isLoading = false;
    notifyListeners();
  }

  List<ArtistPrompt> get filteredArtists {
    final query = searchQuery.trim().toLowerCase();
    var list = artists.where((artist) {
      final matchesCategory = currentCategory == '全部' ||
          artist.categories.contains(currentCategory);
      final matchesSearch = query.isEmpty ||
          artist.name.toLowerCase().contains(query) ||
          artist.tag.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();

    switch (sortMode) {
      case ArtistPromptSortMode.name:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case ArtistPromptSortMode.hot:
        list.sort((a, b) => b.danbooruCount.compareTo(a.danbooruCount));
        break;
      case ArtistPromptSortMode.recent:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
    }
    return list;
  }

  String get generatedPrompt {
    final parts = <String>[];
    for (final artist in artists) {
      final id = artist.id;
      if (id == null) continue;
      final weight = selectedWeights[id];
      if (weight == null) continue;
      parts.add(weight == 1
          ? artist.tag
          : '${weight.toStringAsFixed(1)}::${artist.tag}::');
    }
    return parts.join(', ');
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void setCategory(String value) {
    currentCategory = value;
    notifyListeners();
  }

  void toggleSortMode() {
    final values = ArtistPromptSortMode.values;
    sortMode = values[(values.indexOf(sortMode) + 1) % values.length];
    notifyListeners();
  }

  void toggleSelected(ArtistPrompt artist) {
    final id = artist.id;
    if (id == null) return;
    if (selectedWeights.containsKey(id)) {
      selectedWeights.remove(id);
    } else {
      selectedWeights[id] = 1.0;
    }
    notifyListeners();
  }

  void clearSelected() {
    selectedWeights = {};
    notifyListeners();
  }

  void adjustWeight(int id, double delta) {
    final current = selectedWeights[id];
    if (current == null) return;
    final next = (current + delta).clamp(0.1, 8.0).toDouble();
    selectedWeights[id] = double.parse(next.toStringAsFixed(1));
    notifyListeners();
  }

  Future<void> create({
    required String name,
    required String tag,
    required String imagePath,
    required List<String> categories,
    required int danbooruCount,
  }) async {
    await _useCase.create(
      name: name,
      tag: tag,
      imagePath: imagePath,
      categories: categories,
      danbooruCount: danbooruCount,
    );
    await load();
  }

  Future<void> update(ArtistPrompt artist) async {
    await _useCase.update(artist);
    await load();
  }

  Future<void> delete(int id) async {
    await _useCase.delete(id);
    selectedWeights.remove(id);
    await load();
  }

  Future<void> addCategory(String category) async {
    await _useCase.addCategory(category);
    await load();
  }

  Future<void> deleteCategory(String category) async {
    await _useCase.deleteCategory(category);
    if (currentCategory == category) currentCategory = '全部';
    await load();
  }

  Future<Map<String, dynamic>> exportData() => _useCase.exportData();
  Future<int> importData(Map<String, dynamic> data) async {
    final added = await _useCase.importData(data);
    await load();
    return added;
  }
}
