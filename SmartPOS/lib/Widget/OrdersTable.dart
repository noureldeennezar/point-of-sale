import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Core/app_localizations.dart';
import '../cloud_services/AuthService.dart';
import '../local_services/ItemDatabaseHelper.dart';
import 'SummaryRow.dart';

class OrdersTable extends StatefulWidget {
  const OrdersTable({super.key});

  @override
  _OrdersTableState createState() => _OrdersTableState();
}

class _OrdersTableState extends State<OrdersTable> {
  List<Map<String, dynamic>> orders = [];

  @override
  void initState() {
    super.initState();
    loadOrders();
  }

  Future<void> loadOrders() async {
    ItemDatabaseHelper dbHelper = ItemDatabaseHelper();
    try {
      List<Map<String, dynamic>> data = await dbHelper.fetchOrdersWithItems();
      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context).translate('no_orders_found')),
            ),
          );
        }
      }

      Map<int, Map<String, dynamic>> orderMap = {};

      for (var order in data) {
        int orderNumber = order['orderNumber'] ?? 0;
        String date = order['date'] ?? DateTime.now().toIso8601String();
        double salesPrice = order['salesPrice']?.toDouble() ?? 0.0;
        int quantity = order['quantity'] ?? 1;
        double totalPrice = salesPrice * quantity;

        if (!orderMap.containsKey(orderNumber)) {
          orderMap[orderNumber] = {
            'orderNumber': orderNumber,
            'date': date,
            'totalPrice': 0.0,
            'items': [],
          };
        }

        orderMap[orderNumber]!['items'].add({
          'itemCode': order['itemCode'] ?? '',
          'itemName': order['itemName'] ?? 'Unknown Item',
          'salesPrice': salesPrice,
          'quantity': quantity,
          'totalPrice': totalPrice,
        });

        orderMap[orderNumber]!['totalPrice'] +=
            (totalPrice * 1.2); // Assuming 20% tax/service
      }

      if (mounted) {
        setState(() {
          orders = orderMap.values.toList();
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

  Future<void> deleteItem(String itemCode, int orderNumber) async {
    if (itemCode.isEmpty) return; // Prevent deleting with empty itemCode
    ItemDatabaseHelper dbHelper = ItemDatabaseHelper();
    try {
      await dbHelper.deleteItem(itemCode);
      await loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).translate('item_deleted')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).translate('failed_to_delete_item')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> clearDatabase() async {
    ItemDatabaseHelper dbHelper = ItemDatabaseHelper();
    try {
      await dbHelper.clearDatabase();
      await loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context).translate('database_cleared')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).translate('failed_to_clear_database')}: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return StreamBuilder<Map<String, dynamic>?>(
      stream:
          Provider.of<AuthService>(context, listen: false).currentUserWithRole,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              localizations.translate('error_loading_user_data'),
              style: theme.textTheme.bodyLarge,
            ),
          );
        }

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
                  ElevatedButton(
                    onPressed: clearDatabase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 50),
                      elevation: 4,
                    ),
                    child: Text(
                      localizations.translate('clear_database'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  orders.isEmpty
                      ? Center(
                          child: Text(
                            localizations.translate('no_orders_found'),
                            style: theme.textTheme.bodyLarge,
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
                                    borderRadius: BorderRadius.circular(12)),
                                margin:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: ExpansionTile(
                                  title: Text(
                                    '${localizations.translate('order')} #${order['orderNumber']}',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${localizations.translate('date')}: ${order['date']}',
                                    style: theme.textTheme.bodyMedium,
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
                                            localizations
                                                .translate('total_price'),
                                            '\$${order['totalPrice'].toStringAsFixed(2)}',
                                            isTotal: true,
                                          ),
                                          const SizedBox(height: 8),
                                          ...((order['items'] as List).map(
                                            (item) => ListTile(
                                              title: Text(
                                                '${item['itemName']} (Qty: ${item['quantity']})',
                                                style: theme.textTheme.bodyLarge
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600),
                                              ),
                                              subtitle: Text(
                                                '\$${item['totalPrice'].toStringAsFixed(2)}',
                                                style:
                                                    theme.textTheme.bodyMedium,
                                              ),
                                              trailing: IconButton(
                                                icon: const Icon(Icons.delete,
                                                    color: Colors.red),
                                                onPressed: () => deleteItem(
                                                    item['itemCode'],
                                                    order['orderNumber']),
                                              ),
                                            ),
                                          )),
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
      },
    );
  }
}
