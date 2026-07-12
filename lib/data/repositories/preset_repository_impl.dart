import 'package:sqflite/sqflite.dart';
import 'package:nai_huishi/domain/entities/preset.dart';
import 'package:nai_huishi/domain/repositories/preset_repository.dart';
import 'package:nai_huishi/data/models/preset_model.dart';

class PresetRepositoryImpl implements PresetRepository {
  final Database _db;

  PresetRepositoryImpl(this._db);

  static const String _table = 'presets';

  @override
  Future<List<Preset>> getAllPresets() async {
    final rows = await _db.query(_table, orderBy: 'category, name');
    return rows.map((r) => PresetModel.fromDb(r).toEntity()).toList();
  }

  @override
  Future<Preset?> getPreset(int id) async {
    final rows =
        await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return PresetModel.fromDb(rows.first).toEntity();
  }

  @override
  Future<Preset> createPreset(Preset preset) async {
    final model = PresetModel.fromEntity(preset);
    final id = await _db.insert(_table, model.toDb());
    return preset.copyWith(id: id);
  }

  @override
  Future<Preset> updatePreset(Preset preset) async {
    final model = PresetModel.fromEntity(preset);
    await _db
        .update(_table, model.toDb(), where: 'id = ?', whereArgs: [preset.id]);
    return preset;
  }

  @override
  Future<void> deletePreset(int id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Preset>> getPresetsByCategory(String category) async {
    final rows = await _db.query(
      _table,
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'name',
    );
    return rows.map((r) => PresetModel.fromDb(r).toEntity()).toList();
  }

  @override
  Future<void> initBuiltinPresets() async {
    // 检查是否已有内置预设
    final count = Sqflite.firstIntValue(
      await _db.rawQuery(
          'SELECT COUNT(*) as count FROM $_table WHERE is_builtin = 1'),
    );
    if (count != null && count > 0) return;

    final now = DateTime.now();
    final builtins = [
      Preset(
        name: '二次元标准',
        category: '二次元',
        model: 'nai-diffusion-4-curated-preview',
        prompt:
            'masterpiece, best quality, amazing quality, very aesthetic, absurdres',
        negativePrompt:
            'lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry',
        width: 832,
        height: 1216,
        scale: 5.0,
        cfgRescale: 0.0,
        sampler: 'k_euler',
        noiseSchedule: 'native',
        isBuiltin: true,
        createdAt: now,
        updatedAt: now,
      ),
      Preset(
        name: '二次元风景',
        category: '风景',
        model: 'nai-diffusion-4-curated-preview',
        prompt:
            'masterpiece, best quality, amazing quality, very aesthetic, absurdres, scenery, landscape, no humans',
        negativePrompt:
            'lowres, worst quality, low quality, normal quality, jpeg artifacts, blurry, humans, person',
        width: 1216,
        height: 832,
        scale: 5.0,
        cfgRescale: 0.0,
        sampler: 'k_euler',
        noiseSchedule: 'native',
        isBuiltin: true,
        createdAt: now,
        updatedAt: now,
      ),
      Preset(
        name: '二次元角色',
        category: '角色',
        model: 'nai-diffusion-4-curated-preview',
        prompt:
            'masterpiece, best quality, amazing quality, very aesthetic, absurdres, 1girl, solo',
        negativePrompt:
            'lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry',
        width: 832,
        height: 1216,
        scale: 5.0,
        cfgRescale: 0.0,
        sampler: 'k_euler',
        noiseSchedule: 'native',
        isBuiltin: true,
        createdAt: now,
        updatedAt: now,
      ),
      Preset(
        name: 'Furry 标准',
        category: 'Furry',
        model: 'nai-diffusion-furry-3',
        prompt:
            'masterpiece, best quality, amazing quality, very aesthetic, absurdres, furry',
        negativePrompt:
            'lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry',
        width: 832,
        height: 1216,
        scale: 5.0,
        cfgRescale: 0.0,
        sampler: 'k_euler',
        noiseSchedule: 'native',
        isBuiltin: true,
        createdAt: now,
        updatedAt: now,
      ),
      Preset(
        name: '写实风格',
        category: '写实',
        model: 'nai-diffusion-4-curated-preview',
        prompt:
            'masterpiece, best quality, amazing quality, very aesthetic, absurdres, photorealistic, realistic',
        negativePrompt:
            'lowres, worst quality, low quality, normal quality, jpeg artifacts, blurry, anime, cartoon, illustration, painting, drawing',
        width: 1024,
        height: 1024,
        scale: 5.0,
        cfgRescale: 0.0,
        sampler: 'k_dpmpp_2m',
        noiseSchedule: 'karras',
        isBuiltin: true,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    for (final preset in builtins) {
      final model = PresetModel.fromEntity(preset);
      await _db.insert(_table, model.toDb());
    }
  }
}
