import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseProvider {
  static final DatabaseProvider _instance = DatabaseProvider._internal();
  static Database? _database;

  factory DatabaseProvider() => _instance;

  DatabaseProvider._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'pos.db');
    return await openDatabase(
      path,
      version: 5, // ← Bumped to 5 for the quantity fix
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 5) {
          // Migration: add quantity column if it doesn't exist
          try {
            await db.execute(
              'ALTER TABLE items ADD COLUMN quantity INTEGER DEFAULT 0;',
            );
          } catch (e) {
            // Ignore if column already exists
          }
          // Optional: you can keep drop/recreate for very old versions if needed
          if (oldVersion < 4) {
            await db.execute('DROP TABLE IF EXISTS stores');
            await db.execute('DROP TABLE IF EXISTS categories');
            await db.execute('DROP TABLE IF EXISTS items');
            await db.execute('DROP TABLE IF EXISTS orders');
            await db.execute('DROP TABLE IF EXISTS order_items');
            await _onCreate(db, newVersion);
          }
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE shifts (
        id TEXT PRIMARY KEY,
        userName TEXT NOT NULL,
        startTime INTEGER NOT NULL,
        endTime INTEGER,
        status TEXT NOT NULL,
        finalCashCount REAL,
        store_id TEXT NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shiftId TEXT NOT NULL,
        txnId TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        total REAL NOT NULL,
        paymentMethod TEXT NOT NULL,
        items TEXT NOT NULL,
        store_id TEXT NOT NULL,
        FOREIGN KEY (shiftId) REFERENCES shifts(id),
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
      )
    ''');

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
        is_active INTEGER NOT NULL DEFAULT 1,
        stock_quantity INTEGER DEFAULT 0,
        min_stock_level INTEGER DEFAULT 0,
        quantity INTEGER DEFAULT 0,           -- FIXED: now optional + default 0
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
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
      )
    ''');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
