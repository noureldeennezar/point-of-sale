import 'package:sqflite/sqflite.dart';

import '../models/ProductCategory.dart';
import 'database_provider.dart';

class CategoryDbHelper {
  static final CategoryDbHelper _instance = CategoryDbHelper._internal();

  factory CategoryDbHelper() => _instance;

  CategoryDbHelper._internal();

  final DatabaseProvider _dbProvider = DatabaseProvider();

  // Important: public getter for SyncService
  Future<Database> get database => _dbProvider.database;

  Future<List<ProductCategory>> getCategories(String storeId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    return List.generate(maps.length, (i) => ProductCategory.fromMap(maps[i]));
  }

  Future<void> insertCategory(
    ProductCategory category,
    String storeId, {
    Transaction? txn,
  }) async {
    final db = txn ?? await database;
    await db.insert('categories', {
      ...category.toMap(),
      'store_id': storeId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCategory(String categoryCode, String storeId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'items',
        where: 'itm_group_code = ? AND store_id = ?',
        whereArgs: [categoryCode, storeId],
      );
      await txn.delete(
        'order_items',
        where: 'itm_group_code = ? AND store_id = ?',
        whereArgs: [categoryCode, storeId],
      );
      await txn.delete(
        'categories',
        where: 'category_code = ? AND store_id = ?',
        whereArgs: [categoryCode, storeId],
      );
      await txn.delete(
        'categories',
        where: 'main_group = ? AND store_id = ?',
        whereArgs: [categoryCode, storeId],
      );
    });
  }

  // Used by sync service — uses correct column name
  Future<void> clearAllCategories(String storeId) async {
    final db = await database;
    await db.delete('categories', where: 'store_id = ?', whereArgs: [storeId]);
  }

  // You can keep this if needed, but clearAllCategories is enough for sync
  Future<void> clearCategories(String storeId) async =>
      clearAllCategories(storeId);
}
