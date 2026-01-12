import 'package:sqflite/sqflite.dart';

import 'database_provider.dart';

class ShiftDbHelper {
  static final ShiftDbHelper _instance = ShiftDbHelper._internal();

  factory ShiftDbHelper() => _instance;

  ShiftDbHelper._internal();

  Future<Database> get database async => await DatabaseProvider().database;

  Future<String> openShift({
    required String storeId,
    required String userName,
    required DateTime startTime,
  }) async {
    final db = await database;

    final shiftId = DateTime.now().millisecondsSinceEpoch.toString();

    await db.insert('shifts', {
      'id': shiftId,
      'userName': userName,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': null,
      'status': 'open',
      'finalCashCount': null,
      'store_id': storeId,
    });

    return shiftId;
  }

  Future<void> closeShift({
    required String shiftId,
    required String storeId,
    required double finalCashCount,
    required DateTime endTime,
  }) async {
    final db = await database;

    await db.update(
      'shifts',
      {
        'endTime': endTime.millisecondsSinceEpoch,
        'status': 'closed',
        'finalCashCount': finalCashCount,
      },
      where: 'id = ? AND store_id = ?',
      whereArgs: [shiftId, storeId],
    );
  }

  Future<void> clearAllShifts(String storeId) async {
    final db = await database;
    await db.delete('shifts', where: 'store_id = ?', whereArgs: [storeId]);
  }

  Future<List<Map<String, dynamic>>> getAllShifts(String storeId) async {
    final db = await database;

    return await db.query(
      'shifts',
      where: 'store_id = ?',
      whereArgs: [storeId],
      orderBy: 'startTime DESC',
    );
  }

  Future<Map<String, dynamic>?> getActiveShift(String storeId) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'shifts',
      where: 'store_id = ? AND status = ?',
      whereArgs: [storeId, 'open'],
      orderBy: 'startTime DESC',
      limit: 1,
    );

    return maps.isNotEmpty ? maps.first : null;
  }

  /// **Required for sync** — This method was missing!
  Future<void> insertShiftFromMap(
    Map<String, dynamic> map,
    String storeId, {
    Transaction? txn,
  }) async {
    final db = txn ?? await database;

    await db.insert('shifts', {
      ...map,
      'store_id': storeId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
