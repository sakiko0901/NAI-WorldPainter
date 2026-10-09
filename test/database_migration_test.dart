import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/local/database_helper.dart';
import 'package:nai_huishi/data/models/generation_task_model.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('upgrades a partially migrated v10 history database without data loss',
      () async {
    final path = p.join(await getDatabasesPath(), AppConstants.dbName);
    await deleteDatabase(path);
    addTearDown(() => deleteDatabase(path));

    final legacyDb =
        await openDatabase(path, version: 10, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE generation_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id TEXT UNIQUE NOT NULL,
          model TEXT NOT NULL,
          prompt TEXT NOT NULL,
          negative_prompt TEXT,
          width INTEGER NOT NULL,
          height INTEGER NOT NULL,
          scale REAL NOT NULL,
          cfg_rescale REAL NOT NULL,
          sampler TEXT NOT NULL,
          noise_schedule TEXT NOT NULL,
          steps INTEGER NOT NULL DEFAULT 28,
          seed INTEGER,
          characters TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          image_path TEXT,
          image_url TEXT,
          error_message TEXT,
          is_favorite INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          completed_at INTEGER
        )
      ''');
      await db.insert('generation_history', {
        'task_id': 'legacy-task',
        'model': 'legacy-model',
        'prompt': 'legacy prompt',
        'width': 832,
        'height': 1216,
        'scale': 5.0,
        'cfg_rescale': 0.0,
        'sampler': 'k_euler',
        'noise_schedule': 'native',
        'steps': 30,
        'status': 'success',
        'created_at': 1000,
      });
    });
    await legacyDb.close();

    final db = await DatabaseHelper.instance.database;
    final columns = await db.rawQuery('PRAGMA table_info(generation_history)');
    final names = columns.map((column) => column['name']).toSet();
    expect(
      names,
      containsAll([
        'endpoint_id',
        'protocol',
        'size',
        'steps',
        'use_coords',
        'vibe_references',
        'precise_references',
        'mode',
        'source_image_path',
        'mask_image_path',
        'inpaint_strength',
        'img2img_source_image_path',
        'img2img_strength',
        'response_format',
        'provider_type',
        'disabled_original_image',
        'color_correct',
      ]),
    );

    final legacyRows = await db.query(
      'generation_history',
      where: 'task_id = ?',
      whereArgs: ['legacy-task'],
    );
    expect(legacyRows, hasLength(1));
    expect(legacyRows.single['prompt'], 'legacy prompt');
    expect(legacyRows.single['steps'], 30);
    expect(legacyRows.single['use_coords'], 1);

    final task = GenerationTask(
      taskId: 'new-task',
      model: 'new-model',
      endpointId: 'endpoint-1',
      protocol: 'openai',
      prompt: 'new prompt',
      width: 1024,
      height: 1024,
      scale: 5,
      cfgRescale: 0,
      sampler: 'k_euler',
      noiseSchedule: 'native',
      size: '1024x1024',
      steps: 32,
      useCoords: false,
      mode: GenerationMode.inpainting,
      sourceImagePath: 'source.png',
      maskImagePath: 'mask.png',
      inpaintStrength: 0.8,
      responseFormat: 'b64_json',
      disabledOriginalImage: true,
      colorCorrect: false,
      vibeReferences: const [
        CharacterReferenceImage(path: 'vibe.png', strength: 0.4),
      ],
      status: 'pending',
      createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    await db.insert(
      'generation_history',
      GenerationTaskModel.fromEntity(task).toDb(),
    );
    final inserted = await db.query(
      'generation_history',
      where: 'task_id = ?',
      whereArgs: ['new-task'],
    );
    expect(inserted.single['endpoint_id'], 'endpoint-1');
    expect(inserted.single['protocol'], 'openai');
    expect(inserted.single['steps'], 32);
    expect(inserted.single['use_coords'], 0);
    expect(inserted.single['size'], '1024x1024');
    expect(inserted.single['mode'], 'inpainting');
    expect(inserted.single['source_image_path'], 'source.png');
    expect(inserted.single['mask_image_path'], 'mask.png');
    expect(inserted.single['inpaint_strength'], 0.8);
    expect(inserted.single['response_format'], 'b64_json');
    expect(inserted.single['provider_type'], 'novelAi');
    expect(inserted.single['disabled_original_image'], 1);
    expect(inserted.single['color_correct'], 0);
    expect(inserted.single['vibe_references'], isNotNull);
  });
}
