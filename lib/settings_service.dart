// lib/settings_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SettingsService {
  static Database? _database;
  static const String tableName = 'settings';
  static const String _demoModeKey = 'demo_mode';
  
  // Singleton pattern
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'settings.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  void _onCreate(Database db, int version) async {
    await db.execute('''
    CREATE TABLE $tableName (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''');
  }

  /// Get demo mode status (default: false)
  Future<bool> isDemoMode() async {
    try {
      final db = await database;
      final result = await db.query(
        tableName,
        where: 'key = ?',
        whereArgs: [_demoModeKey],
      );
      
      if (result.isEmpty) {
        return false;
      }
      return result.first['value'] == 'true';
    } catch (e) {
      print('❌ Error getting demo mode: $e');
      return false;
    }
  }

  /// Set demo mode status
  Future<void> setDemoMode(bool value) async {
    try {
      final db = await database;
      await db.insert(
        tableName,
        {'key': _demoModeKey, 'value': value.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('✅ Demo mode set to: $value');
    } catch (e) {
      print('❌ Error setting demo mode: $e');
    }
  }

  /// Toggle demo mode
  Future<bool> toggleDemoMode() async {
    final current = await isDemoMode();
    await setDemoMode(!current);
    return !current;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
