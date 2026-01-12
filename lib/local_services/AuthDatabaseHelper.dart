import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smart_pos.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 2, // ← Updated to version 2
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> setActiveUser(Map<String, dynamic> userData) async {
    final db = await database;

    // Deactivate all first
    await db.update('local_user', {'is_active': 0});

    // Only use known/safe fields to prevent column errors
    final safeUserData = {
      'user_id': userData['user_id'],
      'email': userData['email'],
      'display_name': userData['display_name'],
      'role': userData['role'] ?? 'guest',
      'stored': userData['stored'], // now allowed
      'is_guest': userData['is_guest'] ?? 0, // now allowed
      'is_active': 1,
    };

    // Insert or replace
    await db.insert(
      'local_user',
      safeUserData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Local user table for guest/offline login
    await db.execute('''
      CREATE TABLE local_user (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT UNIQUE,
        email TEXT,
        display_name TEXT,
        role TEXT DEFAULT 'guest',
        stored TEXT,                      -- Added
        is_guest INTEGER DEFAULT 0,       -- Added
        is_active INTEGER DEFAULT 1
      )
    ''');

    // Products table
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        barcode TEXT UNIQUE,
        price REAL NOT NULL,
        stock INTEGER DEFAULT 0,
        image_path TEXT,
        category TEXT
      )
    ''');

    // Orders table
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT UNIQUE NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        total_amount REAL NOT NULL,
        discount REAL DEFAULT 0,
        tax REAL DEFAULT 0,
        payment_method TEXT,
        status TEXT DEFAULT 'pending',
        created_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Order items
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add missing columns to existing database
      await db.execute('ALTER TABLE local_user ADD COLUMN stored TEXT;');
      await db.execute(
        'ALTER TABLE local_user ADD COLUMN is_guest INTEGER DEFAULT 0;',
      );
    }
  }

  // Insert or update guest user
  Future<void> setGuestUser() async {
    final db = await database;
    await db.insert('local_user', {
      'user_id': 'guest_local_user',
      'email': 'guest@localhost',
      'display_name': 'Guest User',
      'role': 'guest',
      'is_guest': 1,
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Get currently active local user
  Future<Map<String, dynamic>?> getActiveUser() async {
    final db = await database;
    final result = await db.query(
      'local_user',
      where: 'is_active = ?',
      whereArgs: [1],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  // Logout: deactivate all local users
  Future<void> logoutLocal() async {
    final db = await database;
    await db.update('local_user', {'is_active': 0});
  }

  // Optional: full reset
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('order_items');
    await db.delete('orders');
    await db.delete('products');
    await db.delete('local_user');
  }
}
