import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/Category.dart';
import '../models/Item.dart';
import '../models/Order.dart';

class ItemDatabaseHelper {
  static final ItemDatabaseHelper _instance = ItemDatabaseHelper._internal();
  static Database? _database;

  factory ItemDatabaseHelper() => _instance;

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
      version: 4, // Updated version
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          await db.execute('DROP TABLE IF EXISTS stores');
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
      CREATE TABLE stores (
        store_id TEXT PRIMARY KEY,
        store_name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE categories (
        category_code TEXT PRIMARY KEY,
        category_name TEXT NOT NULL,
        main_group TEXT NOT NULL,
        store_id TEXT NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
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
        store_id TEXT NOT NULL,
        FOREIGN KEY (itm_group_code) REFERENCES categories(category_code),
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE orders (
        orderNumber INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        store_id TEXT NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
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
        store_id TEXT NOT NULL,
        FOREIGN KEY (orderNumber) REFERENCES orders(orderNumber) ON DELETE CASCADE,
        FOREIGN KEY (item_code) REFERENCES items(item_code),
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_code TEXT NOT NULL,
        operation TEXT NOT NULL,
        item_data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        store_id TEXT NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
      )
    ''');
    await db.execute('''
  CREATE TABLE order_sync_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_number TEXT NOT NULL,
    operation TEXT NOT NULL,
    order_data TEXT NOT NULL,
    created_at TEXT NOT NULL,
    store_id TEXT NOT NULL,
    FOREIGN KEY (store_id) REFERENCES stores(store_id)
  )
''');
    await db.execute('''
      CREATE TABLE category_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_code TEXT NOT NULL,
        operation TEXT NOT NULL,
        category_data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        store_id TEXT NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
      )
    ''');
  }

  Future<void> insertStore(String storeId, String storeName) async {
    final db = await database;
    await db.insert(
      'stores',
      {'store_id': storeId, 'store_name': storeName},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertCategory(Category category, String storeId) async {
    final db = await database;
    await db.insert(
      'categories',
      {...category.toMap(), 'store_id': storeId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertItem(Item item, String storeId) async {
    final db = await database;
    await db.insert(
      'items',
      {...item.toMap(), 'store_id': storeId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertOrUpdateCategory(Category category, String storeId) async {
    await insertCategory(category, storeId);
  }

  Future<void> insertOrUpdateItem(Item item, String storeId) async {
    await insertItem(item, storeId);
  }

  Future<void> queueItemForSync(Item item, String operation, String storeId) async {
    final db = await database;
    await db.insert('sync_queue', {
      'item_code': item.itemCode,
      'operation': operation,
      'item_data': jsonEncode(item.toMap()),
      'created_at': DateTime.now().toIso8601String(),
      'store_id': storeId,
    });
  }

  Future<void> queueOrderForSync(Order order, String operation, String storeId) async {
    final db = await database;
    await db.insert('order_sync_queue', {
      'order_number': order.orderNumber.toString(),
      'operation': operation,
      'order_data': jsonEncode(order.toMap()),
      'created_at': DateTime.now().toIso8601String(),
      'store_id': storeId,
    });
  }

  Future<List<Map<String, dynamic>>> getOrderSyncQueue(String storeId) async {
    final db = await database;
    return await db.query('order_sync_queue', where: 'store_id = ?', whereArgs: [storeId]);
  }

  Future<void> clearOrderSyncQueue(String orderNumber, String storeId) async {
    final db = await database;
    await db.delete(
      'order_sync_queue',
      where: 'order_number = ? AND store_id = ?',
      whereArgs: [orderNumber, storeId],
    );
  }

  Future<void> queueCategoryForSync(Category category, String operation, String storeId) async {
    final db = await database;
    await db.insert('category_sync_queue', {
      'category_code': category.categoryCode,
      'operation': operation,
      'category_data': jsonEncode(category.toMap()),
      'created_at': DateTime.now().toIso8601String(),
      'store_id': storeId,
    });
  }

  Future<List<Map<String, dynamic>>> getSyncQueue(String storeId) async {
    final db = await database;
    return await db.query('sync_queue', where: 'store_id = ?', whereArgs: [storeId]);
  }

  Future<List<Map<String, dynamic>>> getCategorySyncQueue(String storeId) async {
    final db = await database;
    return await db.query('category_sync_queue', where: 'store_id = ?', whereArgs: [storeId]);
  }

  Future<void> clearSyncQueue(String itemCode, String storeId) async {
    final db = await database;
    await db.delete(
      'sync_queue',
      where: 'item_code = ? AND store_id = ?',
      whereArgs: [itemCode, storeId],
    );
  }

  Future<void> clearCategorySyncQueue(String categoryCode, String storeId) async {
    final db = await database;
    await db.delete(
      'category_sync_queue',
      where: 'category_code = ? AND store_id = ?',
      whereArgs: [categoryCode, storeId],
    );
  }

  Future<List<Category>> getItemGroups(String storeId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
    await db.query('categories', where: 'store_id = ?', whereArgs: [storeId]);
    return List.generate(maps.length, (i) => Category.fromMap(maps[i]));
  }

  Future<List<Item>> getItems(String storeId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
    await db.query('items', where: 'store_id = ?', whereArgs: [storeId]);
    return List.generate(maps.length, (i) => Item.fromMap(maps[i]));
  }

  Future<int> insertOrder(Order order, String storeId) async {
    final db = await database;
    int orderId = await db.insert('orders', {'date': order.date, 'store_id': storeId});
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
        'store_id': storeId,
      });
    }
    return orderId;
  }

  Future<List<Map<String, dynamic>>> fetchOrdersWithItems(String storeId) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> orders = await db.rawQuery(
          '''
        SELECT 
          o.orderNumber, 
          o.date, 
          oi.item_code AS itemCode, 
          oi.item_name AS itemName, 
          oi.sales_price AS salesPrice, 
          oi.quantity 
        FROM orders o
        LEFT JOIN order_items oi ON o.orderNumber = oi.orderNumber
        WHERE o.store_id = ?
        ORDER BY o.orderNumber DESC
      ''',
          [storeId]);
      return orders;
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteItem(String itemCode, String storeId) async {
    final db = await database;
    try {
      await db.delete(
        'items',
        where: 'item_code = ? AND store_id = ?',
        whereArgs: [itemCode, storeId],
      );
      await db.delete(
        'order_items',
        where: 'item_code = ? AND store_id = ?',
        whereArgs: [itemCode, storeId],
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteCategory(String categoryCode, String storeId) async {
    final db = await database;
    try {
      await db.delete(
        'items',
        where: 'itm_group_code = ? AND store_id = ?',
        whereArgs: [categoryCode, storeId],
      );
      await db.delete(
        'order_items',
        where: 'itm_group_code = ? AND store_id = ?',
        whereArgs: [categoryCode, storeId],
      );
      await db.delete(
        'categories',
        where: 'category_code = ? AND store_id = ?',
        whereArgs: [categoryCode, storeId],
      );
      await db.delete(
        'categories',
        where: 'main_group = ? AND store_id = ?',
        whereArgs: [categoryCode, storeId],
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearDatabase(String storeId) async {
    final db = await database;
    try {
      await db.delete('order_items', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('orders', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('items', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('categories', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('sync_queue', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('category_sync_queue', where: 'store_id = ?', whereArgs: [storeId]);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearItemsAndCategories(String storeId) async {
    final db = await database;
    try {
      await db.delete('items', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('categories', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('sync_queue', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('category_sync_queue', where: 'store_id = ?', whereArgs: [storeId]);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> resetOrderSequence(String storeId) async {
    final db = await database;
    try {
      await db.delete('order_items', where: 'store_id = ?', whereArgs: [storeId]);
      await db.delete('orders', where: 'store_id = ?', whereArgs: [storeId]);
      await db.execute(
        'DELETE FROM sqlite_sequence WHERE name IN ("orders", "order_items")',
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<int> getLatestOrderId(String storeId) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'orders',
      columns: ['orderNumber'],
      where: 'store_id = ?',
      whereArgs: [storeId],
      orderBy: 'orderNumber DESC',
      limit: 1,
    );
    if (result.isNotEmpty && result.first['orderNumber'] != null) {
      return result.first['orderNumber'] as int;
    }
    return 0;
  }
}