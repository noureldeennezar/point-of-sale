import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../Core/app_localizations.dart';

class ShiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Database? _database;
  BuildContext? _context;

  ShiftService({BuildContext? context}) {
    _firestore.settings = const Settings(persistenceEnabled: true);
    _context = context;
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    _database = await openDatabase(
      'pos_offline.db',
      version: 2,
      onCreate: (db, version) {
        db.execute(
          'CREATE TABLE offline_queue (id TEXT PRIMARY KEY, action TEXT, data TEXT, timestamp INTEGER, store_id TEXT)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS offline_queue');
          await db.execute(
            'CREATE TABLE offline_queue (id TEXT PRIMARY KEY, action TEXT, data TEXT, timestamp INTEGER, store_id TEXT)',
          );
        }
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
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // ──────────────────────────────────────────────────────────────
  //                   OPEN SHIFT
  // ──────────────────────────────────────────────────────────────
  Future<String?> openShift(String storeId) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userName = userDoc.exists
        ? userDoc['displayName'] ?? user.email
        : user.email;

    final shiftData = {
      'userId': user.uid,
      'userName': userName,
      'startTime': FieldValue.serverTimestamp(),
      'status': 'open',
      'transactions': [],
      'finalCashCount': null,
      'storeId': storeId,
    };

    try {
      if (await isOnline()) {
        final shiftRef = await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('shifts')
            .add(shiftData);
        return shiftRef.id;
      } else {
        final db = await getDatabase();
        if (db == null) throw Exception('Database not initialized');
        final shiftId = DateTime.now().millisecondsSinceEpoch.toString();
        await db.insert('offline_queue', {
          'id': shiftId,
          'action': 'open_shift',
          'data': jsonEncode(shiftData),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'store_id': storeId,
        });
        return shiftId;
      }
    } catch (e) {
      _showError('failed_to_open_shift', e);
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────
  //                   CLOSE SHIFT
  // ──────────────────────────────────────────────────────────────
  Future<bool> closeShift(
    String shiftId,
    String storeId, {
    double? finalCashCount,
  }) async {
    final updateData = {
      'endTime': FieldValue.serverTimestamp(),
      'status': 'closed',
      if (finalCashCount != null) 'finalCashCount': finalCashCount,
    };

    try {
      if (await isOnline()) {
        await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('shifts')
            .doc(shiftId)
            .update(updateData);
        return true;
      } else {
        final db = await getDatabase();
        if (db == null) throw Exception('Database not initialized');
        await db.insert('offline_queue', {
          'id': '$shiftId-close',
          'action': 'close_shift',
          'data': jsonEncode({'shiftId': shiftId, ...updateData}),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'store_id': storeId,
        });
        return true;
      }
    } catch (e) {
      _showError('failed_to_close_shift', e);
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────
  //                   ADD TRANSACTION
  // ──────────────────────────────────────────────────────────────
  Future<String?> addTransaction({
    required String shiftId,
    required String storeId,
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
      'storeId': storeId,
    };

    try {
      if (await isOnline()) {
        final txnRef = await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('transactions')
            .add(transactionData);

        await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('shifts')
            .doc(shiftId)
            .update({
              'transactions': FieldValue.arrayUnion([txnRef.id]),
            });

        return txnRef.id;
      } else {
        final db = await getDatabase();
        if (db == null) throw Exception('Database not initialized');
        final txnId = DateTime.now().millisecondsSinceEpoch.toString();
        await db.insert('offline_queue', {
          'id': txnId,
          'action': 'add_transaction',
          'data': jsonEncode({'shiftId': shiftId, ...transactionData}),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'store_id': storeId,
        });
        return txnId;
      }
    } catch (e) {
      _showError('failed_to_add_transaction', e);
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────
  //                   SYNC OFFLINE SHIFTS
  // ──────────────────────────────────────────────────────────────
  Future<void> syncOfflineShifts(String storeId) async {
    final db = await getDatabase();
    if (db == null) {
      _showErrorMessage('database_not_initialized');
      return;
    }

    if (!await isOnline()) return;

    final batch = _firestore.batch();
    final queueItems = await db.query(
      'offline_queue',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );

    for (var item in queueItems) {
      final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;
      final itemId = item['id'] as String;

      switch (item['action']) {
        case 'open_shift':
          batch.set(
            _firestore
                .collection('stores')
                .doc(storeId)
                .collection('shifts')
                .doc(itemId),
            data,
          );
          break;
        case 'close_shift':
          batch.update(
            _firestore
                .collection('stores')
                .doc(storeId)
                .collection('shifts')
                .doc(data['shiftId']),
            data,
          );
          break;
        case 'add_transaction':
          final shiftId = data['shiftId'] as String;
          final txnId = itemId;
          batch.set(
            _firestore
                .collection('stores')
                .doc(storeId)
                .collection('transactions')
                .doc(txnId),
            data,
          );
          batch.update(
            _firestore
                .collection('stores')
                .doc(storeId)
                .collection('shifts')
                .doc(shiftId),
            {
              'transactions': FieldValue.arrayUnion([txnId]),
            },
          );
          break;
      }

      await db.delete(
        'offline_queue',
        where: 'id = ? AND store_id = ?',
        whereArgs: [itemId, storeId],
      );
    }

    try {
      await batch.commit();
      _showSuccessMessage('offline_shifts_synced');
    } catch (e) {
      _showError('failed_to_sync_shifts', e);
    }
  }

  // ──────────────────────────────────────────────────────────────
  //                   HELPERS
  // ──────────────────────────────────────────────────────────────
  void _showError(String key, dynamic error) {
    if (_context != null && _context!.mounted) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              _context!,
            ).translate(key, params: {'error': error.toString()}),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showErrorMessage(String key) {
    if (_context != null && _context!.mounted) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(_context!).translate(key)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showSuccessMessage(String key) {
    if (_context != null && _context!.mounted) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(_context!).translate(key)),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }

  // Keep your existing methods (getActiveShift, getShifts, etc.) as they are...
}
