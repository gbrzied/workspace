// lib/local_queue_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalQueueService {
  static Database? _database;
  static const String tableName = 'local_clients';
  static const int _dbVersion = 2;
  final bool _inMemory;

  LocalQueueService({bool inMemory = false}) : _inMemory = inMemory;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    if (_inMemory) {
      return await openDatabase(
        ':memory:',
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } else {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'waiting_room.db');
      return await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  // ✅ Create table for fresh installs
  void _onCreate(Database db, int version) async {
    print('📦 Creating local_clients table (version $version)');
    await db.execute('''
CREATE TABLE $tableName (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  lat REAL,
  lng REAL,
  created_at TEXT NOT NULL,
  waiting_room_id TEXT,
  is_synced INTEGER NOT NULL DEFAULT 0
)
''');
  }

  // ✅ Handle schema migrations
  void _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 Upgrading database from v$oldVersion to v$newVersion');

    if (oldVersion < 2) {
      // Migration: Add waiting_room_id column if it doesn't exist
      try {
        await db.execute(
            'ALTER TABLE $tableName ADD COLUMN waiting_room_id TEXT'
        );
        print('✅ Added waiting_room_id column');
      } catch (e) {
        print('⚠️ Column already exists or error: $e');
      }
    }
  }

  Future<void> insertClientLocally(Map<String, dynamic> client) async {
    try {
      final db = await database;
      await db.insert(
        tableName,
        client,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('✅ Inserted client locally: ${client['name']}');
    } catch (e) {
      print('❌ Error inserting client: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getClients() async {
    try {
      final db = await database;
      return await db.query(tableName, orderBy: 'created_at ASC');
    } catch (e) {
      print('❌ Error getting clients: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedClients() async {
    try {
      final db = await database;
      return await db.query(
        tableName,
        where: 'is_synced = ?',
        whereArgs: [0],
      );
    } catch (e) {
      print('❌ Error getting unsynced clients: $e');
      return [];
    }
  }

  Future<void> markClientAsSynced(String id) async {
    try {
      final db = await database;
      final count = await db.update(
        tableName,
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      print('✅ Marked client $id as synced. Rows affected: $count');
    } catch (e) {
      print('❌ Error marking as synced: $e');
    }
  }

  Future<void> debugPrintAllClients() async {
    try {
      final db = await database;
      final result = await db.query(tableName);
      print('📋 All local clients:');
      for (var row in result) {
        print('   - ${row['id']}: ${row['name']} (synced: ${row['is_synced']})');
      }
    } catch (e) {
      print('❌ Error debug printing: $e');
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}