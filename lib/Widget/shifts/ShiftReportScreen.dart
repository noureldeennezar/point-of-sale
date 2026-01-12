import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../Core/app_localizations.dart';
import '../../cloud_services/AuthService.dart';
import '../../local_services/order_db_helper.dart';
import '../../local_services/database_provider.dart';

class ShiftReportScreen extends StatefulWidget {
  const ShiftReportScreen({super.key});

  @override
  _ShiftReportScreenState createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends State<ShiftReportScreen> {
  DateTime? startDate;
  DateTime? endDate;
  bool use24HourFormat = true;

  late final OrderDbHelper _orderDbHelper;
  final DatabaseProvider _dbProvider = DatabaseProvider();

  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _shifts = [];

  @override
  void initState() {
    super.initState();
    _orderDbHelper = OrderDbHelper();
    _loadShifts();
  }

  Future<String> _getEffectiveStoreId() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userData = await authService.currentUserWithRole.first;

      print('AuthService returned: $userData');

      if (userData == null ||
          userData['storeId'] == null ||
          (userData['storeId'] as String?)?.isEmpty == true) {
        print('Guest/Offline mode → fallback to local_store_001');
        return 'local_store_001';
      }

      final storeId = userData['storeId'] as String;
      print('Authenticated storeId: $storeId');
      return storeId;
    } catch (e) {
      print('StoreId fetch error: $e → fallback to local_store_001');
      return 'local_store_001';
    }
  }

  Future<void> _loadShifts() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final storeId = await _getEffectiveStoreId();
    print(
      'Loading shifts for store: $storeId | Date range: $startDate - $endDate',
    );

    final db = await _dbProvider.database;

    String whereClause = 'store_id = ?';
    List<dynamic> whereArgs = [storeId];

    if (startDate != null && endDate != null) {
      whereClause += ' AND startTime >= ? AND startTime <= ?';
      whereArgs.add(startDate!.millisecondsSinceEpoch);
      whereArgs.add(
        endDate!.add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
    }

    try {
      final shiftMaps = await db.query(
        'shifts',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'startTime DESC',
      );

      print('Loaded ${shiftMaps.length} shifts successfully');
      if (mounted) {
        setState(() {
          _shifts = shiftMaps;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Shift load failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Failed to load shifts: $e\n'
              '(Open at least one shift in POS, then come back here)';
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTransactionsForShift(
    String shiftId,
  ) async {
    final storeId = await _getEffectiveStoreId();
    print('Loading transactions for shift $shiftId (store: $storeId)');

    final db = await _dbProvider.database;

    try {
      final txns = await db.query(
        'transactions',
        where: 'shiftId = ? AND store_id = ?',
        whereArgs: [shiftId, storeId],
        orderBy: 'timestamp DESC',
      );
      print('Found ${txns.length} transactions');
      return txns;
    } catch (e) {
      print('Transactions error: $e');
      return [];
    }
  }

  Future<void> _refresh() async {
    await _loadShifts();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && mounted) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
      await _loadShifts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          localizations.translate('shift_reports') ?? 'Shift Reports',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    onPressed: _refresh,
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            startDate == null
                                ? 'Select Date Range'
                                : '${DateFormat('yyyy-MM-dd').format(startDate!)} - ${DateFormat('yyyy-MM-dd').format(endDate!)}',
                          ),
                          onPressed: _selectDateRange,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                        onPressed: () {
                          setState(() {
                            startDate = null;
                            endDate = null;
                          });
                          _loadShifts();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _shifts.isEmpty
                        ? const Center(
                            child: Text(
                              'No shifts found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView.builder(
                              itemCount: _shifts.length,
                              itemBuilder: (context, index) {
                                final shift = _shifts[index];
                                final startTime =
                                    DateTime.fromMillisecondsSinceEpoch(
                                      shift['startTime'] as int,
                                    );
                                final timeFormat = use24HourFormat
                                    ? 'yyyy-MM-dd HH:mm'
                                    : 'yyyy-MM-dd hh:mm a';

                                return Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: ExpansionTile(
                                    title: Text(
                                      '${shift['userName'] ?? 'Guest'} - ${DateFormat(timeFormat).format(startTime)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Status: ${shift['status'] ?? 'unknown'}',
                                    ),
                                    childrenPadding: const EdgeInsets.all(16),
                                    children: [
                                      FutureBuilder<List<Map<String, dynamic>>>(
                                        future: _fetchTransactionsForShift(
                                          shift['id'] as String,
                                        ),
                                        builder: (ctx, txnSnap) {
                                          if (txnSnap.connectionState ==
                                              ConnectionState.waiting) {
                                            return const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            );
                                          }
                                          final txns = txnSnap.data ?? [];
                                          return Text(
                                            'Transactions: ${txns.length}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
