import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class ShiftDatabaseHelper {
  static final ShiftDatabaseHelper _instance = ShiftDatabaseHelper._internal();

  factory ShiftDatabaseHelper() => _instance;

  ShiftDatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'shift_database.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          '''
          CREATE TABLE shifts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day_code TEXT NOT NULL,
            day_shift_begin TEXT NOT NULL,
            day_shift_end TEXT NOT NULL,
            night_shift_begin TEXT NOT NULL,
            night_shift_end TEXT NOT NULL,
            open_shift TEXT NOT NULL,
            close_shift TEXT,
            extra_time INTEGER DEFAULT 0 CHECK(extra_time >= 0)
          )
          ''',
        );
      },
    );
  }

  Future<void> insertShift(Map<String, dynamic> shift) async {
    final db = await database;
    try {
      await db.insert(
        'shifts',
        shift,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print("Insert error: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getShifts() async {
    final db = await database;
    try {
      return await db.query('shifts');
    } catch (e) {
      print("Query error: $e");
      return [];
    }
  }

  Future<void> updateShift(int id, Map<String, dynamic> shift) async {
    final db = await database;
    try {
      await db.update(
        'shifts',
        shift,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print("Update error: $e");
    }
  }

  Future<void> deleteShift(int id) async {
    final db = await database;
    try {
      await db.delete(
        'shifts',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print("Delete error: $e");
    }
  }

  Future<void> clearShifts() async {
    final db = await database;
    try {
      await db.delete('shifts');
    } catch (e) {
      print("Clear table error: $e");
    }
  }
}
