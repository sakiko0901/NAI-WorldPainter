import 'package:nai_huishi/domain/entities/preset.dart';
import 'package:nai_huishi/domain/repositories/preset_repository.dart';

class ManagePresetsUseCase {
  final PresetRepository _repo;

  ManagePresetsUseCase(this._repo);

  Future<List<Preset>> getAll() => _repo.getAllPresets();
  Future<Preset?> getById(int id) => _repo.getPreset(id);
  Future<Preset> create(Preset preset) => _repo.createPreset(preset);
  Future<Preset> update(Preset preset) => _repo.updatePreset(preset);
  Future<void> delete(int id) => _repo.deletePreset(id);
  Future<List<Preset>> getByCategory(String category) =>
      _repo.getPresetsByCategory(category);
  Future<void> initBuiltin() => _repo.initBuiltinPresets();
}
