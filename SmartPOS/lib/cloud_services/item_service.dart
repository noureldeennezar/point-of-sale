import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../local_services/ItemDatabaseHelper.dart';
import '../models/Catgeory.dart';
import '../models/Item.dart';

class ItemService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ItemDatabaseHelper _itemDbHelper = ItemDatabaseHelper();

  Future<void> addOrUpdateItem(Item item) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      bool isOnline = connectivityResult != ConnectivityResult.none;

      // Insert or update item in local database
      await _itemDbHelper.insertOrUpdateItem(item);

      if (isOnline) {
        try {
          await _firestore.collection('items').doc(item.itemCode).set(item.toMap());
          await _itemDbHelper.clearSyncQueue(item.itemCode);
        } catch (e) {
          await _itemDbHelper.queueItemForSync(item, 'addOrUpdate');
          rethrow;
        }
      } else {
        await _itemDbHelper.queueItemForSync(item, 'addOrUpdate');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addOrUpdateCategory(Category category) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      bool isOnline = connectivityResult != ConnectivityResult.none;

      // Insert or update category in local database
      await _itemDbHelper.insertOrUpdateCategory(category);

      if (isOnline) {
        try {
          await _firestore.collection('categories').doc(category.categoryCode).set(category.toMap());
          await _itemDbHelper.clearCategorySyncQueue(category.categoryCode);
        } catch (e) {
          await _itemDbHelper.queueCategoryForSync(category, 'addOrUpdate');
          rethrow;
        }
      } else {
        await _itemDbHelper.queueCategoryForSync(category, 'addOrUpdate');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> syncOfflineItems() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return;

      final queue = await _itemDbHelper.getSyncQueue();
      for (var entry in queue) {
        try {
          final itemData = jsonDecode(entry['item_data']);
          final item = Item.fromMap(itemData);
          final operation = entry['operation'];
          if (operation == 'addOrUpdate') {
            await _firestore.collection('items').doc(item.itemCode).set(item.toMap());
          } else if (operation == 'delete') {
            await _firestore.collection('items').doc(item.itemCode).delete();
          }
          await _itemDbHelper.clearSyncQueue(item.itemCode);
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> syncOfflineCategories() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return;

      final queue = await _itemDbHelper.getCategorySyncQueue();
      for (var entry in queue) {
        try {
          final categoryData = jsonDecode(entry['category_data']);
          final category = Category.fromMap(categoryData);
          await _firestore.collection('categories').doc(category.categoryCode).set(category.toMap());
          await _itemDbHelper.clearCategorySyncQueue(category.categoryCode);
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Item>> getItems() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return await _itemDbHelper.getItems();
      }

      final snapshot = await _firestore.collection('items').get();
      final items = snapshot.docs.map((doc) => Item.fromMap(doc.data())).toList();

      for (var item in items) {
        await _itemDbHelper.insertOrUpdateItem(item);
      }

      return items;
    } catch (e) {
      return await _itemDbHelper.getItems();
    }
  }

  Future<List<Category>> getCategories() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return await _itemDbHelper.getItemGroups();
      }

      final snapshot = await _firestore.collection('categories').get();
      final categories = snapshot.docs.map((doc) => Category.fromMap(doc.data())).toList();

      for (var category in categories) {
        await _itemDbHelper.insertOrUpdateCategory(category);
      }

      return categories;
    } catch (e) {
      return await _itemDbHelper.getItemGroups();
    }
  }
}