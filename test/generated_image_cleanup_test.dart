import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/local/database_helper.dart';
import 'package:nai_huishi/data/datasources/local/generated_image_cleanup.dart';
import 'package:nai_huishi/data/repositories/history_repository_impl.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fixture;
  late Directory documents;
  late Directory images;
  late Database db;
  late SharedPreferences preferences;
  late DateTime now;
  late GeneratedImageCleanup cleanup;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    fixture = await Directory.systemTemp.createTemp('generated_image_cleanup_');
    await databaseFactory.setDatabasesPath(fixture.path);
    db = await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await db.close();
    await fixture.delete(recursive: true);
  });

  setUp(() async {
    await db.delete('generation_history');
    await db.delete('llm_messages');
    await db.delete('llm_sessions');
    documents = await fixture.createTemp('documents_');
    images = await Directory(p.join(documents.path, AppConstants.imagesDirName))
        .create();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 11, 23, 12);
    cleanup = GeneratedImageCleanup(
      db,
      preferences,
      documentsDirectory: () async => documents,
      now: () => now,
    );
  });

  Future<File> writeImage(String name, {bool recent = false}) async {
    final file = await File(p.join(images.path, name)).writeAsString('image');
    await file.setLastModified(now.subtract(Duration(hours: recent ? 1 : 48)));
    return file;
  }

  test('reclaims expired output and preserves every persisted reference',
      () async {
    final old = [
      await writeImage('nai_1.png'),
      await writeImage('inpaint_123_5_base.png'),
      await writeImage('inpaint_layer_123_1.png'),
      await writeImage('inpaint_compare_123_2_1.png'),
      await writeImage('enhance_123.png'),
      await writeImage('upscale_123_x4.png'),
    ];
    final recent = await writeImage('inpaint_123_5_mask.png', recent: true);
    final unknown = await writeImage('custom.png');
    final historyOutput = await writeImage('nai_2.png');
    final historyInput = await writeImage('inpaint_123_5_before.png');
    final historyReference = await writeImage('nai_3.png');
    final draftReference = await writeImage('nai_4.png');
    final comicReference = await writeImage('nai_5.png');
    final firstChatImage =
        await writeImage('12345678-1234-1234-1234-123456789abc.jpg');
    final secondChatImage = await writeImage('nai_6.png');
    final firstToolImage = await writeImage('nai_7.png');
    final secondToolImage = await writeImage('nai_8.png');
    final comics = Directory(
      p.join(documents.path, AppConstants.comicProjectsDirName, 'project'),
    );
    await comics.create(recursive: true);
    await File(p.join(comics.path, 'project.json')).writeAsString(
      jsonEncode({'reference': comicReference.path}),
    );
    await preferences.setString(
      AppConstants.keyPreciseReferencesDraft,
      jsonEncode([
        {'path': draftReference.path},
      ]),
    );
    await HistoryRepositoryImpl(db).saveTask(
      _task('keep', historyOutput, now).copyWith(
        sourceImagePath: historyInput.path,
        preciseReferences: [PreciseReferenceImage(path: historyReference.path)],
      ),
    );
    await db.insert('llm_sessions', {
      'id': 'conversation',
      'title': 'conversation',
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('llm_messages', {
      'session_id': 'conversation',
      'role': 'assistant',
      'content': '',
      'image_path': jsonEncode([firstChatImage.path, secondChatImage.path]),
      'tool_calls': jsonEncode({
        'first': firstToolImage.path,
        'long_payload': 'x' * (2 * 1024 * 1024),
        'second': secondToolImage.path,
      }),
      'created_at': 0,
    });

    await cleanup.runIfDue();

    expect(await Future.wait(old.map((file) => file.exists())),
        everyElement(false));
    final kept = [
      recent,
      unknown,
      historyOutput,
      historyInput,
      historyReference,
      draftReference,
      comicReference,
      firstChatImage,
      secondChatImage,
      firstToolImage,
      secondToolImage,
    ];
    expect(await Future.wait(kept.map((file) => file.exists())),
        everyElement(true));

    final leftover = await writeImage('inpaint_202_other.png');
    now = now.add(const Duration(hours: 23));
    await cleanup.runIfDue();
    expect(await leftover.exists(), isTrue);

    now = now.add(const Duration(hours: 1));
    await cleanup.runIfDue();
    expect(await leftover.exists(), isFalse);
    expect(await recent.exists(), isFalse);
    expect(await historyOutput.exists(), isTrue);
  });

  test('history deletion and trimming preserve copies still in use', () async {
    final repo = HistoryRepositoryImpl(db);
    final oldResult = await writeImage('nai_10.png');
    final latestResult = await writeImage('nai_11.png');
    final exported =
        await File(p.join(fixture.path, 'nai_12.png')).writeAsString('export');
    await repo.saveTask(_task('old', oldResult, now));
    await repo.saveTask(
      _task('latest', latestResult, now.add(const Duration(seconds: 1)))
          .copyWith(sourceImagePath: oldResult.path),
    );
    await repo.saveTask(_task('external', exported, now));
    await repo.deleteTask('external');
    await repo.trimHistory(keep: 1);

    expect(await repo.getTaskCount(), 1);
    expect(await oldResult.exists(), isTrue);
    expect(await exported.exists(), isTrue);
    await cleanup.runIfDue();
    expect(await oldResult.exists(), isTrue);
    expect(await latestResult.exists(), isTrue);

    await repo.clearHistory();
    expect(await repo.getTaskCount(), 0);
    now = now.add(const Duration(days: 1));
    await cleanup.runIfDue();
    expect(await oldResult.exists(), isFalse);
    expect(await latestResult.exists(), isFalse);
    expect(await exported.exists(), isTrue);
  });

  test('an incomplete reference scan keeps files and permits retry', () async {
    final file = await writeImage('nai_13.png');
    final incomplete =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      final failingCleanup = GeneratedImageCleanup(
        incomplete,
        preferences,
        documentsDirectory: () async => documents,
        now: () => now,
      );
      await expectLater(
          failingCleanup.runIfDue(), throwsA(isA<DatabaseException>()));
      expect(await file.exists(), isTrue);
    } finally {
      await incomplete.close();
    }

    await cleanup.runIfDue();
    expect(await file.exists(), isFalse);
  });
}

GenerationTask _task(String id, File output, DateTime createdAt) =>
    GenerationTask(
      taskId: id,
      model: 'nai',
      prompt: '',
      width: 1024,
      height: 1024,
      scale: 5,
      cfgRescale: 0,
      sampler: 'sampler',
      noiseSchedule: 'native',
      status: 'success',
      imagePath: output.path,
      createdAt: createdAt,
    );
