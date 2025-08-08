import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../local_services/ItemDatabaseHelper.dart';
import '../models/Order.dart';

class OrderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ItemDatabaseHelper _itemDbHelper = ItemDatabaseHelper();

  Future<void> addOrUpdateOrder(Order order, String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      bool isOnline = connectivityResult != ConnectivityResult.none;

      await _itemDbHelper.insertOrder(order, storeId);

      if (isOnline) {
        try {
          await _firestore
              .collection('stores')
              .doc(storeId)
              .collection('orders')
              .doc(order.orderNumber.toString())
              .set(order.toMap());
          await _itemDbHelper.clearOrderSyncQueue(order.orderNumber.toString(), storeId);
        } catch (e) {
          await _itemDbHelper.queueOrderForSync(order, 'addOrUpdate', storeId);
          rethrow;
        }
      } else {
        await _itemDbHelper.queueOrderForSync(order, 'addOrUpdate', storeId);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getOrders(String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return await _itemDbHelper.fetchOrdersWithItems(storeId);
      }

      final snapshot =
      await _firestore.collection('stores').doc(storeId).collection('orders').get();
      final orders = snapshot.docs.map((doc) => Order.fromMap(doc.data())).toList();

      for (var order in orders) {
        await _itemDbHelper.insertOrder(order, storeId);
      }

      return await _itemDbHelper.fetchOrdersWithItems(storeId);
    } catch (e) {
      return await _itemDbHelper.fetchOrdersWithItems(storeId);
    }
  }
}