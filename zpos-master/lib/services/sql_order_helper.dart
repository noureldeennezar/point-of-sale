import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:zpos/classes/MenuItem.dart'; // Ensure Order class is imported

class DBHelper {
  static Database? _database;

  // Initialize the database connection
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDB();
    return _database!;
  }

  // Initialize the database
  Future<Database> initDB() async {
    String path = join(await getDatabasesPath(), 'pos_app.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE orders(
            orderNumber INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE orderItems(
            id INTEGER PRIMARY KEY AUTOINCREMENT, 
            orderNumber INTEGER,
            itemCode TEXT,
            itemName TEXT,
            salesPrice REAL,
            itmGroupCode TEXT,
            quantity INTEGER,
            FOREIGN KEY (orderNumber) REFERENCES orders(orderNumber) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  // Insert the order into the database
  Future<int> insertOrder(Order order) async {
    final db = await database;

    // Insert the order (without items)
    int orderId =
        await db.insert('orders', {'date': DateTime.now().toString()});

    // Insert each item associated with the order
    for (var item in order.items) {
      await db.insert('orderItems', {
        'orderNumber': orderId,
        'itemCode': item.itemCode,
        'itemName': item.itemName,
        'salesPrice': item.salesPrice,
        'itmGroupCode': item.itmGroupCode,
        'quantity': item.quantity,
      });
    }

    return orderId;
  }

  // Fetch orders with their items
  Future<List<Map<String, dynamic>>> fetchOrdersWithItems() async {
    final db = await database;

    try {
      final List<Map<String, dynamic>> orders = await db.rawQuery('''
        SELECT 
          o.orderNumber, 
          o.date, 
          i.itemCode, 
          i.itemName, 
          i.salesPrice, 
          i.quantity 
        FROM orders o
        LEFT JOIN orderItems i ON o.orderNumber = i.orderNumber
        ORDER BY o.orderNumber DESC
      ''');
      return orders; // Return the fetched orders with items
    } catch (e) {
      print("Error fetching orders with items: $e"); // Log the error
      return []; // Return an empty list if an error occurs
    }
  }

  // Delete an item from the order
  Future<void> deleteItem(String itemCode, int orderNumber) async {
    final db = await database;
    try {
      await db.delete('orderItems',
          where: 'itemCode = ? AND orderNumber = ?',
          whereArgs: [itemCode, orderNumber]);
    } catch (e) {
      print("Error deleting item: $e"); // Log the error
    }
  }

  // Clear all data from the database
// Clear all data from the database
  Future<void> clearDatabase() async {
    final db = await database;
    try {
      await db.delete('orderItems'); // Clear order items
      await db.delete('orders'); // Clear orders
      // Reset the orderNumber to start from 1 again
      await db.execute('DELETE FROM sqlite_sequence WHERE name = "orders"');
      print(
          "Database cleared and orderNumber reset."); // Log successful clearing
    } catch (e) {
      print("Error clearing database: $e"); // Log any error
    }
  }
}
