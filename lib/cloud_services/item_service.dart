import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../local_services/ItemDatabaseHelper.dart';
import '../models/Category.dart';
import '../models/Item.dart';

class ItemService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ItemDatabaseHelper _itemDbHelper = ItemDatabaseHelper();

  Future<void> addOrUpdateItem(Item item, String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      bool isOnline = connectivityResult != ConnectivityResult.none;

      await _itemDbHelper.insertOrUpdateItem(item, storeId);

      if (isOnline) {
        try {
          await _firestore
              .collection('stores')
              .doc(storeId)
              .collection('items')
              .doc(item.itemCode)
              .set(item.toMap());
          await _itemDbHelper.clearSyncQueue(item.itemCode, storeId);
        } catch (e) {
          await _itemDbHelper.queueItemForSync(item, 'addOrUpdate', storeId);
          rethrow;
        }
      } else {
        await _itemDbHelper.queueItemForSync(item, 'addOrUpdate', storeId);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addOrUpdateCategory(Category category, String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      bool isOnline = connectivityResult != ConnectivityResult.none;

      await _itemDbHelper.insertOrUpdateCategory(category, storeId);

      if (isOnline) {
        try {
          await _firestore
              .collection('stores')
              .doc(storeId)
              .collection('categories')
              .doc(category.categoryCode)
              .set(category.toMap());
          await _itemDbHelper.clearCategorySyncQueue(category.categoryCode, storeId);
        } catch (e) {
          await _itemDbHelper.queueCategoryForSync(category, 'addOrUpdate', storeId);
          rethrow;
        }
      } else {
        await _itemDbHelper.queueCategoryForSync(category, 'addOrUpdate', storeId);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> syncOfflineItems(String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return;

      final queue = await _itemDbHelper.getSyncQueue(storeId);
      for (var entry in queue) {
        try {
          final itemData = jsonDecode(entry['item_data']);
          final item = Item.fromMap(itemData);
          final operation = entry['operation'];
          if (operation == 'addOrUpdate') {
            await _firestore
                .collection('stores')
                .doc(storeId)
                .collection('items')
                .doc(item.itemCode)
                .set(item.toMap());
          } else if (operation == 'delete') {
            await _firestore
                .collection('stores')
                .doc(storeId)
                .collection('items')
                .doc(item.itemCode)
                .delete();
          }
          await _itemDbHelper.clearSyncQueue(item.itemCode, storeId);
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> syncOfflineCategories(String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return;

      final queue = await _itemDbHelper.getCategorySyncQueue(storeId);
      for (var entry in queue) {
        try {
          final categoryData = jsonDecode(entry['category_data']);
          final category = Category.fromMap(categoryData);
          await _firestore
              .collection('stores')
              .doc(storeId)
              .collection('categories')
              .doc(category.categoryCode)
              .set(category.toMap());
          await _itemDbHelper.clearCategorySyncQueue(category.categoryCode, storeId);
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Item>> getItems(String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return await _itemDbHelper.getItems(storeId);
      }

      final snapshot =
      await _firestore.collection('stores').doc(storeId).collection('items').get();
      final items = snapshot.docs.map((doc) => Item.fromMap(doc.data())).toList();

      for (var item in items) {
        await _itemDbHelper.insertOrUpdateItem(item, storeId);
      }

      return items;
    } catch (e) {
      return await _itemDbHelper.getItems(storeId);
    }
  }

  Future<List<Category>> getCategories(String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return await _itemDbHelper.getItemGroups(storeId);
      }

      final snapshot = await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('categories')
          .get();
      final categories = snapshot.docs.map((doc) => Category.fromMap(doc.data())).toList();

      for (var category in categories) {
        await _itemDbHelper.insertOrUpdateCategory(category, storeId);
      }

      return categories;
    } catch (e) {
      return await _itemDbHelper.getItemGroups(storeId);
    }
  }
}