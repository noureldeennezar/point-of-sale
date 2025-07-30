import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../Core/app_localizations.dart'; // Added for error messages

class ShiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Database? _database;
  BuildContext? _context; // Added to allow showing SnackBar in syncOfflineShifts

  ShiftService({BuildContext? context}) {
    _firestore.settings = const Settings(persistenceEnabled: true);
    _context = context;
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    _database = await openDatabase(
      'pos_offline.db',
      version: 1,
      onCreate: (db, version) {
        db.execute(
          'CREATE TABLE offline_queue (id TEXT PRIMARY KEY, action TEXT, data TEXT, timestamp INTEGER)',
        );
      },
    );
  }

  Future<Database?> getDatabase() async {
    if (_database == null) {
      await _initDatabase();
    }
    return _database;
  }

  Future<bool> isOnline() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> fixExistingShift(String shiftId) async {
    try {
      await _firestore.collection('shifts').doc(shiftId).update({
        'transactions': [],
      });
    } catch (e) {
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(_context!)
                .translate('failed_to_fix_shift', params: {'error': e.toString()})),
          ),
        );
      }
    }
  }

  Future<String?> openShift() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userName = userDoc.exists ? userDoc['displayName'] : user.email;

    final shiftData = {
      'userId': user.uid,
      'userName': userName,
      'startTime': FieldValue.serverTimestamp(),
      'status': 'open',
      'transactions': [],
      'finalCashCount': null,
    };

    try {
      if (await isOnline()) {
        DocumentReference shiftRef = await _firestore.collection('shifts').add(shiftData);
        return shiftRef.id;
      } else {
        final db = await getDatabase();
        if (db == null) throw Exception('Database not initialized');
        String shiftId = DateTime.now().millisecondsSinceEpoch.toString();
        await db.insert('offline_queue', {
          'id': shiftId,
          'action': 'open_shift',
          'data': jsonEncode(shiftData),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return shiftId;
      }
    } catch (e) {
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(_context!)
                .translate('failed_to_open_shift', params: {'error': e.toString()})),
          ),
        );
      }
      return null;
    }
  }

  Future<bool> closeShift(String shiftId, {double? finalCashCount}) async {
    final updateData = {
      'endTime': FieldValue.serverTimestamp(),
      'status': 'closed',
      'finalCashCount': finalCashCount,
    };

    try {
      if (await isOnline()) {
        await _firestore.collection('shifts').doc(shiftId).update(updateData);
        return true;
      } else {
        final db = await getDatabase();
        if (db == null) throw Exception('Database not initialized');
        await db.insert('offline_queue', {
          'id': '$shiftId-close',
          'action': 'close_shift',
          'data': jsonEncode({'shiftId': shiftId, ...updateData}),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return true;
      }
    } catch (e) {
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(_context!)
                .translate('failed_to_close_shift', params: {'error': e.toString()})),
          ),
        );
      }
      return false;
    }
  }

  Future<String?> addTransaction({
    required String shiftId,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double serviceCharge,
    required double tax,
    required double total,
    required String paymentMethod,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final transactionData = {
      'shiftId': shiftId,
      'userId': user.uid,
      'items': items,
      'subtotal': subtotal,
      'serviceCharge': serviceCharge,
      'tax': tax,
      'total': total,
      'paymentMethod': paymentMethod,
      'timestamp': FieldValue.serverTimestamp(),
    };

    try {
      if (await isOnline()) {
        DocumentReference txnRef = await _firestore.collection('transactions').add(transactionData);
        await _firestore.collection('shifts').doc(shiftId).update({
          'transactions': FieldValue.arrayUnion([txnRef.id]),
        });
        return txnRef.id;
      } else {
        final db = await getDatabase();
        if (db == null) throw Exception('Database not initialized');
        String txnId = DateTime.now().millisecondsSinceEpoch.toString();
        await db.insert('offline_queue', {
          'id': txnId,
          'action': 'add_transaction',
          'data': jsonEncode({'shiftId': shiftId, ...transactionData}),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return txnId;
      }
    } catch (e) {
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(_context!)
                .translate('failed_to_add_transaction', params: {'error': e.toString()})),
          ),
        );
      }
      return null;
    }
  }

  Future<void> syncOfflineShifts() async {
    final db = await getDatabase();
    if (db == null) {
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(_context!).translate('database_not_initialized')),
          ),
        );
      }
      return;
    }

    if (await isOnline()) {
      final batch = _firestore.batch();
      final queueItems = await db.query('offline_queue');
      for (var item in queueItems) {
        final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;
        final itemId = item['id'] as String;
        switch (item['action']) {
          case 'open_shift':
            batch.set(_firestore.collection('shifts').doc(itemId), data);
            break;
          case 'close_shift':
            batch.update(_firestore.collection('shifts').doc(data['shiftId'] as String), data);
            break;
          case 'add_transaction':
            String shiftId = data['shiftId'];
            batch.set(_firestore.collection('transactions').doc(itemId), data);
            batch.update(_firestore.collection('shifts').doc(shiftId), {
              'transactions': FieldValue.arrayUnion([itemId]),
            });
            break;
        }
        await db.delete('offline_queue', where: 'id = ?', whereArgs: [itemId]);
      }
      try {
        await batch.commit();
        if (_context != null && _context!.mounted) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(_context!).translate('offline_shifts_synced')),
            ),
          );
        }
      } catch (e) {
        if (_context != null && _context!.mounted) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(_context!)
                  .translate('failed_to_sync_shifts', params: {'error': e.toString()})),
            ),
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>?> getActiveShift() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final query = await _firestore
          .collection('shifts')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'open')
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return {'id': query.docs.first.id, ...query.docs.first.data()};
      }
      return null;
    } catch (e) {
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(_context!)
                .translate('failed_to_get_active_shift', params: {'error': e.toString()})),
          ),
        );
      }
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getShifts({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore.collection('shifts');
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }
      if (startDate != null) {
        query = query.where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }
      final result = await query.get();
      return result.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();
    } catch (e) {
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(_context!)
                .translate('failed_to_load_shifts', params: {'error': e.toString()})),
          ),
        );
      }
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> getShiftsStream({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    Query query = _firestore.collection('shifts');
    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }
    if (startDate != null) {
      query = query.where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }
    // Sort by startTime in descending order (newest first)
    query = query.orderBy('startTime', descending: true);
    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
        .toList());
  }

  Future<List<Map<String, dynamic>>> getShiftTransactions(String shiftId) async {
    try {
      final result = await _firestore
          .collection('transactions')
          .where('shiftId', isEqualTo: shiftId)
          .get();
      return result.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(_context!)
                .translate('failed_to_load_transactions', params: {'error': e.toString()})),
          ),
        );
      }
      return [];
    }
  }
}