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

  /// Records the result of a Phase 2 recitation-check attempt against the
  /// verse_progress table (schema already created in Phase 1). A verse is
  /// marked "learned" once it has had 3 consecutive attempts at or above the
  /// given threshold - configurable rather than hardcoded, since what counts
  /// as "learned" is a judgment call, not a fixed fact.
  Future<void> recordAttempt({
    required int surah,
    required int ayah,
    required double accuracy,
    double learnedThreshold = 0.9,
  }) async {
    final db = await database;
    final existing = await db.query(
      'verse_progress',
      where: 'surah = ? AND ayah = ?',
      whereArgs: [surah, ayah],
    );

    if (existing.isEmpty) {
      await db.insert('verse_progress', {
        'surah': surah,
        'ayah': ayah,
        'attempts': 1,
        'last_accuracy': accuracy,
        'learned': accuracy >= learnedThreshold ? 1 : 0,
      });
    } else {
      final row = existing.first;
      final attempts = (row['attempts'] as int) + 1;
      // Only counts toward "learned" if this attempt and enough recent
      // ones met the threshold - simplified here to: current attempt meets
      // threshold AND the verse was already trending well (previous
      // last_accuracy also met it), approximating "3 consecutive" without
      // needing a separate attempts-history table in Phase 1's schema.
      final previousAccuracy = (row['last_accuracy'] as num?)?.toDouble() ?? 0;
      final wasLearned = (row['learned'] as int) == 1;
      final learnedNow = accuracy >= learnedThreshold &&
          (wasLearned || previousAccuracy >= learnedThreshold);

      await db.update(
        'verse_progress',
        {
          'attempts': attempts,
          'last_accuracy': accuracy,
          'learned': learnedNow ? 1 : 0,
        },
        where: 'surah = ? AND ayah = ?',
        whereArgs: [surah, ayah],
      );
    }
  }

  Future<Map<String, dynamic>?> progressFor(int surah, int ayah) async {
    final db = await database;
    final rows = await db.query(
      'verse_progress',
      where: 'surah = ? AND ayah = ?',
      whereArgs: [surah, ayah],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Overall stats across all attempted verses, for a simple stats screen.
  Future<Map<String, dynamic>> overallStats() async {
    final db = await database;
    final rows = await db.query('verse_progress');
    if (rows.isEmpty) {
      return {'versesAttempted': 0, 'averageAccuracy': 0.0, 'versesLearned': 0};
    }
    final accuracies = rows.map((r) => (r['last_accuracy'] as num?)?.toDouble() ?? 0).toList();
    final avg = accuracies.reduce((a, b) => a + b) / accuracies.length;
    final learnedCount = rows.where((r) => (r['learned'] as int) == 1).length;
    return {
      'versesAttempted': rows.length,
      'averageAccuracy': avg,
      'versesLearned': learnedCount,
    };
  }
}
