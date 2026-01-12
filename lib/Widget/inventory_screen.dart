import 'package:flutter/material.dart';

import '../local_services/item_db_helper.dart';
import '../models/Item.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ItemDbHelper _itemDb = ItemDbHelper();
  List<Item> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<String> _getStoreId() async {
    return 'local_store_001';
  }

  Future<void> _loadItems() async {
    try {
      final storeId = await _getStoreId();
      final items = await _itemDb.getItems(storeId);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading items: $e')));
      }
    }
  }

  Future<void> _adjustStock(Item item, int delta) async {
    final storeId = await _getStoreId();

    try {
      if (delta > 0) {
        await _itemDb.updateItemStock(
          item.itemCode,
          storeId,
          increaseBy: delta,
        );
      } else if (delta < 0) {
        await _itemDb.updateItemStock(
          item.itemCode,
          storeId,
          decreaseBy: delta.abs(),
        );
      }

      await _loadItems(); // Refresh list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error changing stock: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _setStockDialog(Item item) async {
    final ctrl = TextEditingController(text: item.stockQuantity.toString());
    final newQty = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set stock quantity: ${item.itemName}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              if (v != null && v >= 0) {
                Navigator.pop(ctx, v);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter a valid number ≥ 0')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newQty != null && newQty >= 0 && mounted) {
      try {
        final storeId = await _getStoreId();
        await _itemDb.updateItemStock(item.itemCode, storeId, newStock: newQty);
        await _loadItems();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error setting stock: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Warehouse / Stock')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadItems,
              child: _items.isEmpty
                  ? const Center(child: Text('No items in stock'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final isLow =
                            item.minStockLevel > 0 &&
                            item.stockQuantity <= item.minStockLevel;

                        return ListTile(
                          title: Text(item.itemName),
                          subtitle: Text(
                            'Stock: ${item.stockQuantity}   •   Min level: ${item.minStockLevel}',
                            style: TextStyle(color: isLow ? Colors.red : null),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () => _adjustStock(item, -1),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.green,
                                ),
                                onPressed: () => _adjustStock(item, 1),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () => _setStockDialog(item),
                                child: const Text('Set'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
