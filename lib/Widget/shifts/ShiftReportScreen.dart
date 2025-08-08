import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../Core/app_localizations.dart';
import '../../cloud_services/AuthService.dart';
import '../../cloud_services/shift_service.dart';

class ShiftReportScreen extends StatefulWidget {
  const ShiftReportScreen({super.key});

  @override
  _ShiftReportScreenState createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends State<ShiftReportScreen> {
  final ShiftService _shiftService =
      ShiftService(context: null); // Context set in build
  String? selectedUserId;
  DateTime? startDate;
  DateTime? endDate;
  bool use24HourFormat = true; // Default to 24-hour format

  @override
  void initState() {
    super.initState();
    // Initialize Firestore settings to ensure main thread usage
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Theme.of(context).colorScheme.primary,
                  surface: Theme.of(context).colorScheme.surface,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shiftServiceWithContext = ShiftService(context: context);

    return StreamBuilder<Map<String, dynamic>?>(
      stream:
          Provider.of<AuthService>(context, listen: false).currentUserWithRole,
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (userSnapshot.hasError || userSnapshot.data == null) {
          return SafeArea(
            child: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              appBar: AppBar(
                title: Text(
                  localizations.translate('shift_reports'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                backgroundColor: theme.colorScheme.surface,
                elevation: 0,
                centerTitle: true,
              ),
              body: Center(
                child: Text(
                  localizations.translate('error_loading_user_data'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          );
        }

        final storeId = userSnapshot.data!['storeId'] as String? ?? '';
        if (storeId.isEmpty) {
          return SafeArea(
            child: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              appBar: AppBar(
                title: Text(
                  localizations.translate('shift_reports'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                backgroundColor: theme.colorScheme.surface,
                elevation: 0,
                centerTitle: true,
              ),
              body: Center(
                child: Text(
                  localizations.translate('no_store_id'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          );
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: shiftServiceWithContext.getShiftsStream(
            userId: selectedUserId,
            startDate: startDate,
            endDate: endDate,
            storeId: storeId,
          ),
          builder: (context, shiftSnapshot) {
            final isLoading =
                shiftSnapshot.connectionState == ConnectionState.waiting;

            if (shiftSnapshot.hasError) {
              return SafeArea(
                child: Scaffold(
                  backgroundColor: theme.colorScheme.surface,
                  appBar: AppBar(
                    title: Text(
                      localizations.translate('shift_reports'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    backgroundColor: theme.colorScheme.surface,
                    elevation: 0,
                    centerTitle: true,
                  ),
                  body: Center(
                    child: Text(
                      localizations.translate('failed_to_load_shifts'),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              );
            }

            final shifts = shiftSnapshot.data ?? [];

            return SafeArea(
              child: Scaffold(
                backgroundColor: theme.colorScheme.surface,
                appBar: AppBar(
                  title: Text(
                    localizations.translate('shift_reports'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  backgroundColor: theme.colorScheme.surface,
                  elevation: 0,
                  centerTitle: true,
                ),
                body: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _selectDateRange(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: Text(
                                startDate == null
                                    ? localizations
                                        .translate('select_date_range')
                                    : '${DateFormat('yyyy-MM-dd').format(startDate!)} - ${DateFormat('yyyy-MM-dd').format(endDate!)}',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedUserId = null;
                                  startDate = null;
                                  endDate = null;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: Text(
                                localizations.translate('clear_filters'),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  use24HourFormat = !use24HourFormat;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: Text(
                                localizations.translate('toggle_time_format'),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Expanded(
                              child: shifts.isEmpty
                                  ? Center(
                                      child: Text(
                                        localizations
                                            .translate('no_shifts_found'),
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: shifts.length,
                                      itemBuilder: (context, index) {
                                        final shift = shifts[index];
                                        final timeFormat = use24HourFormat
                                            ? 'yyyy-MM-dd HH:mm'
                                            : 'yyyy-MM-dd hh:mm a';
                                        return Card(
                                          elevation: 4,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 8.0),
                                          child: ExpansionTile(
                                            title: Text(
                                              '${shift['userName']} - ${DateFormat(timeFormat).format((shift['startTime'] as Timestamp).toDate())}',
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600),
                                            ),
                                            subtitle: Text(
                                              '${localizations.translate('status')}: ${shift['status']} | ${localizations.translate('cash_count')}: ${shift['finalCashCount']?.toStringAsFixed(2) ?? 'N/A'}',
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                            children: [
                                              FutureBuilder<
                                                  List<Map<String, dynamic>>>(
                                                future: shiftServiceWithContext
                                                    .getShiftTransactions(
                                                        shift['id'], storeId),
                                                builder: (context, snapshot) {
                                                  if (snapshot
                                                          .connectionState ==
                                                      ConnectionState.waiting) {
                                                    return const Padding(
                                                      padding:
                                                          EdgeInsets.all(16.0),
                                                      child:
                                                          CircularProgressIndicator(),
                                                    );
                                                  }
                                                  if (snapshot.hasError) {
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16.0),
                                                      child: Text(
                                                        localizations.translate(
                                                            'error_loading_transactions'),
                                                        style: theme.textTheme
                                                            .bodyLarge,
                                                      ),
                                                    );
                                                  }
                                                  if (!snapshot.hasData ||
                                                      snapshot.data!.isEmpty) {
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16.0),
                                                      child: Text(
                                                        localizations.translate(
                                                            'no_transactions'),
                                                        style: theme.textTheme
                                                            .bodyLarge,
                                                      ),
                                                    );
                                                  }
                                                  final transactions =
                                                      snapshot.data!;
                                                  double totalSales =
                                                      transactions.fold(
                                                          0.0,
                                                          (sum, txn) =>
                                                              sum +
                                                              (txn['total']
                                                                  as double));
                                                  double cashSales = transactions
                                                      .where((txn) =>
                                                          txn['paymentMethod'] ==
                                                          'cash')
                                                      .fold(
                                                          0.0,
                                                          (sum, txn) =>
                                                              sum +
                                                              (txn['total']
                                                                  as double));
                                                  double visaSales = transactions
                                                      .where((txn) =>
                                                          txn['paymentMethod'] ==
                                                          'visa')
                                                      .fold(
                                                          0.0,
                                                          (sum, txn) =>
                                                              sum +
                                                              (txn['total']
                                                                  as double));

                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16.0),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        buildSummaryRow(
                                                            localizations
                                                                .translate(
                                                                    'total_sales'),
                                                            '\$${totalSales.toStringAsFixed(2)}'),
                                                        buildSummaryRow(
                                                            localizations
                                                                .translate(
                                                                    'cash_sales'),
                                                            '\$${cashSales.toStringAsFixed(2)}'),
                                                        buildSummaryRow(
                                                            localizations
                                                                .translate(
                                                                    'visa_sales'),
                                                            '\$${visaSales.toStringAsFixed(2)}'),
                                                        const SizedBox(
                                                            height: 8),
                                                        ...transactions.map(
                                                            (txn) => ListTile(
                                                                  title: Text(
                                                                    '${localizations.translate('transaction')} #${txn['id']} - ${DateFormat(use24HourFormat ? 'HH:mm' : 'hh:mm a').format((txn['timestamp'] as Timestamp).toDate())}',
                                                                    style: theme
                                                                        .textTheme
                                                                        .bodyLarge
                                                                        ?.copyWith(
                                                                            fontWeight:
                                                                                FontWeight.w600),
                                                                  ),
                                                                  subtitle:
                                                                      Text(
                                                                    '${localizations.translate('total')}: \$${txn['total'].toStringAsFixed(2)} (${txn['paymentMethod']})',
                                                                    style: theme
                                                                        .textTheme
                                                                        .bodyMedium,
                                                                  ),
                                                                )),
                                                      ],
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
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                  color: isTotal ? Colors.green : null,
                ),
          ),
        ],
      ),
    );
  }
}
