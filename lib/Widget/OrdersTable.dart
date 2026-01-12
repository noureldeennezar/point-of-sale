import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Core/app_localizations.dart';
import '../cloud_services/AuthService.dart';
import '../local_services/order_db_helper.dart';
import 'SummaryRow.dart';

class OrdersTable extends StatefulWidget {
  const OrdersTable({super.key});

  @override
  _OrdersTableState createState() => _OrdersTableState();
}

class _OrdersTableState extends State<OrdersTable> {
  List<Map<String, dynamic>> orders = [];
  late final OrderDbHelper _orderDbHelper;

  @override
  void initState() {
    super.initState();
    _orderDbHelper = OrderDbHelper();
    loadOrders();
  }

  Future<String> _getEffectiveStoreId() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userData = await authService.currentUserWithRole.first;

    // Fallback for guest/offline
    return userData?['storeId'] as String? ?? 'local_store_001';
  }

  Future<void> loadOrders() async {
    final storeId = await _getEffectiveStoreId();

    try {
      List<Map<String, dynamic>> rawData = await _orderDbHelper
          .fetchOrdersWithItems(storeId);

      if (rawData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).translate('no_orders_found'),
              ),
            ),
          );
        }
        setState(() => orders = []);
        return;
      }

      // Group by orderNumber (your existing logic)
      Map<int, Map<String, dynamic>> orderMap = {};

      for (var row in rawData) {
        final int orderNumber = row['orderNumber'] as int;
        final String date = row['date'] as String;

        if (!orderMap.containsKey(orderNumber)) {
          orderMap[orderNumber] = {
            'orderNumber': orderNumber,
            'date': date,
            'totalPrice': 0.0,
            'items': [],
          };
        }

        final double salesPrice = (row['salesPrice'] as num).toDouble();
        final int quantity = row['quantity'] as int;
        final double lineTotal = salesPrice * quantity;

        orderMap[orderNumber]!['items'].add({
          'itemCode': row['itemCode'] ?? '',
          'itemName': row['itemName'] ?? 'Unknown Item',
          'salesPrice': salesPrice,
          'quantity': quantity,
          'totalPrice': lineTotal,
        });

        orderMap[orderNumber]!['totalPrice'] += lineTotal;
      }

      final groupedOrders = orderMap.values.toList()
        ..sort((a, b) => b['orderNumber'].compareTo(a['orderNumber']));

      if (mounted) {
        setState(() {
          orders = groupedOrders;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).translate('failed_to_load_orders')}: $e',
            ),
          ),
        );
      }
    }
  }

  // Your clearAllOrders() – just update _getEffectiveStoreId() there too
  Future<void> clearAllOrders() async {
    final storeId = await _getEffectiveStoreId();
    // ... rest of your clearAllOrders logic remains the same
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Text(
            localizations.translate('order_history'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: localizations.translate('refresh'),
              onPressed: loadOrders,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              ElevatedButton.icon(
                onPressed: clearAllOrders,
                icon: const Icon(Icons.delete_sweep),
                label: Text(localizations.translate('clear_all_orders')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                  elevation: 4,
                ),
              ),
              const SizedBox(height: 16),
              orders.isEmpty
                  ? Expanded(
                      child: Center(
                        child: Text(localizations.translate('no_orders_found')),
                      ),
                    )
                  : Expanded(
                      child: ListView.builder(
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 8.0),
                            child: ExpansionTile(
                              title: Text(
                                '${localizations.translate('order')} #${order['orderNumber']}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${localizations.translate('date')}: ${DateTime.parse(order['date']).toLocal().toString().substring(0, 16)}',
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      buildSummaryRow(
                                        context,
                                        localizations.translate('total_price'),
                                        '\$${order['totalPrice'].toStringAsFixed(2)}',
                                        isTotal: true,
                                      ),
                                      const SizedBox(height: 12),
                                      ...(order['items'] as List).map<Widget>((
                                        item,
                                      ) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4.0,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${item['itemName']} × ${item['quantity']}',
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                              ),
                                              Text(
                                                '\$${item['totalPrice'].toStringAsFixed(2)}',
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: Colors.green[700],
                                                    ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
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
  }
}
