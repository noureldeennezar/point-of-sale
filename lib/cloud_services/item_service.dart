import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/ProductCategory.dart';
import '../models/Item.dart';

class ItemService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addOrUpdateItem(Item item, String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        // We allow local save even offline → don't throw here
        print('Offline: Item update will be synced later');
        return;
      }

      await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('items')
          .doc(item.itemCode)
          .set(item.toMap());
    } catch (e) {
      print('Cloud item save failed: $e');
      rethrow;
    }
  }

  Future<void> addOrUpdateCategory(ProductCategory category, String storeId) async {
    // similar pattern...
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return;

      await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('categories')
          .doc(category.categoryCode)
          .set(category.toMap());
    } catch (e) {
      print('Cloud category save failed: $e');
    }
  }

  Future<List<Item>> getItems(String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        throw Exception('Offline mode - cannot fetch from cloud');
      }

      final snapshot = await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('items')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Item.fromMap({
          ...data,
          'item_code': doc.id, // important if you use doc.id as itemCode
        });
      }).toList();
    } catch (e) {
      print('Cloud items fetch failed: $e');
      rethrow;
    }
  }

// getCategories(...) remains similar
}