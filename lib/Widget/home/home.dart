import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_barcode_listener/flutter_barcode_listener.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../Core/app_localizations.dart';
import '../../cloud_services/AuthService.dart';
import '../../cloud_services/sync_service.dart';
import '../../local_services/AuthDatabaseHelper.dart';
import '../../local_services/category_db_helper.dart';
import '../../local_services/item_db_helper.dart';
import '../../local_services/order_db_helper.dart';
import '../../local_services/shift_db_helper.dart';
import '../../models/Item.dart';
import '../../models/Order.dart' as OrderModel;
import '../../models/ProductCategory.dart';
import '../SummaryRow.dart';
import '../auth/login.dart';

class MyHomePage extends StatefulWidget {
  final String loggedInUserName;
  final String title;
  final String name;

  const MyHomePage({
    super.key,
    required this.title,
    required this.name,
    required this.loggedInUserName,
  });

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final CategoryDbHelper _categoryDb = CategoryDbHelper();
  final ItemDbHelper _itemDb = ItemDbHelper();
  final OrderDbHelper _orderDb = OrderDbHelper();
  final ShiftDbHelper _shiftDb = ShiftDbHelper();
  final DatabaseHelper _localDb = DatabaseHelper.instance;

  late final SyncService _syncService;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _serviceChargeController =
      TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Add this right after the other fields (lists, booleans, controllers, etc.)
  final Map<String, TextEditingController> _quantityControllers = {};

  String? selectedCategory;
  List<ProductCategory> displayGroups = [];
  List<Item> displayItems = [];
  List<Item> orderItems = [];
  List<List<Item>> heldOrders = [];

  bool isShiftOpen = false;
  bool isShowingSubcategories = false;
  bool isLoading = false;
  bool _isAdding = false;
  bool _isEditing = false;
  bool _applyServiceCharge = false;
  bool isSyncing = false;
  bool isAuthenticated = false;

  double _serviceChargeAmount = 0.0;

  String? _userRole;
  Item? _editingItem;
  int curOrderNumber = 1;
  String? _currentShiftId;

  StreamSubscription<Map<String, dynamic>?>? _firebaseSub;

  @override
  void initState() {
    super.initState();

    _itemDb.ensureStockColumnsExist();

    _syncService = SyncService(
      context: context,
      categoryDb: _categoryDb,
      itemDb: _itemDb,
      orderDb: _orderDb,
      shiftDb: _shiftDb,
    );

    _loadInitialData();

    _firebaseSub = Provider.of<AuthService>(context, listen: false)
        .currentUserWithRole
        .listen((firebaseData) async {
          String? role;

          if (firebaseData != null) {
            role = firebaseData['role'] as String?;
            if (mounted) setState(() => isAuthenticated = true);
          } else {
            // Force guest role when offline / no Firebase user
            role = 'guest';
            if (mounted) setState(() => isAuthenticated = false);

            // Clean up any lingering active user flag
            await _localDb.logoutLocal();
          }

          if (mounted) {
            setState(() {
              _userRole = role?.toLowerCase() ?? 'guest';
            });
          }
        });

    _checkLocalRoleImmediately();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  Future<void> _checkLocalRoleImmediately() async {
    if (_userRole != null) return;

    final localUser = await _localDb.getActiveUser();
    if (localUser != null && mounted) {
      setState(() {
        _userRole = (localUser['role'] as String?)?.toLowerCase() ?? 'guest';
      });
    }
  }

  Future<String> _getStoreId() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userData = await authService.currentUserWithRole.first;
    return (userData?['storeId'] as String?) ?? 'local_store_001';
  }

  Future<void> _loadInitialData() async {
    setState(() => isLoading = true);
    try {
      await _fetchData();
      await _fetchLatestOrderNumber();

      final storeId = await _getStoreId();
      if (storeId.isNotEmpty) {
        final cats = await _categoryDb.getCategories(storeId);
        if (mounted) setState(() => displayGroups = cats);
      }
    } catch (_) {}
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchLatestOrderNumber() async {
    try {
      final storeId = await _getStoreId();
      final latest = await _orderDb.getLatestOrderId(storeId);
      if (mounted) setState(() => curOrderNumber = latest + 1);
    } catch (_) {}
  }

  Future<void> _fetchData() async {
    try {
      await fetchCategories();
      await _fetchLatestOrderNumber();
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────
  //                      STOCK CHECK & UPDATE
  // ──────────────────────────────────────────────────────────────

  Future<bool> _canProcessOrder() async {
    final storeId = await _getStoreId();

    for (final orderItem in orderItems) {
      final dbItem = await _itemDb.getItem(orderItem.itemCode, storeId);
      if (dbItem == null || dbItem.stockQuantity < orderItem.quantity) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Not enough stock for "${orderItem.itemName}"\n'
                'Available: ${dbItem?.stockQuantity ?? "?"}  Required: ${orderItem.quantity}',
              ),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return false;
      }
    }
    return true;
  }

  Future<void> _decreaseStockAfterSale() async {
    final storeId = await _getStoreId();
    final db = await _itemDb.database; // ← now compiles!

    await db.transaction((txn) async {
      for (final item in orderItems) {
        await _itemDb.updateItemStock(
          item.itemCode,
          storeId,
          decreaseBy: item.quantity,
          txn: txn,
        );
      }
    });
  }

  Future<void> _checkout() async {
    final storeId = await _getStoreId();

    if (orderItems.isEmpty) {
      _showSnack('No items to checkout');
      return;
    }

    if (!isShiftOpen) {
      _showSnack('No active shift');
      return;
    }

    if (!(await _canProcessOrder())) return;

    final order = OrderModel.Order(
      items: List.from(orderItems),
      date: DateTime.now().toIso8601String(),
    );

    try {
      print('Starting checkout - inserting order...');
      await _orderDb.insertOrder(order, storeId);
      print('Order inserted, decreasing stock...');
      await _decreaseStockAfterSale();
      print('Stock decreased successfully');

      if (!mounted) {
        print('Widget not mounted after checkout');
        return;
      }

      setState(() {
        orderItems.clear();
        curOrderNumber++;
        _applyServiceCharge = false;
        _serviceChargeAmount = 0.0;
      });

      _showSnack(
        AppLocalizations.of(context).translate('order_checked_out_success'),
        color: Colors.green,
      );
    } catch (e, stack) {
      print('Checkout failed: $e');
      print('Stack: $stack');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }

    _searchFocusNode.requestFocus();
  }

  // Helper method
  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color ?? null),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //                          SHIFT MANAGEMENT
  // ──────────────────────────────────────────────────────────────

  Future<void> _toggleShift() async {
    final storeId = await _getStoreId();
    // Use display name ("Guest User") instead of email for better guest experience
    final userName = widget.name;

    print(
      'Attempting to toggle shift | User: $userName | Store: $storeId | Current open: $isShiftOpen',
    );

    if (!isShiftOpen) {
      try {
        final shiftId = await _shiftDb.openShift(
          storeId: storeId,
          userName: userName,
          startTime: DateTime.now(),
        );

        print('Shift opened successfully! ID: $shiftId');

        if (mounted) {
          setState(() {
            isShiftOpen = true;
            _currentShiftId = shiftId;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).translate(
                  'shift_opened_at',
                  params: {'time': DateFormat('HH:mm').format(DateTime.now())},
                ),
              ),
            ),
          );
        }
      } catch (e) {
        print('Failed to open shift: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to open shift: $e')));
        }
      }
    } else {
      double? finalCashCount;
      final controller = TextEditingController();

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context).translate('close_shift')),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(
                context,
              ).translate('final_cash_count'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).translate('cancel')),
            ),
            TextButton(
              onPressed: () {
                finalCashCount = double.tryParse(controller.text) ?? 0.0;
                Navigator.pop(context, true);
              },
              child: Text(AppLocalizations.of(context).translate('confirm')),
            ),
          ],
        ),
      );

      if (confirmed != true || _currentShiftId == null || !mounted) return;

      try {
        await _shiftDb.closeShift(
          shiftId: _currentShiftId!,
          storeId: storeId,
          finalCashCount: finalCashCount!,
          endTime: DateTime.now(),
        );

        print('Shift closed successfully! ID: $_currentShiftId');

        setState(() {
          isShiftOpen = false;
          _currentShiftId = null;
          curOrderNumber = 1;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate(
                'shift_closed_at',
                params: {'time': DateFormat('HH:mm').format(DateTime.now())},
              ),
            ),
          ),
        );
      } catch (e) {
        print('Failed to close shift: $e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to close shift: $e')));
      }
    }
  }

  // ──────────────────────────────────────────────────────────────
  //                     CATEGORY & ITEM MANAGEMENT
  // ──────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteCategory(ProductCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete category "${category.categoryName}"?\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _deleteCategory(category);
  }

  Future<void> _confirmEditItem(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Item'),
        content: Text('Edit "${item.itemName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Edit'),
          ),
        ],
      ),
    );

    if (confirmed == true) _editItem(item);
  }

  Future<void> _confirmDeleteItem(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete item "${item.itemName}"?\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _deleteItem(item);
  }

  Future<void> _deleteCategory(ProductCategory category) async {
    final role = (_userRole ?? 'guest').toLowerCase();
    if (role != 'admin' && role != 'local') return;

    final storeId = await _getStoreId();

    try {
      await _categoryDb.deleteCategory(category.categoryCode, storeId);
      setState(() {
        displayGroups.remove(category);
        if (selectedCategory == category.categoryCode) {
          displayItems.clear();
          selectedCategory = null;
          isShowingSubcategories = false;
        }
        orderItems.removeWhere((i) => i.itmGroupCode == category.categoryCode);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Category "${category.categoryName}" has been deleted'),
        ),
      );
      await fetchCategories();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete category')),
      );
    }
  }

  Future<void> _deleteItem(Item item) async {
    final role = (_userRole ?? 'guest').toLowerCase();
    if (role != 'admin' && role != 'local') return;

    final storeId = await _getStoreId();

    try {
      await _itemDb.deleteItem(item.itemCode, storeId);
      setState(() {
        displayItems.remove(item);
        orderItems.removeWhere((i) => i.itemCode == item.itemCode);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item "${item.itemName}" has been deleted')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete item')));
    }
  }

  void _editItem(Item item) {
    final role = (_userRole ?? 'guest').toLowerCase();
    if (role != 'admin' && role != 'local') return;

    setState(() {
      _isAdding = true;
      _isEditing = true;
      _editingItem = item;
      _nameController.text = item.itemName;
      _priceController.text = item.salesPrice.toString();
      _barcodeController.text = item.barcode ?? '';
      selectedCategory = item.itmGroupCode;
    });
  }

  // ──────────────────────────────────────────────────────────────
  //                        ORDER ACTIONS
  // ──────────────────────────────────────────────────────────────

  void holdOrder() {
    if (orderItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('no_items_to_hold'),
          ),
        ),
      );
      return;
    }
    setState(() {
      heldOrders.add(List.from(orderItems));
      orderItems.clear();
      curOrderNumber++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).translate('order_held')),
      ),
    );
    _searchFocusNode.requestFocus();
  }

  void getHeldOrders() async {
    if (heldOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('no_held_orders'),
          ),
        ),
      );
      return;
    }

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppLocalizations.of(context).translate('select_held_order'),
        ),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: heldOrders.length,
            itemBuilder: (context, index) {
              final order = heldOrders[index];
              final total = order.fold(
                0.0,
                (sum, i) => sum + i.salesPrice * i.quantity,
              );
              return ListTile(
                title: Text('Order #${index + 1}'),
                subtitle: Text(
                  '${order.length} items — \$${total.toStringAsFixed(2)}',
                ),
                onTap: () => Navigator.pop(context, index),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).translate('cancel')),
          ),
        ],
      ),
    );

    if (selectedIndex != null) {
      setState(() {
        orderItems = List.from(heldOrders[selectedIndex]);
        heldOrders.removeAt(selectedIndex);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('order_retrieved'),
          ),
        ),
      );
    }
  }

  void _showServiceChargeDialog() async {
    _serviceChargeController.text = _serviceChargeAmount.toStringAsFixed(2);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context).translate('service_charge')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _serviceChargeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                ).translate('service_charge_amount'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: Text(
                AppLocalizations.of(context).translate('apply_service_charge'),
              ),
              value: _applyServiceCharge,
              onChanged: (v) =>
                  setState(() => _applyServiceCharge = v ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).translate('cancel')),
          ),
          TextButton(
            onPressed: () {
              final amount =
                  double.tryParse(_serviceChargeController.text) ?? 0.0;
              Navigator.pop(context, {
                'apply': _applyServiceCharge,
                'amount': amount,
              });
            },
            child: Text(AppLocalizations.of(context).translate('save')),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _applyServiceCharge = result['apply'] as bool;
        _serviceChargeAmount = result['amount'] as double;
      });
    }
  }

  // ──────────────────────────────────────────────────────────────
  //                          SEARCH & ADD ITEM
  // ──────────────────────────────────────────────────────────────

  Future<void> _handleSearchSubmit(String value) async {
    if (!_isAdding && isShiftOpen && value.isNotEmpty) {
      value = value.trim();
      final items = await _getAllItems();
      final found = items.firstWhere(
        (i) =>
            i.barcode == value ||
            i.itemName.toLowerCase() == value.toLowerCase(),
        orElse: () => Item(
          itemCode: '',
          itemName: '',
          salesPrice: 0,
          itmGroupCode: '',
          quantity: 0,
        ),
      );

      if (found.itemCode.isNotEmpty) {
        if (found.stockQuantity > 0) {
          addItemToOrder(found);
          setState(() {
            _searchController.clear();
            displayItems = [];
            displayGroups = [];
            isShowingSubcategories = false;
            selectedCategory = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).translate(
                  'item_added_to_order',
                  params: {'item_name': found.itemName},
                ),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Item is out of stock'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        _barcodeController.text = value;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate('item_not_found'),
            ),
            action: SnackBarAction(
              label: AppLocalizations.of(context).translate('add_new_item'),
              onPressed: () => setState(() => _isAdding = true),
            ),
          ),
        );
      }
    }
    _searchFocusNode.requestFocus();
  }

  Future<void> _saveNewItem() async {
    final storeId = await _getStoreId();

    if (_nameController.text.trim().isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('fill_all_fields'),
          ),
        ),
      );
      return;
    }

    final price = double.tryParse(_priceController.text);
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('invalid_price'),
          ),
        ),
      );
      return;
    }

    final groupCode =
        selectedCategory ??
        (displayGroups.isNotEmpty
            ? displayGroups.first.categoryCode
            : 'default');

    final item = Item(
      itemCode: _isEditing
          ? _editingItem!.itemCode
          : DateTime.now().millisecondsSinceEpoch.toString(),
      itemName: _nameController.text.trim(),
      salesPrice: price,
      itmGroupCode: groupCode,
      barcode: _barcodeController.text.trim(),
      isActive: true,
      quantity: 1,
    );

    try {
      await _itemDb.insertItem(item, storeId);

      if (!_isEditing) addItemToOrder(item);

      setState(() {
        _isAdding = false;
        _isEditing = false;
        _editingItem = null;
      });
      _nameController.clear();
      _priceController.clear();
      _barcodeController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              _isEditing ? 'item_updated' : 'item_added',
              params: {'item_name': item.itemName},
            ),
          ),
        ),
      );
      await fetchCategories();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('failed_to_save_item'),
          ),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    await Provider.of<AuthService>(context, listen: false).signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //                     STOCK VISUALIZATION
  // ──────────────────────────────────────────────────────────────

  Widget _buildStockBadge(Item item) {
    final stock = item.stockQuantity;
    final min = item.minStockLevel;

    if (stock <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red),
        ),
        child: Text(
          '0 — out of stock',
          style: const TextStyle(
            color: Colors.red,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (min > 0 && stock <= min) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange),
        ),
        child: Text(
          'Stock: $stock (low)',
          style: const TextStyle(
            color: Colors.deepOrange,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Text(
      'Stock: $stock',
      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //                          BARCODE SCAN
  // ──────────────────────────────────────────────────────────────

  Future<void> _handleScannedBarcode(String barcode) async {
    if (!isShiftOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('no_active_shift'),
          ),
        ),
      );
      return;
    }

    if (_isAdding || _isEditing) return;

    barcode = barcode.trim();
    final items = await _getAllItems();
    final found = items.firstWhere(
      (i) => i.barcode == barcode,
      orElse: () => Item(
        itemCode: '',
        itemName: '',
        salesPrice: 0,
        itmGroupCode: '',
        quantity: 0,
      ),
    );

    if (found.itemCode.isNotEmpty) {
      if (found.stockQuantity > 0) {
        addItemToOrder(found);
        setState(() {
          _searchController.clear();
          displayItems = [];
          displayGroups = [];
          isShowingSubcategories = false;
          selectedCategory = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate(
                'item_added_to_order',
                params: {'item_name': found.itemName},
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Item "${found.itemName}" is out of stock'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      _barcodeController.text = barcode;
    }

    _searchFocusNode.requestFocus();
  }

  // ──────────────────────────────────────────────────────────────
  //                        HELPER METHODS
  // ──────────────────────────────────────────────────────────────

  Future<void> fetchCategories() async {
    final storeId = await _getStoreId();
    setState(() => isLoading = true);
    try {
      final categories = await _categoryDb.getCategories(storeId);
      if (mounted) {
        setState(() {
          displayGroups = categories;
          displayItems = [];
          isShowingSubcategories = false;
          selectedCategory = null;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchSubcategories(String categoryCode) async {
    final storeId = await _getStoreId();
    setState(() => isLoading = true);
    try {
      final allCategories = await _categoryDb.getCategories(storeId);
      final subcats = allCategories
          .where(
            (c) =>
                c.mainGroup == categoryCode && c.categoryCode != categoryCode,
          )
          .toList();

      if (subcats.isEmpty) {
        final items = await _itemDb.getItemsByCategory(categoryCode, storeId);
        if (mounted) {
          setState(() {
            displayItems = items;
            selectedCategory = categoryCode;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            displayGroups = subcats;
            displayItems = [];
            isShowingSubcategories = true;
            selectedCategory = categoryCode;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<List<Item>> _getAllItems() async {
    final storeId = await _getStoreId();
    return await _itemDb.getItems(storeId);
  }

  void _incrementQuantity(Item item) {
    setState(() => item.quantity += 1);
    _searchFocusNode.requestFocus();
  }

  void _decrementQuantity(Item item) {
    setState(() {
      if (item.quantity > 1) {
        item.quantity -= 1;
      } else {
        orderItems.remove(item);
      }
    });
    _searchFocusNode.requestFocus();
  }

  void _setQuantity(Item item, String value) {
    final qty = int.tryParse(value) ?? 1;
    setState(() {
      if (qty <= 0) {
        orderItems.remove(item);
      } else {
        item.quantity = qty;
      }
    });
    _searchFocusNode.requestFocus();
  }

  void _removeFromOrder(Item item) {
    setState(() => orderItems.remove(item));
    _searchFocusNode.requestFocus();
  }

  TextEditingController _getQuantityController(Item item) {
    return _quantityControllers.putIfAbsent(
      item.itemCode,
      () =>
          TextEditingController(text: item.quantity.toString())
            ..addListener(() {
              final text = _quantityControllers[item.itemCode]!.text.trim();
              if (text.isEmpty) return;
              final qty = int.tryParse(text);
              if (qty != null && qty != item.quantity) {
                setState(() {
                  item.quantity = qty.clamp(1, 9999);
                });
              }
            }),
    );
  }

  void addItemToOrder(Item item) {
    setState(() {
      final existingIndex = orderItems.indexWhere(
        (i) => i.itemCode == item.itemCode,
      );
      if (existingIndex != -1) {
        orderItems[existingIndex] = orderItems[existingIndex].copyWith(
          quantity: orderItems[existingIndex].quantity + 1,
        );
      } else {
        orderItems.add(item.copyWith(quantity: 1));
      }
    });
  }

  // ──────────────────────────────────────────────────────────────
  //                              BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isArabic = localizations.translate('settings') == 'الإعدادات';

    final subtotal = orderItems.fold<double>(
      0.0,
      (sum, i) => sum + i.salesPrice * i.quantity,
    );
    final serviceCharge = _applyServiceCharge ? _serviceChargeAmount : 0.0;
    final total = subtotal + serviceCharge;

    return SafeArea(
      child: BarcodeKeyboardListener(
        onBarcodeScanned: _handleScannedBarcode,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              '${localizations.translate('welcome')}, ${widget.name} '
              '(Role: ${_userRole ?? "loading..."})',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _fetchData,
                tooltip: localizations.translate('refresh_data'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: ElevatedButton.icon(
                  onPressed: _toggleShift,
                  icon: Icon(isShiftOpen ? Icons.lock_open : Icons.lock),
                  label: Text(
                    isShiftOpen
                        ? localizations.translate('close_shift')
                        : localizations.translate('open_shift'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (isAuthenticated)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ElevatedButton.icon(
                    icon: isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload, size: 20),
                    label: Text(isSyncing ? 'Syncing...' : 'Save & Sync'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isSyncing
                        ? null
                        : () async {
                            // Show the choice dialog
                            final choice = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text("Save Options"),
                                content: const Text(
                                  "What would you like to do?",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, "upload"),
                                    child: const Text(
                                      "Upload to Cloud (save my changes)",
                                    ),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    onPressed: () async {
                                      // Extra confirmation for dangerous action
                                      final really = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text(
                                            "DANGER – DATA LOSS",
                                            style: TextStyle(color: Colors.red),
                                          ),
                                          content: const Text(
                                            "This will COMPLETELY ERASE all local data on this device\n"
                                            "and replace it with the cloud version.\n\n"
                                            "There is NO UNDO.\n\nContinue?",
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text("No! Cancel"),
                                            ),
                                            TextButton(
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.red,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const Text(
                                                "Yes, replace everything",
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (really == true) {
                                        Navigator.pop(context, "download");
                                      }
                                    },
                                    child: const Text(
                                      "Download & REPLACE local",
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("Cancel"),
                                  ),
                                ],
                              ),
                            );

                            if (choice == null || !mounted) return;

                            setState(() => isSyncing = true);

                            bool success = false;

                            try {
                              if (choice == "upload") {
                                success = await _syncService
                                    .performFullLocalToCloudSync();
                              } else if (choice == "download") {
                                success = await _syncService
                                    .performFullCloudToLocalReplace();

                                // Very important: Reload UI after successful replace
                                if (success) {
                                  await _loadInitialData();
                                  await _fetchLatestOrderNumber();
                                }
                              }
                            } catch (e) {
                              debugPrint("Sync failed: $e");
                            } finally {
                              if (mounted) {
                                setState(() => isSyncing = false);

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      success
                                          ? (choice == "upload"
                                                ? "Upload completed ✓"
                                                : "Data restored from cloud ✓")
                                          : "Operation failed. Check connection.",
                                    ),
                                    backgroundColor: success
                                        ? Colors.green
                                        : Colors.red,
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            }
                          },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: ElevatedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: Text(localizations.translate('logout')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  decoration: InputDecoration(
                                    hintText: localizations.translate('search'),
                                    prefixIcon: const Icon(Icons.search),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                  ),
                                  onChanged: (value) async {
                                    if (value.isEmpty) {
                                      await fetchCategories();
                                      return;
                                    }
                                    final items = await _getAllItems();
                                    setState(() {
                                      displayItems = items
                                          .where(
                                            (i) =>
                                                i.itemName
                                                    .toLowerCase()
                                                    .contains(
                                                      value.toLowerCase(),
                                                    ) ||
                                                (i.barcode?.contains(value) ??
                                                    false),
                                          )
                                          .toList();
                                      displayGroups = [];
                                      isShowingSubcategories = false;
                                      selectedCategory = null;
                                    });
                                  },
                                  onSubmitted: _handleSearchSubmit,
                                ),
                                const SizedBox(height: 16),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  reverse: isArabic,
                                  child: Row(
                                    children: [
                                      if (isShowingSubcategories)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8.0,
                                            vertical: 4.0,
                                          ),
                                          child: OutlinedButton(
                                            onPressed: () {
                                              fetchCategories();
                                              _searchFocusNode.requestFocus();
                                            },
                                            child: Text(
                                              localizations.translate('back'),
                                            ),
                                          ),
                                        ),
                                      ...displayGroups.map((group) {
                                        final isSelected =
                                            selectedCategory ==
                                            group.categoryCode;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8.0,
                                            vertical: 4.0,
                                          ),
                                          child: Card(
                                            elevation: 3,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                InkWell(
                                                  onTap: () =>
                                                      fetchSubcategories(
                                                        group.categoryCode,
                                                      ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 24,
                                                          vertical: 14,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      color: isSelected
                                                          ? theme.primaryColor
                                                                .withOpacity(
                                                                  0.9,
                                                                )
                                                          : theme.primaryColor,
                                                    ),
                                                    child: Text(
                                                      group.categoryName,
                                                      style: theme
                                                          .textTheme
                                                          .labelLarge
                                                          ?.copyWith(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                                if ((_userRole ?? 'guest')
                                                            .toLowerCase() ==
                                                        'admin' ||
                                                    (_userRole ?? 'guest')
                                                            .toLowerCase() ==
                                                        'local')
                                                  Positioned(
                                                    top: -8,
                                                    right: -8,
                                                    child: GestureDetector(
                                                      onTap: () =>
                                                          _confirmDeleteCategory(
                                                            group,
                                                          ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              6,
                                                            ),
                                                        decoration:
                                                            BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              color: Colors.red
                                                                  .withOpacity(
                                                                    0.85,
                                                                  ),
                                                            ),
                                                        child: const Icon(
                                                          Icons.delete,
                                                          size: 20,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: AbsorbPointer(
                                    absorbing: !isShiftOpen,
                                    child: displayItems.isNotEmpty
                                        ? GridView.builder(
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 4,
                                                  childAspectRatio: 1.15,
                                                  crossAxisSpacing: 12,
                                                  mainAxisSpacing: 12,
                                                ),
                                            itemCount: displayItems.length,
                                            itemBuilder: (context, index) {
                                              final item = displayItems[index];
                                              final isOutOfStock =
                                                  item.stockQuantity <= 0;
                                              final isLowStock =
                                                  item.minStockLevel > 0 &&
                                                  item.stockQuantity <=
                                                      item.minStockLevel &&
                                                  !isOutOfStock;

                                              return GestureDetector(
                                                onTap:
                                                    isShiftOpen && !isOutOfStock
                                                    ? () => addItemToOrder(item)
                                                    : null,
                                                child: Card(
                                                  elevation: isOutOfStock
                                                      ? 1
                                                      : 4,
                                                  color: isOutOfStock
                                                      ? Colors.grey[200]
                                                      : (isLowStock
                                                            ? Colors.orange[50]
                                                            : null),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Stack(
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              12.0,
                                                            ),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Expanded(
                                                              child: Center(
                                                                child: Text(
                                                                  item.itemName,
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                  maxLines: 2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: TextStyle(
                                                                    color:
                                                                        isOutOfStock
                                                                        ? Colors
                                                                              .grey[600]
                                                                        : null,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            Text(
                                                              '\$${item.salesPrice.toStringAsFixed(2)}',
                                                              style: TextStyle(
                                                                color:
                                                                    isOutOfStock
                                                                    ? Colors
                                                                          .grey
                                                                    : Colors
                                                                          .green,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            _buildStockBadge(
                                                              item,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      if ((_userRole ?? 'guest')
                                                                  .toLowerCase() ==
                                                              'admin' ||
                                                          (_userRole ?? 'guest')
                                                                  .toLowerCase() ==
                                                              'local')
                                                        Positioned(
                                                          top: 8,
                                                          right: 8,
                                                          child: Column(
                                                            children: [
                                                              GestureDetector(
                                                                onTap: () =>
                                                                    _confirmEditItem(
                                                                      item,
                                                                    ),
                                                                child: Container(
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        6,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    shape: BoxShape
                                                                        .circle,
                                                                    color: Colors
                                                                        .blue
                                                                        .withOpacity(
                                                                          0.85,
                                                                        ),
                                                                  ),
                                                                  child: const Icon(
                                                                    Icons.edit,
                                                                    size: 20,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              GestureDetector(
                                                                onTap: () =>
                                                                    _confirmDeleteItem(
                                                                      item,
                                                                    ),
                                                                child: Container(
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        6,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    shape: BoxShape
                                                                        .circle,
                                                                    color: Colors
                                                                        .red
                                                                        .withOpacity(
                                                                          0.85,
                                                                        ),
                                                                  ),
                                                                  child: const Icon(
                                                                    Icons
                                                                        .delete,
                                                                    size: 20,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          )
                                        : Center(
                                            child: Text(
                                              localizations.translate(
                                                displayGroups.isEmpty
                                                    ? 'no_categories'
                                                    : 'select_category',
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 350,
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            border: Border(
                              left: BorderSide(color: theme.dividerColor),
                            ),
                          ),
                          child: AbsorbPointer(
                            absorbing: !isShiftOpen,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Order #$curOrderNumber',
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _applyServiceCharge
                                            ? Icons.monetization_on
                                            : Icons.monetization_on_outlined,
                                        color: _applyServiceCharge
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      onPressed: _showServiceChargeDialog,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: orderItems.isEmpty
                                      ? Center(
                                          child: Text(
                                            localizations.translate(
                                              'no_items_in_order',
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: orderItems.length,
                                          itemBuilder: (context, index) {
                                            final item = orderItems[index];
                                            final quantityCtrl =
                                                TextEditingController(
                                                  text: item.quantity
                                                      .toString(),
                                                );
                                            return Dismissible(
                                              key: Key(item.itemCode),
                                              direction: isArabic
                                                  ? DismissDirection.startToEnd
                                                  : DismissDirection.endToStart,
                                              onDismissed: (_) =>
                                                  _removeFromOrder(item),
                                              child: Card(
                                                child: ListTile(
                                                  title: Text(item.itemName),
                                                  subtitle: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          IconButton(
                                                            icon: const Icon(
                                                              Icons
                                                                  .remove_circle_outline,
                                                            ),
                                                            onPressed: () =>
                                                                _decrementQuantity(
                                                                  item,
                                                                ),
                                                          ),
                                                          SizedBox(
                                                            width: 60,
                                                            child: TextField(
                                                              controller:
                                                                  _getQuantityController(
                                                                    item,
                                                                  ),
                                                              keyboardType:
                                                                  TextInputType
                                                                      .number,
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              decoration: const InputDecoration(
                                                                contentPadding:
                                                                    EdgeInsets.symmetric(
                                                                      vertical:
                                                                          8,
                                                                    ),
                                                                border:
                                                                    OutlineInputBorder(),
                                                              ),
                                                              onSubmitted: (v) {
                                                                final qty =
                                                                    int.tryParse(
                                                                      v.trim(),
                                                                    ) ??
                                                                    item.quantity;
                                                                setState(() {
                                                                  item.quantity =
                                                                      qty.clamp(
                                                                        1,
                                                                        9999,
                                                                      );
                                                                });
                                                                // Force controller to show clamped value
                                                                _getQuantityController(
                                                                  item,
                                                                ).text = item
                                                                    .quantity
                                                                    .toString();
                                                              },
                                                            ),
                                                          ),
                                                          IconButton(
                                                            icon: const Icon(
                                                              Icons
                                                                  .add_circle_outline,
                                                            ),
                                                            onPressed: () =>
                                                                _incrementQuantity(
                                                                  item,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      Text(
                                                        '\$${(item.salesPrice * item.quantity).toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          color: Colors.green,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                                const SizedBox(height: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    buildSummaryRow(
                                      context,
                                      localizations.translate('subtotal'),
                                      '\$${subtotal.toStringAsFixed(2)}',
                                    ),
                                    if (_applyServiceCharge)
                                      buildSummaryRow(
                                        context,
                                        localizations.translate(
                                          'service_charge',
                                        ),
                                        '\$${serviceCharge.toStringAsFixed(2)}',
                                      ),
                                    buildSummaryRow(
                                      context,
                                      localizations.translate('total'),
                                      '\$${total.toStringAsFixed(2)}',
                                      isTotal: true,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: orderItems.isNotEmpty
                                          ? holdOrder
                                          : null,
                                      icon: const Icon(Icons.pause),
                                      label: Text(
                                        localizations.translate('hold'),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: heldOrders.isNotEmpty
                                          ? getHeldOrders
                                          : null,
                                      icon: const Icon(Icons.get_app),
                                      label: Text(
                                        localizations.translate('get'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed:
                                            orderItems.isNotEmpty && isShiftOpen
                                            ? _checkout
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              (orderItems.isEmpty ||
                                                  !isShiftOpen)
                                              ? Colors.grey
                                              : null,
                                        ),
                                        child: Text(
                                          localizations.translate(
                                            'pay_with_cash',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed:
                                            orderItems.isNotEmpty && isShiftOpen
                                            ? _checkout
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              (orderItems.isEmpty ||
                                                  !isShiftOpen)
                                              ? Colors.grey
                                              : null,
                                        ),
                                        child: Text(
                                          localizations.translate(
                                            'pay_with_card',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
              if (_isAdding)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Container(
                      width: 400,
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isEditing
                                ? localizations.translate('edit_item')
                                : localizations.translate('new_item'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: localizations.translate('item_name'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: localizations.translate('price'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _barcodeController,
                            enabled: !_isEditing,
                            decoration: InputDecoration(
                              labelText: localizations.translate('barcode'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedCategory,
                            decoration: InputDecoration(
                              labelText: localizations.translate('category'),
                              border: const OutlineInputBorder(),
                            ),
                            items: displayGroups
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.categoryCode,
                                    child: Text(c.categoryName),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => selectedCategory = v),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ElevatedButton(
                                onPressed: () =>
                                    setState(() => _isAdding = false),
                                child: Text(localizations.translate('cancel')),
                              ),
                              ElevatedButton(
                                onPressed: _saveNewItem,
                                child: Text(
                                  localizations.translate(
                                    _isEditing ? 'update' : 'save',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Clean up quantity controllers
    for (var ctrl in _quantityControllers.values) {
      ctrl.dispose();
    }
    _quantityControllers.clear();

    _firebaseSub?.cancel();
    _nameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    _searchController.dispose();
    _serviceChargeController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
}
