// lib/local_rooms_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalRoomsService {
  static Database? _database;
  static const String tableName = 'local_rooms';
  static const int _dbVersion = 1;
  final bool _inMemory;

  LocalRoomsService({bool inMemory = false}) : _inMemory = inMemory;

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
      );
    } else {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'waiting_rooms.db');
      return await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
      );
    }
  }

  void _onCreate(Database db, int version) async {
    print('📦 Creating local_rooms table (version $version)');
    await db.execute('''
    CREATE TABLE $tableName (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL
    )
    ''');
  }

  Future<void> insertRoomLocally(Map<String, dynamic> room) async {
    try {
      final db = await database;
      await db.insert(
        tableName,
        room,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('✅ Inserted room locally: ${room['name']}');
    } catch (e) {
      print('❌ Error inserting room: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getRooms() async {
    try {
      final db = await database;
      return await db.query(tableName);
    } catch (e) {
      print('❌ Error getting rooms: $e');
      return [];
    }
  }

  Future<void> clearRooms() async {
    try {
      final db = await database;
      await db.delete(tableName);
      print('✅ Cleared all local rooms');
    } catch (e) {
      print('❌ Error clearing rooms: $e');
    }
  }

  /// Seed demo rooms for simulation/testing
  Future<void> seedDemoRooms() async {
    final demoRooms = [
      {
        'id': 'demo-room-1',
        'name': 'Downtown Clinic',
        'latitude': 40.7128,
        'longitude': -74.0060,
      },
      {
        'id': 'demo-room-2',
        'name': 'Airport Terminal A',
        'latitude': 40.6413,
        'longitude': -73.7781,
      },
      {
        'id': 'demo-room-3',
        'name': 'Shopping Mall Center',
        'latitude': 40.7589,
        'longitude': -73.9851,
      },
      {
        'id': 'demo-room-4',
        'name': 'University Campus',
        'latitude': 40.8075,
        'longitude': -73.9626,
      },
      {
        'id': 'demo-room-5',
        'name': 'Central Hospital',
        'latitude': 40.7614,
        'longitude': -73.9776,
      },
    ];

    for (var room in demoRooms) {
      await insertRoomLocally(room);
    }
    print('✅ Seeded ${demoRooms.length} demo rooms');
  }

  /// Check if demo rooms exist
  Future<bool> hasDemoRooms() async {
    final rooms = await getRooms();
    return rooms.isNotEmpty;
  }

  /// Seed demo clients for a specific room
  Future<void> seedDemoClients(String roomId) async {
    // This uses the existing LocalQueueService
    // Import will be handled where this is called
    print('✅ Demo clients should be seeded via QueueProvider');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
