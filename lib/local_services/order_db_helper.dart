import 'package:sqflite/sqflite.dart';

import '../../models/Order.dart' as OrderModel;
import '../models/Item.dart';
import 'database_provider.dart';

class OrderDbHelper {
  static final OrderDbHelper _instance = OrderDbHelper._internal();

  factory OrderDbHelper() => _instance;

  OrderDbHelper._internal();

  final DatabaseProvider _dbProvider = DatabaseProvider();

  Future<Database> get database => _dbProvider.database;

  /// Fixed: Proper transaction support for both normal & sync usage
  Future<int> insertOrder(
    OrderModel.Order order,
    String storeId, {
    Transaction? txn,
  }) async {
    // If we already have a transaction (from sync), use it directly
    if (txn != null) {
      return await _insertOrderInTransaction(txn, order, storeId);
    }

    // Otherwise, start a new transaction
    final db = await database;
    return await db.transaction((newTxn) async {
      return await _insertOrderInTransaction(newTxn, order, storeId);
    });
  }

  /// Internal helper: actual insert logic (used by both paths)
  Future<int> _insertOrderInTransaction(
    Transaction txn,
    OrderModel.Order order,
    String storeId,
  ) async {
    final int orderId = await txn.insert('orders', {
      'date': order.date,
      'store_id': storeId,
    });

    for (var item in order.items) {
      await txn.insert('order_items', {
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

  Future<List<OrderModel.Order>> getAllOrders(String storeId) async {
    final db = await database;

    final orderMaps = await db.query(
      'orders',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );

    final List<OrderModel.Order> orders = [];

    for (final orderMap in orderMaps) {
      final orderNumber = orderMap['orderNumber'] as int;
      final date = orderMap['date'] as String;

      final itemMaps = await db.query(
        'order_items',
        where: 'orderNumber = ? AND store_id = ?',
        whereArgs: [orderNumber, storeId],
      );

      final items = itemMaps
          .map(
            (m) => Item(
              itemCode: m['item_code'] as String,
              itemName: m['item_name'] as String,
              salesPrice: (m['sales_price'] as num).toDouble(),
              itmGroupCode: m['itm_group_code'] as String,
              barcode: m['barcode'] as String?,
              isActive: (m['is_active'] as int) == 1,
              quantity: m['quantity'] as int,
            ),
          )
          .toList();

      orders.add(OrderModel.Order(items: items, date: date));
    }

    return orders;
  }

  /// Sync-required method — fixed column name + transaction
  Future<void> clearAllOrders(String storeId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'order_items',
        where: 'store_id = ?',
        whereArgs: [storeId],
      );
      await txn.delete('orders', where: 'store_id = ?', whereArgs: [storeId]);
    });
  }

  // ─────────────── Other methods (unchanged) ───────────────
  Future<List<Map<String, dynamic>>> fetchOrdersWithItems(
    String storeId,
  ) async {
    final db = await database;
    return await db.rawQuery(
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
      [storeId],
    );
  }

  Future<int> getLatestOrderId(String storeId) async {
    final db = await database;
    final result = await db.query(
      'orders',
      columns: ['orderNumber'],
      where: 'store_id = ?',
      whereArgs: [storeId],
      orderBy: 'orderNumber DESC',
      limit: 1,
    );
    return result.isNotEmpty ? result.first['orderNumber'] as int : 0;
  }
}
