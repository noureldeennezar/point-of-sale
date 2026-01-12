class Item {
  final String itemCode;
  final String itemName;
  final double salesPrice;
  final String itmGroupCode;
  final String? barcode;
  final bool isActive;

  // ── Stock fields ───────────────────────────────
  final int stockQuantity;
  final int minStockLevel;

  // Quantity used only in order/cart context (not persisted)
  int quantity;

  Item({
    required this.itemCode,
    required this.itemName,
    required this.salesPrice,
    required this.itmGroupCode,
    this.barcode,
    this.isActive = true,
    this.stockQuantity = 0,
    this.minStockLevel = 0,
    this.quantity = 1,
  });

  Item copyWith({
    String? itemCode,
    String? itemName,
    double? salesPrice,
    String? itmGroupCode,
    String? barcode,
    bool? isActive,
    int? stockQuantity,
    int? minStockLevel,
    int? quantity,
  }) {
    return Item(
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      salesPrice: salesPrice ?? this.salesPrice,
      itmGroupCode: itmGroupCode ?? this.itmGroupCode,
      barcode: barcode ?? this.barcode,
      isActive: isActive ?? this.isActive,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      quantity: quantity ?? this.quantity,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item_code': itemCode,
      'item_name': itemName,
      'sales_price': salesPrice,
      'itm_group_code': itmGroupCode,
      'barcode': barcode,
      'is_active': isActive ? 1 : 0,
      'stock_quantity': stockQuantity,
      'min_stock_level': minStockLevel,
      // Note: 'quantity' is NOT saved to database
    };
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      itemCode: map['item_code'] as String,
      itemName: map['item_name'] as String,
      salesPrice: (map['sales_price'] as num).toDouble(),
      itmGroupCode: map['itm_group_code'] as String,
      barcode: map['barcode'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      stockQuantity: map['stock_quantity'] as int? ?? 0,
      minStockLevel: map['min_stock_level'] as int? ?? 0,
      // quantity remains 1 by default when loaded from DB
    );
  }

  @override
  String toString() => 'Item($itemCode - $itemName, stock: $stockQuantity)';
}
