import 'package:flutter/material.dart';
import 'package:zpos/services/sql_order_helper.dart';

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

  // Load orders from the database
  Future<void> loadOrders() async {
    DBHelper dbHelper = DBHelper();

    try {
      List<Map<String, dynamic>> data = await dbHelper.fetchOrdersWithItems();

      // Grouping orders and calculating total price
      Map<int, Map<String, dynamic>> orderMap = {};

      for (var order in data) {
        int orderNumber = order['orderNumber'];
        String date = order['date'];
        double salesPrice = order['salesPrice'];
        int quantity = order['quantity'];
        double totalPrice = salesPrice * quantity;

        if (!orderMap.containsKey(orderNumber)) {
          orderMap[orderNumber] = {
            'orderNumber': orderNumber,
            'date': date,
            'totalPrice': 0.0, // Initialize total price
            'items': [], // Initialize items list
          };
        }

        // Add item to the items list
        orderMap[orderNumber]!['items'].add({
          'itemCode': order['itemCode'],
          'itemName': order['itemName'],
          'salesPrice': salesPrice,
          'quantity': quantity,
          'totalPrice': totalPrice,
        });

        // Accumulate total price for this order
        orderMap[orderNumber]!['totalPrice'] += (totalPrice * 1.2);
      }

      setState(() {
        orders = orderMap.values.toList(); // Convert map values to a list
      });

      // Log the orders for debugging
      print(
          "Orders loaded: ${orders.length}"); // Check the length of the orders
    } catch (e) {
      print("Error loading orders: $e"); // Log the error
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load orders.')));
    }
  }

  // Delete an item and reload the orders
  Future<void> deleteItem(String itemCode, int orderNumber) async {
    DBHelper dbHelper = DBHelper();
    try {
      await dbHelper.deleteItem(itemCode, orderNumber);
      loadOrders(); // Reload the table after deletion
    } catch (e) {
      print("Error deleting item: $e"); // Log the error
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete item.')));
    }
  }

  // Clear the database and reload the orders
  Future<void> clearDatabase() async {
    DBHelper dbHelper = DBHelper();
    try {
      await dbHelper.clearDatabase();
      loadOrders(); // Reload the orders after clearing the database
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Database cleared!')));
    } catch (e) {
      print("Error clearing database: $e"); // Log the error
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to clear the database.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders Table'),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Clear Database Button at the top
              ElevatedButton(
                onPressed: clearDatabase,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text(
                  'Clear Database',
                  style: TextStyle(color: Colors.white),
                ), // Style the button
              ),
              const SizedBox(height: 20), // Spacing before the data table
              orders.isEmpty
                  ? const Center(
                      child: Text(
                        'No orders found.',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : SizedBox(
                      width: double.infinity, // Make the table take full width
                      child: DataTable(
                        columnSpacing: 50,
                        // ignore: deprecated_member_use
                        dataRowHeight: 100, // Set the height of each row
                        columns: const [
                          DataColumn(
                              label: Text('Number',
                                  style: TextStyle(color: Colors.white))),
                          DataColumn(
                              label: Text('Order Number',
                                  style: TextStyle(color: Colors.white))),
                          DataColumn(
                              label: Text('Date',
                                  style: TextStyle(color: Colors.white))),
                          DataColumn(
                              label: Text('Total Price',
                                  style: TextStyle(color: Colors.white))),
                          DataColumn(
                              label: Text('Items',
                                  style: TextStyle(color: Colors.white))),
                        ],
                        rows: orders.asMap().entries.map((entry) {
                          int index = entry.key; // Get the index of the entry
                          Map<String, dynamic> order = entry.value;
                          return DataRow(cells: [
                            DataCell(Text((index + 1).toString(),
                                style: const TextStyle(color: Colors.white))),
                            // Number column
                            DataCell(Text(order['orderNumber'].toString(),
                                style: const TextStyle(color: Colors.white))),
                            DataCell(Text(order['date'].toString(),
                                style: const TextStyle(color: Colors.white))),
                            DataCell(Text(
                                order['totalPrice'].toStringAsFixed(2),
                                style: const TextStyle(color: Colors.white))),
                            // Display total price
                            DataCell(
                              SizedBox(
                                height: 250, // Set fixed height for item column
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: (order['items'] as List)
                                        .map<Widget>((item) {
                                      return Text(
                                        '${item['itemName']} (Qty: ${item['quantity']})',
                                        style: const TextStyle(
                                            color: Colors.white),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
