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
      'item_code': itemCode,
      'item_name': itemName,
      'sales_price': salesPrice,
      'itm_group_code': itmGroupCode,
      // 'quantity': quantity
    };
  }
}

class Order {
  int orderNumber;
  List<Item> items;

  Order({
    required this.orderNumber,
    required this.items,
  });

  // Convert Order to Map for inserting into the database
  Map<String, dynamic> toMap() {
    return {
      'orderNumber': orderNumber,
      'items': items.map((item) => item.toMap()).toList(),
    };
  }
}
