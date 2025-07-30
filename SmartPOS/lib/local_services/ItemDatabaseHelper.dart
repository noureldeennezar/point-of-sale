import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/Catgeory.dart';
import '../models/Item.dart';
import '../models/Order.dart';

class ItemDatabaseHelper {
  static final ItemDatabaseHelper _instance = ItemDatabaseHelper._internal();
  static Database? _database;

  factory ItemDatabaseHelper() {
    return _instance;
  }

  ItemDatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'pos.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < newVersion) {
          await db.execute('DROP TABLE IF EXISTS categories');
          await db.execute('DROP TABLE IF EXISTS items');
          await db.execute('DROP TABLE IF EXISTS orders');
          await db.execute('DROP TABLE IF EXISTS order_items');
          await db.execute('DROP TABLE IF EXISTS sync_queue');
          await db.execute('DROP TABLE IF EXISTS category_sync_queue');
          await _onCreate(db, newVersion);
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        category_code TEXT PRIMARY KEY,
        category_name TEXT NOT NULL,
        main_group TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE items (
        item_code TEXT PRIMARY KEY,
        item_name TEXT NOT NULL,
        sales_price REAL NOT NULL,
        itm_group_code TEXT NOT NULL,
        barcode TEXT,
        is_active INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        FOREIGN KEY (itm_group_code) REFERENCES categories(category_code)
      )
    ''');
    await db.execute('''
      CREATE TABLE orders (
        orderNumber INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderNumber INTEGER NOT NULL,
        item_code TEXT NOT NULL,
        item_name TEXT NOT NULL,
        sales_price REAL NOT NULL,
        itm_group_code TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        barcode TEXT,
        is_active INTEGER NOT NULL,
        FOREIGN KEY (orderNumber) REFERENCES orders(orderNumber) ON DELETE CASCADE,
        FOREIGN KEY (item_code) REFERENCES items(item_code)
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_code TEXT NOT NULL,
        operation TEXT NOT NULL,
        item_data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE category_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_code TEXT NOT NULL,
        operation TEXT NOT NULL,
        category_data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> insertCategory(Category category) async {
    final db = await database;
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertItem(Item item) async {
    final db = await database;
    await db.insert(
      'items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertOrUpdateCategory(Category category) async {
    await insertCategory(category);
  }

  Future<void> insertOrUpdateItem(Item item) async {
    await insertItem(item);
  }

  Future<void> queueItemForSync(Item item, String operation) async {
    final db = await database;
    await db.insert('sync_queue', {
      'item_code': item.itemCode,
      'operation': operation,
      'item_data': jsonEncode(item.toMap()),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> queueCategoryForSync(Category category, String operation) async {
    final db = await database;
    await db.insert('category_sync_queue', {
      'category_code': category.categoryCode,
      'operation': operation,
      'category_data': jsonEncode(category.toMap()),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await database;
    return await db.query('sync_queue');
  }

  Future<List<Map<String, dynamic>>> getCategorySyncQueue() async {
    final db = await database;
    return await db.query('category_sync_queue');
  }

  Future<void> clearSyncQueue(String itemCode) async {
    final db = await database;
    await db.delete(
      'sync_queue',
      where: 'item_code = ?',
      whereArgs: [itemCode],
    );
  }

  Future<void> clearCategorySyncQueue(String categoryCode) async {
    final db = await database;
    await db.delete(
      'category_sync_queue',
      where: 'category_code = ?',
      whereArgs: [categoryCode],
    );
  }

  Future<List<Category>> getItemGroups() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('categories');
    return List.generate(maps.length, (i) => Category.fromMap(maps[i]));
  }

  Future<List<Item>> getItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('items');
    return List.generate(maps.length, (i) => Item.fromMap(maps[i]));
  }

  Future<int> insertOrder(Order order) async {
    final db = await database;
    int orderId = await db.insert('orders', {'date': order.date});
    for (var item in order.items) {
      await db.insert('order_items', {
        'orderNumber': orderId,
        'item_code': item.itemCode,
        'item_name': item.itemName,
        'sales_price': item.salesPrice,
        'itm_group_code': item.itmGroupCode,
        'quantity': item.quantity,
        'barcode': item.barcode,
        'is_active': item.isActive ? 1 : 0,
      });
    }
    return orderId;
  }

  Future<List<Map<String, dynamic>>> fetchOrdersWithItems() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> orders = await db.rawQuery('''
        SELECT 
          o.orderNumber, 
          o.date, 
          oi.item_code AS itemCode, 
          oi.item_name AS itemName, 
          oi.sales_price AS salesPrice, 
          oi.quantity 
        FROM orders o
        LEFT JOIN order_items oi ON o.orderNumber = oi.orderNumber
        ORDER BY o.orderNumber DESC
      ''');
      return orders;
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteItem(String itemCode) async {
    final db = await database;
    try {
      await db.delete(
        'items',
        where: 'item_code = ?',
        whereArgs: [itemCode],
      );
      await db.delete(
        'order_items',
        where: 'item_code = ?',
        whereArgs: [itemCode],
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteCategory(String categoryCode) async {
    final db = await database;
    try {
      // Delete items associated with the category
      await db.delete(
        'items',
        where: 'itm_group_code = ?',
        whereArgs: [categoryCode],
      );
      // Delete order items associated with the category
      await db.delete(
        'order_items',
        where: 'itm_group_code = ?',
        whereArgs: [categoryCode],
      );
      // Delete the category
      await db.delete(
        'categories',
        where: 'category_code = ?',
        whereArgs: [categoryCode],
      );
      // Delete subcategories
      await db.delete(
        'categories',
        where: 'main_group = ?',
        whereArgs: [categoryCode],
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearDatabase() async {
    final db = await database;
    try {
      await db.delete('order_items');
      await db.delete('orders');
      await db.delete('items');
      await db.delete('categories');
      await db.delete('sync_queue');
      await db.delete('category_sync_queue');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearItemsAndCategories() async {
    final db = await database;
    try {
      await db.delete('items');
      await db.delete('categories');
      await db.delete('sync_queue');
      await db.delete('category_sync_queue');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> resetOrderSequence() async {
    final db = await database;
    try {
      await db.delete('order_items');
      await db.delete('orders');
      await db.execute(
        'DELETE FROM sqlite_sequence WHERE name IN ("orders", "order_items")',
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<int> getLatestOrderId() async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'orders',
      columns: ['orderNumber'],
      orderBy: 'orderNumber DESC',
      limit: 1,
    );
    if (result.isNotEmpty && result.first['orderNumber'] != null) {
      return result.first['orderNumber'] as int;
    }
    return 0; // Return 0 if no orders exist
  }
}
