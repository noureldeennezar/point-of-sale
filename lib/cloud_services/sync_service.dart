import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../cloud_services/AuthService.dart';
import '../local_services/category_db_helper.dart';
import '../local_services/item_db_helper.dart';
import '../local_services/order_db_helper.dart';
import '../local_services/shift_db_helper.dart';
import '../models/ProductCategory.dart';
import '../models/Item.dart';
import '../models/Order.dart' as OrderModel;

class SyncService {
  final BuildContext context;

  final CategoryDbHelper categoryDb;
  final ItemDbHelper itemDb;
  final OrderDbHelper orderDb;
  final ShiftDbHelper shiftDb;

  SyncService({
    required this.context,
    CategoryDbHelper? categoryDb,
    ItemDbHelper? itemDb,
    OrderDbHelper? orderDb,
    ShiftDbHelper? shiftDb,
  }) : categoryDb = categoryDb ?? CategoryDbHelper(),
       itemDb = itemDb ?? ItemDbHelper(),
       orderDb = orderDb ?? OrderDbHelper(),
       shiftDb = shiftDb ?? ShiftDbHelper();

  /// Uploads all local data → overwrites cloud version for current user/store
  Future<bool> performFullLocalToCloudSync() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userData = await authService.currentUserWithRole.first;

    if (userData == null) {
      debugPrint("Sync blocked: No authenticated user");
      return false;
    }

    final uid = userData['uid'] as String? ?? '';
    final storeId = userData['storeId'] as String? ?? '';

    if (uid.isEmpty || storeId.isEmpty) {
      debugPrint("Sync blocked: Missing uid or storeId");
      return false;
    }

    try {
      final categories = await categoryDb.getCategories(storeId);
      final items = await itemDb.getItems(storeId);
      final orders = await orderDb.getAllOrders(storeId);
      final shifts = await shiftDb.getAllShifts(storeId);

      final syncData = {
        'lastSync': FieldValue.serverTimestamp(),
        'uid': uid,
        'storeId': storeId,
        'metadata': {
          'syncTime': DateTime.now().toIso8601String(),
          'platform': defaultTargetPlatform.toString(),
        },
        'categories': categories.map((c) => c.toMap()).toList(),
        'items': items.map((i) => i.toMap()).toList(),
        'orders': orders.map((o) => o.toMap()).toList(),
        'shifts': shifts,
      };

      await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('users')
          .doc(uid)
          .set(syncData, SetOptions(merge: false));

      debugPrint("→ Full local → cloud sync completed for $uid / $storeId");
      return true;
    } catch (e, stack) {
      debugPrint("Local → Cloud sync failed:\n$e\n$stack");
      return false;
    }
  }

  /// **DANGEROUS** — Completely replaces local data with cloud version
  /// Use only after strong user confirmation!
  Future<bool> performFullCloudToLocalReplace() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userData = await authService.currentUserWithRole.first;

    if (userData == null) {
      debugPrint("Cloud → Local blocked: No authenticated user");
      return false;
    }

    final uid = userData['uid'] as String? ?? '';
    final storeId = userData['storeId'] as String? ?? '';

    if (uid.isEmpty || storeId.isEmpty) {
      debugPrint("Cloud → Local blocked: Missing uid or storeId");
      return false;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('users')
          .doc(uid);

      final snapshot = await docRef.get(
        const GetOptions(source: Source.serverAndCache),
      );

      if (!snapshot.exists || snapshot.data() == null) {
        debugPrint("No cloud data found for $uid / $storeId");
        return false;
      }

      final cloudData = snapshot.data()!;

      final categories = cloudData['categories'];
      final items = cloudData['items'];
      final orders = cloudData['orders'];
      final shifts = cloudData['shifts'];

      if (categories is! List ||
          items is! List ||
          orders is! List ||
          shifts is! List) {
        debugPrint("Invalid cloud data structure");
        return false;
      }

      debugPrint("→ Starting full local WIPE for store $storeId...");

      await categoryDb.clearAllCategories(storeId);
      await itemDb.clearAllItems(storeId);
      await orderDb.clearAllOrders(storeId);
      await shiftDb.clearAllShifts(storeId);

      debugPrint("→ Restoring from cloud...");

      // Categories
      final catDb = await categoryDb.database;
      await catDb.transaction((txn) async {
        for (final map in categories.cast<Map<String, dynamic>>()) {
          await categoryDb.insertCategory(
            ProductCategory.fromMap(map),
            storeId,
            txn: txn,
          );
        }
      });

      // Items
      final itemDbInstance = await itemDb.database;
      await itemDbInstance.transaction((txn) async {
        for (final map in items.cast<Map<String, dynamic>>()) {
          await itemDb.insertItem(Item.fromMap(map), storeId, txn: txn);
        }
      });

      // Orders
      final orderDbInstance = await orderDb.database;
      await orderDbInstance.transaction((txn) async {
        for (final map in orders.cast<Map<String, dynamic>>()) {
          await orderDb.insertOrder(
            OrderModel.Order.fromMap(map),
            storeId,
            txn: txn,
          );
        }
      });

      // Shifts
      final shiftDbInstance = await shiftDb.database;
      await shiftDbInstance.transaction((txn) async {
        for (final map in shifts.cast<Map<String, dynamic>>()) {
          await shiftDb.insertShiftFromMap(map, storeId, txn: txn);
        }
      });

      debugPrint("→ Full cloud → local replace completed successfully!");
      return true;
    } catch (e, stack) {
      debugPrint("Cloud → Local replace FAILED:\n$e\n$stack");
      return false;
    }
  }
}
