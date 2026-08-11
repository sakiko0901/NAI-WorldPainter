import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/data/datasources/local/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('opens a v14 database missing the Vibe table and restores it', () async {
    final path = p.join(await getDatabasesPath(), AppConstants.dbName);
    await deleteDatabase(path);
    addTearDown(() => deleteDatabase(path));

    final legacyDb = await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE generation_history (id INTEGER PRIMARY KEY)');
      },
    );
    await legacyDb.close();

    final db = await DatabaseHelper.instance.database;
    final table = await db.rawQuery('PRAGMA table_info(vibe_encodings)');

    expect(
        table.map((column) => column['name']),
        containsAll([
          'id',
          'thumbnail_path',
          'source_image_path',
          'encoded_vibe',
        ]));
  });
}
