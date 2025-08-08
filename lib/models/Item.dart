class Item {
  final String itemCode;
  final String itemName;
  final double salesPrice;
  final String itmGroupCode;
  final String? barcode;
  final bool isActive;
  int quantity;

  Item({
    required this.itemCode,
    required this.itemName,
    required this.salesPrice,
    required this.itmGroupCode,
    this.barcode,
    this.isActive = true,
    this.quantity = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'item_code': itemCode,
      'item_name': itemName,
      'sales_price': salesPrice,
      'itm_group_code': itmGroupCode,
      'barcode': barcode,
      'is_active': isActive ? 1 : 0,
      'quantity': quantity,
    };
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      itemCode: map['item_code'],
      itemName: map['item_name'],
      salesPrice: map['sales_price'],
      itmGroupCode: map['itm_group_code'],
      barcode: map['barcode'],
      isActive: map['is_active'] == 1,
      quantity: map['quantity'] ?? 1,
    );
  }
}
