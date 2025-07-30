// TODO Implement this library.
class Item {
  final String itemCode;
  final String itemName;
  final double salesPrice;
  final String itmGroupCode;
  int quantity;

  Item({
    required this.itemCode,
    required this.itemName,
    required this.salesPrice,
    required this.itmGroupCode,
    this.quantity = 1, // Default quantity is 1
  });

  Map<String, dynamic> toMap() {
    return {
      'itemCode': itemCode, // Match DBHelper field names
      'itemName': itemName,
      'salesPrice': salesPrice,
      'itmGroupCode': itmGroupCode,
      'quantity': quantity, // Include quantity for orderItems table
    };
  }
}

class Order {
  int? orderNumber; // Nullable since it's auto-incremented
  List<Item> items;
  String? date; // Add date field for DB compatibility

  Order({
    this.orderNumber,
    required this.items,
    this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'orderNumber': orderNumber,
      'date': date ?? DateTime.now().toString(),
      'items': items.map((item) => item.toMap()).toList(),
    };
  }
}