import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:nai_huishi/core/constants/app_constants.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, AppConstants.dbName);

    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE generation_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id TEXT UNIQUE NOT NULL,
        model TEXT NOT NULL,
        endpoint_id TEXT,
        protocol TEXT,
        prompt TEXT NOT NULL,
        negative_prompt TEXT,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL,
        size TEXT,
        scale REAL NOT NULL,
        cfg_rescale REAL NOT NULL,
        sampler TEXT NOT NULL,
        noise_schedule TEXT NOT NULL,
        steps INTEGER NOT NULL DEFAULT 28,
        use_coords INTEGER NOT NULL DEFAULT 1,
        seed INTEGER,
        characters TEXT,
        vibe_references TEXT,
        precise_references TEXT,
        mode TEXT NOT NULL DEFAULT 'textToImage',
        source_image_path TEXT,
        mask_image_path TEXT,
        inpaint_strength REAL,
        img2img_source_image_path TEXT,
        img2img_strength REAL,
        response_format TEXT,
        provider_type TEXT NOT NULL DEFAULT 'novelAi',
        disabled_original_image INTEGER NOT NULL DEFAULT 0,
        color_correct INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'pending',
        image_path TEXT,
        image_url TEXT,
        error_message TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE presets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        category TEXT NOT NULL,
        model TEXT NOT NULL,
        prompt TEXT NOT NULL,
        negative_prompt TEXT,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL,
        scale REAL NOT NULL,
        cfg_rescale REAL NOT NULL,
        sampler TEXT NOT NULL,
        noise_schedule TEXT NOT NULL,
        seed INTEGER,
        characters TEXT,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE prompt_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        content TEXT NOT NULL,
        tags TEXT,
        use_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 索引
    await db.execute(
        'CREATE INDEX idx_history_status ON generation_history(status)');
    await db.execute(
        'CREATE INDEX idx_history_created ON generation_history(created_at)');
    await db.execute(
        'CREATE INDEX idx_history_favorite ON generation_history(is_favorite)');
    await db.execute('CREATE INDEX idx_presets_category ON presets(category)');
    await db.execute(
        'CREATE INDEX idx_templates_category ON prompt_templates(category)');

    await _createLlmTables(db);
    await _createPromptAssistantTables(db);
    await _createArtistPromptTables(db);
    await _createVibeEncodingTables(db);
    await _createComicTables(db);
  }

  Future<void> _createComicTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS comic_projects (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        project_json_path TEXT NOT NULL,
        canvas_width INTEGER NOT NULL,
        canvas_height INTEGER NOT NULL,
        panel_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        cover_path TEXT,
        last_export_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS comic_panels (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        panel_index INTEGER NOT NULL,
        status TEXT NOT NULL,
        candidate_count INTEGER NOT NULL DEFAULT 0,
        selected_candidate_id TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS comic_candidates (
        id TEXT PRIMARY KEY,
        panel_id TEXT NOT NULL,
        task_id TEXT UNIQUE NOT NULL,
        image_path TEXT,
        task_snapshot_path TEXT,
        status TEXT NOT NULL,
        seed INTEGER,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        is_selected INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_comic_projects_updated '
      'ON comic_projects(updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_comic_panels_project '
      'ON comic_panels(project_id, panel_index)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_comic_candidates_panel '
      'ON comic_candidates(panel_id, created_at)',
    );
  }

  Future<void> _createVibeEncodingTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vibe_encodings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        thumbnail_path TEXT NOT NULL,
        source_image_path TEXT,
        encoded_vibe TEXT NOT NULL DEFAULT '',
        encoded_vibe_path TEXT,
        encoded_model TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vibe_encodings_updated '
      'ON vibe_encodings(updated_at DESC)',
    );
  }

  Future<void> _createLlmTables(Database db) async {
    await db.execute('''
      CREATE TABLE llm_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'general',
        context_key TEXT,
        prompt_version TEXT NOT NULL DEFAULT 'v5',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE llm_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        image_path TEXT,
        tool_calls TEXT,
        interaction_json TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES llm_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_llm_messages_session ON llm_messages(session_id, created_at)');
    await db.execute(
        'CREATE INDEX idx_llm_sessions_updated ON llm_sessions(updated_at)');
    await db.execute(
        'CREATE INDEX idx_llm_sessions_context ON llm_sessions(context_key)');
  }

  Future<void> _createPromptAssistantTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prompt_memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trigger TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        source TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'user',
        hit_count INTEGER NOT NULL DEFAULT 0,
        last_hit_at INTEGER,
        weight REAL NOT NULL DEFAULT 1.0,
        superseded_by INTEGER,
        embedding BLOB,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_prompt_memories_trigger ON prompt_memories(trigger)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_prompt_memories_updated ON prompt_memories(updated_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_prompt_memories_scope ON prompt_memories(scope)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_prompt_memories_source ON prompt_memories(source)');
    await _createPromptMemoriesFts(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS style_presets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        prompt TEXT NOT NULL,
        image_path TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_style_presets_updated ON style_presets(updated_at)');
  }

  /// FTS5 外部内容表 + 触发器同步。trigger/content 入索引，支持 BM25 检索。
  /// 注意：FTS5 在某些 Android 旧版本 SQLite 中未编译，创建会抛错；
  /// 因此本方法失败时不抛异常，仅打印警告，让 DB 初始化继续完成。
  /// 检索层（PromptMemoryRepositoryImpl）需自行判断 FTS 是否可用。
  Future<void> _createPromptMemoriesFts(Database db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS prompt_memories_fts USING fts5(
          "trigger", content, content='prompt_memories', content_rowid='id'
        )
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS prompt_memories_ai AFTER INSERT ON prompt_memories BEGIN
          INSERT INTO prompt_memories_fts(rowid, "trigger", content) VALUES (new.id, new."trigger", new.content);
        END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS prompt_memories_ad AFTER DELETE ON prompt_memories BEGIN
          INSERT INTO prompt_memories_fts(prompt_memories_fts, rowid, "trigger", content) VALUES('delete', old.id, old."trigger", old.content);
        END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS prompt_memories_au AFTER UPDATE ON prompt_memories BEGIN
          INSERT INTO prompt_memories_fts(prompt_memories_fts, rowid, "trigger", content) VALUES('delete', old.id, old."trigger", old.content);
          INSERT INTO prompt_memories_fts(rowid, "trigger", content) VALUES (new.id, new."trigger", new.content);
        END
      ''');
    } catch (e) {
      // FTS5 不可用时忽略，检索层会降级
      print('[DB] FTS5 创建失败（将降级为 LIKE 检索）: $e');
    }
  }

  Future<void> _createArtistPromptTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS artist_prompts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        tag TEXT NOT NULL,
        image_path TEXT NOT NULL DEFAULT '',
        categories TEXT NOT NULL,
        danbooru_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_artist_prompts_tag ON artist_prompts(tag)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_artist_prompts_updated ON artist_prompts(updated_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS artist_prompt_categories (
        name TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL
      )
    ''');

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final category in const ['二次元', '厚涂', '写实', '水墨', '黑白', 'R18']) {
      await db.insert(
        'artist_prompt_categories',
        {'name': category, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db
          .execute('ALTER TABLE generation_history ADD COLUMN seed INTEGER');
      await db.execute('ALTER TABLE presets ADD COLUMN seed INTEGER');
    }
    if (oldVersion < 3) {
      // v3: 移除 batch_id 列和 batch_tasks 表（SQLite 不支持 DROP COLUMN，保留旧列忽略即可）
      await db.execute('DROP TABLE IF EXISTS batch_tasks');
    }
    if (oldVersion < 4) {
      await _createLlmTables(db);
    }
    if (oldVersion < 6) {
      await _createArtistPromptTables(db);
    }
    if (oldVersion < 7) {
      await _ensureColumn(db, 'llm_messages', 'image_path TEXT');
    }
    if (oldVersion < 8) {
      await _ensureColumn(
          db, 'prompt_memories', 'scope TEXT NOT NULL DEFAULT \'user\'');
      await _ensureColumn(
          db, 'prompt_memories', 'hit_count INTEGER NOT NULL DEFAULT 0');
      await _ensureColumn(db, 'prompt_memories', 'last_hit_at INTEGER');
      await _ensureColumn(
          db, 'prompt_memories', 'weight REAL NOT NULL DEFAULT 1.0');
      await _ensureColumn(db, 'prompt_memories', 'superseded_by INTEGER');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_prompt_memories_scope ON prompt_memories(scope)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_prompt_memories_source ON prompt_memories(source)');
      await _createPromptMemoriesFts(db);
      // 老数据重建索引（FTS 创建成功才执行）
      try {
        await db.execute(
          'INSERT INTO prompt_memories_fts(rowid, "trigger", content) '
          'SELECT id, "trigger", content FROM prompt_memories',
        );
      } catch (_) {}
    }
    if (oldVersion < 9) {
      // Agent 化：llm_messages 加 tool_calls 列保存工具调用历史；prompt_memories 加 embedding 列（向量记忆预留）
      await _ensureColumn(db, 'llm_messages', 'tool_calls TEXT');
      await _ensureColumn(db, 'prompt_memories', 'embedding BLOB');
    }
    if (oldVersion < 10) {
      await _ensureGenerationHistoryColumns(db);
    }
    if (oldVersion < 11) {
      await _ensureGenerationHistoryColumns(db);
    }
    if (oldVersion < 12) {
      await _ensureGenerationHistoryColumns(db);
    }
    if (oldVersion < 13) {
      await _createVibeEncodingTables(db);
    }
    if (oldVersion < 14) {
      final table = await db.rawQuery('PRAGMA table_info(vibe_encodings)');
      final columns = table.map((column) => column['name'] as String).toSet();
      if (!columns.contains('source_image_path')) {
        await db.execute(
          'ALTER TABLE vibe_encodings ADD COLUMN source_image_path TEXT',
        );
      }
    }
    if (oldVersion < 15) {
      await _ensureVibeEncodingTable(db);
    }
    if (oldVersion < 16) {
      await _createComicTables(db);
    }
    if (oldVersion < 17) {
      await _ensureLlmSessionColumns(db);
    }
    if (oldVersion < 18) {
      await _ensureLlmInteractionColumns(db);
    }
    if (oldVersion < 20) {
      await _ensureGenerationHistoryColumns(db);
    }
    if (oldVersion < 21) {
      await _ensureGenerationHistoryColumns(db);
    }
    if (oldVersion < 22) {
      await _createDailyStatsTable(db);
    }
  }

  Future<void> _onOpen(Database db) async {
    await _ensureGenerationHistoryColumns(db);
    await _ensureVibeEncodingTable(db);
    await _ensureComicTables(db);
    await _ensureLlmSessionColumns(db);
    await _ensureLlmInteractionColumns(db);
    await _createDailyStatsTable(db);
  }

  /// 每日生成成功统计表。独立于 generation_history（后者会被裁剪到 200 条），
  /// 按天累加计数，长期保留。日期格式 yyyy-MM-dd（本地时区）。
  Future<void> _createDailyStatsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_generation_stats (
        date TEXT PRIMARY KEY,
        success_count INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _ensureLlmSessionColumns(Database db) async {
    final table = await db.rawQuery('PRAGMA table_info(llm_sessions)');
    if (table.isEmpty) return;
    final columns = table.map((column) => column['name'] as String).toSet();
    if (!columns.contains('scope')) {
      await db.execute(
        "ALTER TABLE llm_sessions ADD COLUMN scope TEXT NOT NULL DEFAULT 'general'",
      );
    }
    if (!columns.contains('context_key')) {
      await db.execute('ALTER TABLE llm_sessions ADD COLUMN context_key TEXT');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_llm_sessions_context ON llm_sessions(context_key)',
    );
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final name = definition.split(RegExp(r'\s+')).first;
    if (!columns.any((column) => column['name'] == name)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $definition');
    }
  }

  Future<void> _ensureLlmInteractionColumns(Database db) async {
    final sessions = await db.rawQuery('PRAGMA table_info(llm_sessions)');
    if (sessions.isNotEmpty) {
      final columns =
          sessions.map((column) => column['name'] as String).toSet();
      if (!columns.contains('prompt_version')) {
        await db.execute(
          "ALTER TABLE llm_sessions ADD COLUMN prompt_version TEXT NOT NULL DEFAULT 'v5'",
        );
      }
    }
    final messages = await db.rawQuery('PRAGMA table_info(llm_messages)');
    if (messages.isNotEmpty) {
      final columns =
          messages.map((column) => column['name'] as String).toSet();
      if (!columns.contains('interaction_json')) {
        await db.execute(
          'ALTER TABLE llm_messages ADD COLUMN interaction_json TEXT',
        );
      }
    }
  }

  Future<void> _ensureComicTables(Database db) => _createComicTables(db);

  Future<void> _ensureVibeEncodingTable(Database db) async {
    await _createVibeEncodingTables(db);
    final table = await db.rawQuery('PRAGMA table_info(vibe_encodings)');
    final columns = table.map((column) => column['name'] as String).toSet();
    if (!columns.contains('source_image_path')) {
      await db.execute(
        'ALTER TABLE vibe_encodings ADD COLUMN source_image_path TEXT',
      );
    }
    if (!columns.contains('encoded_vibe_path')) {
      await db.execute(
        'ALTER TABLE vibe_encodings ADD COLUMN encoded_vibe_path TEXT',
      );
    }
  }

  Future<void> _ensureGenerationHistoryColumns(Database db) async {
    final table = await db.rawQuery('PRAGMA table_info(generation_history)');
    if (table.isEmpty) return;

    final columns = table.map((column) => column['name'] as String).toSet();
    final definitions = <String, String>{
      'endpoint_id': 'TEXT',
      'protocol': 'TEXT',
      'size': 'TEXT',
      'steps': 'INTEGER NOT NULL DEFAULT 28',
      'use_coords': 'INTEGER NOT NULL DEFAULT 1',
      'vibe_references': 'TEXT',
      'precise_references': 'TEXT',
      'mode': "TEXT NOT NULL DEFAULT 'textToImage'",
      'source_image_path': 'TEXT',
      'mask_image_path': 'TEXT',
      'inpaint_strength': 'REAL',
      'img2img_source_image_path': 'TEXT',
      'img2img_strength': 'REAL',
      'response_format': 'TEXT',
      'provider_type': "TEXT NOT NULL DEFAULT 'novelAi'",
      'disabled_original_image': 'INTEGER NOT NULL DEFAULT 0',
      'color_correct': 'INTEGER NOT NULL DEFAULT 1',
    };
    for (final entry in definitions.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE generation_history ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }
}
