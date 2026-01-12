import 'package:sqflite/sqflite.dart';

import '../../models/Item.dart';
import 'database_provider.dart';

class ItemDbHelper {
  static final ItemDbHelper _instance = ItemDbHelper._internal();

  factory ItemDbHelper() => _instance;

  ItemDbHelper._internal();

  final DatabaseProvider _dbProvider = DatabaseProvider();

  /// Public getter — required by SyncService
  Future<Database> get database => _dbProvider.database;

  // ─────────────── Migration ───────────────
  Future<void> ensureStockColumnsExist() async {
    final db = await database;
    try {
      await db.execute(
        'ALTER TABLE items ADD COLUMN stock_quantity INTEGER DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE items ADD COLUMN min_stock_level INTEGER DEFAULT 0',
      );
    } catch (_) {}
  }

  // ─────────────── Basic CRUD ───────────────
  Future<List<Item>> getItems(String storeId) async {
    final db = await database;
    final maps = await db.query(
      'items',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    return maps.map((m) => Item.fromMap(m)).toList();
  }

  Future<List<Item>> getItemsByCategory(
    String categoryCode,
    String storeId,
  ) async {
    final db = await database;
    final maps = await db.query(
      'items',
      where: 'itm_group_code = ? AND store_id = ?',
      whereArgs: [categoryCode, storeId],
    );
    return maps.map((m) => Item.fromMap(m)).toList();
  }

  Future<Item?> getItem(String itemCode, String storeId) async {
    final db = await database;
    final maps = await db.query(
      'items',
      where: 'item_code = ? AND store_id = ?',
      whereArgs: [itemCode, storeId],
      limit: 1,
    );
    return maps.isNotEmpty ? Item.fromMap(maps.first) : null;
  }

  /// Updated to support transaction (required by sync)
  Future<void> insertItem(Item item, String storeId, {Transaction? txn}) async {
    final db = txn ?? await database;
    await db.insert('items', {
      ...item.toMap(),
      'store_id': storeId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─────────────── The fixed stock update method ───────────────
  Future<void> updateItemStock(
    String itemCode,
    String storeId, {
    int? newStock,
    int? increaseBy,
    int? decreaseBy,
    Transaction? txn,
  }) async {
    final executor = txn ?? await database;

    final maps = await executor.query(
      'items',
      where: 'item_code = ? AND store_id = ?',
      whereArgs: [itemCode, storeId],
      limit: 1,
    );

    if (maps.isEmpty) {
      throw Exception('Item not found: $itemCode in store $storeId');
    }

    final item = Item.fromMap(maps.first);
    int updatedStock = item.stockQuantity;

    if (newStock != null) {
      updatedStock = newStock.clamp(0, 999999);
    } else if (increaseBy != null && increaseBy > 0) {
      updatedStock += increaseBy;
    } else if (decreaseBy != null && decreaseBy > 0) {
      updatedStock -= decreaseBy;
      updatedStock = updatedStock.clamp(0, 999999);
    } else {
      return;
    }

    await executor.update(
      'items',
      {'stock_quantity': updatedStock},
      where: 'item_code = ? AND store_id = ?',
      whereArgs: [itemCode, storeId],
    );
  }

  // ─────────────── Sync-related method ───────────────
  Future<void> clearAllItems(String storeId) async {
    final db = await database;
    await db.delete('items', where: 'store_id = ?', whereArgs: [storeId]);
  }

  // ─────────────── Other methods ───────────────
  Future<bool> hasEnoughStock(
    String itemCode,
    int needed,
    String storeId,
  ) async {
    final item = await getItem(itemCode, storeId);
    return item != null && item.stockQuantity >= needed;
  }

  Future<void> deleteItem(String itemCode, String storeId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'items',
        where: 'item_code = ? AND store_id = ?',
        whereArgs: [itemCode, storeId],
      );
      await txn.delete(
        'order_items',
        where: 'item_code = ? AND store_id = ?',
        whereArgs: [itemCode, storeId],
      );
    });
  }

  Future<List<Item>> getLowStockItems(String storeId) async {
    final db = await database;
    final maps = await db.query(
      'items',
      where:
          'store_id = ? AND stock_quantity <= min_stock_level AND min_stock_level > 0',
      whereArgs: [storeId],
      orderBy: 'stock_quantity ASC',
    );
    return maps.map((m) => Item.fromMap(m)).toList();
  }
}
