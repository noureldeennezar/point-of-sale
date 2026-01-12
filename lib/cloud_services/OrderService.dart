import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/Order.dart' as OrderModel;

class OrderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Adds or updates a single order in Firestore
  Future<void> addOrUpdateOrder(OrderModel.Order order, String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('No internet - order sync queued locally');
        throw Exception(
          'No internet connection. Order will be queued locally.',
        );
      }

      await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('orders')
          .doc(order.orderNumber.toString())
          .set(order.toMap(), SetOptions(merge: true));

      debugPrint('Order ${order.orderNumber} synced to Firestore successfully');
    } catch (e) {
      debugPrint('OrderService - addOrUpdateOrder failed: $e');
      rethrow;
    }
  }

  /// Fetches all orders for a store from Firestore
  Future<List<Map<String, dynamic>>> getOrders(String storeId) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        throw Exception('No internet connection. Cannot fetch orders offline.');
      }

      final snapshot = await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('orders')
          .orderBy('date', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Useful for referencing the document
        return data;
      }).toList();
    } catch (e) {
      debugPrint('OrderService - getOrders failed: $e');
      rethrow;
    }
  }

  /// Bulk sync multiple local orders to Firestore (useful for manual sync or recovery)
  Future<void> syncMultipleOrders(
    List<OrderModel.Order> orders,
    String storeId,
  ) async {
    if (orders.isEmpty) return;

    final batch = _firestore.batch();

    for (final order in orders) {
      final ref = _firestore
          .collection('stores')
          .doc(storeId)
          .collection('orders')
          .doc(order.orderNumber.toString());

      batch.set(ref, order.toMap(), SetOptions(merge: true));
    }

    try {
      await batch.commit();
      debugPrint(
        'Bulk sync completed: ${orders.length} orders for store $storeId',
      );
    } catch (e) {
      debugPrint('Bulk order sync failed: $e');
      rethrow;
    }
  }
}
