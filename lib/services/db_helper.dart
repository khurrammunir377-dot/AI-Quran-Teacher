import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite storage for recording metadata and (in later phases)
/// attempt/progress history. Schema is kept intentionally simple and
/// versioned so Phase 2+ can add tables/columns via migrations without
/// breaking existing data.
class DbHelper {
  DbHelper._internal();
  static final DbHelper instance = DbHelper._internal();

  static const int schemaVersion = 1;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'hifz_companion.db');
    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            surah INTEGER NOT NULL,
            ayah INTEGER NOT NULL,
            file_path TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            size_bytes INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        // Placeholder for Phase 2+: per-verse accuracy/progress tracking.
        await db.execute('''
          CREATE TABLE verse_progress (
            surah INTEGER NOT NULL,
            ayah INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_accuracy REAL,
            learned INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (surah, ayah)
          )
        ''');
      },
    );
  }

  Future<int> saveRecording({
    required int surah,
    required int ayah,
    required String filePath,
    required int durationMs,
    required int sizeBytes,
  }) async {
    final db = await database;
    return db.insert('recordings', {
      'surah': surah,
      'ayah': ayah,
      'file_path': filePath,
      'duration_ms': durationMs,
      'size_bytes': sizeBytes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> recordingsFor(int surah, int ayah) async {
    final db = await database;
    return db.query(
      'recordings',
      where: 'surah = ? AND ayah = ?',
      whereArgs: [surah, ayah],
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> latestRecordingFor(int surah, int ayah) async {
    final rows = await recordingsFor(surah, ayah);
    return rows.isNotEmpty ? rows.first : null;
  }
}
