/// Offline database for queue management
library;

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/queue_item.dart';

/// SQLite database manager for offline queue
class OfflineDatabase {
  static final OfflineDatabase _instance = OfflineDatabase._internal();
  factory OfflineDatabase() => _instance;
  OfflineDatabase._internal();

  static Database? _database;

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'resilient_middleware.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  /// Create database schema
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE request_queue (
        id TEXT PRIMARY KEY,
        method TEXT NOT NULL,
        url TEXT NOT NULL,
        headers TEXT,
        body TEXT,
        priority INTEGER DEFAULT 5,
        retry_count INTEGER DEFAULT 0,
        max_retries INTEGER DEFAULT 3,
        created_at INTEGER NOT NULL,
        expires_at INTEGER,
        status TEXT DEFAULT 'pending',
        idempotency_key TEXT UNIQUE,
        sms_eligible INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_priority_created
      ON request_queue(priority DESC, created_at ASC)
    ''');

    await db.execute('''
      CREATE INDEX idx_status
      ON request_queue(status)
    ''');
  }

  /// Insert a queued request
  Future<int> insert(QueuedRequest request) async {
    final db = await database;
    return await db.insert(
      'request_queue',
      request.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all pending requests ordered by priority
  Future<List<QueuedRequest>> getPendingRequests({int? limit}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'request_queue',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'priority DESC, created_at ASC',
      limit: limit,
    );

    return List.generate(maps.length, (i) {
      return QueuedRequest.fromJson(maps[i]);
    });
  }

  /// Get request by ID
  Future<QueuedRequest?> getById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'request_queue',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return QueuedRequest.fromJson(maps.first);
  }

  /// Update request status
  Future<int> updateStatus(String id, String status) async {
    final db = await database;
    return await db.update(
      'request_queue',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Increment retry count
  Future<int> incrementRetryCount(String id) async {
    final db = await database;
    final request = await getById(id);
    if (request == null) return 0;

    return await db.update(
      'request_queue',
      {'retry_count': request.retryCount + 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete request
  Future<int> delete(String id) async {
    final db = await database;
    return await db.delete(
      'request_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete expired requests
  Future<int> deleteExpired() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.delete(
      'request_queue',
      where: 'expires_at IS NOT NULL AND expires_at < ?',
      whereArgs: [now],
    );
  }

  /// Get queue count
  Future<int> getQueueCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM request_queue WHERE status = ?',
      ['pending'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear all requests
  Future<int> clearAll() async {
    final db = await database;
    return await db.delete('request_queue');
  }

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
