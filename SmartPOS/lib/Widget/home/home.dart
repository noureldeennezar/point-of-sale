import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_barcode_listener/flutter_barcode_listener.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../Core/app_localizations.dart';
import '../../cloud_services/AuthService.dart';
import '../../cloud_services/item_service.dart';
import '../../cloud_services/shift_service.dart';
import '../../local_services/ItemDatabaseHelper.dart';
import '../../models/Catgeory.dart';
import '../../models/Item.dart';
import '../../models/Order.dart' as OrderModel;
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
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ShiftService _shiftService = ShiftService(context: null);
  final ItemDatabaseHelper _itmdbHelper = ItemDatabaseHelper();
  final ItemService _itemService = ItemService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String? selectedCategory;
  List<Category> displayGroups = [];
  List<Item> displayItems = [];
  List<Item> orderItems = [];
  List<List<Item>> heldOrders = [];
  bool isShiftOpen = false;
  bool isShowingSubcategories = false;
  bool isLoading = false;
  bool _isAdding = false;
  bool _isEditing = false;
  String? _activeShiftId;
  String? _userRole;
  Item? _editingItem;
  int curOrderNumber = 1;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _checkActiveShift();
    _syncOfflineData();
    _fetchLatestOrderNumber();

    _shiftService.fixExistingShift('YOUR_SHIFT_ID').then((_) {
      _shiftService.getActiveShift().then((activeShift) {
        if (activeShift != null &&
            activeShift['status'] == 'open' &&
            activeShift['endTime'] != null) {
          _firestore
              .collection('shifts')
              .doc(activeShift['id'])
              .update({
                'endTime': null,
              })
              .then(
                  (_) => print('Fixed endTime for shift ${activeShift['id']}'))
              .catchError((e) => print('Error fixing endTime: $e'));
        }
      });
    });

    Provider.of<AuthService>(context, listen: false)
        .currentUserWithRole
        .listen((userData) {
      setState(() {
        _userRole = userData?['role'];
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  Future<void> _fetchLatestOrderNumber() async {
    try {
      final latestOrderId = await _itmdbHelper.getLatestOrderId();
      setState(() {
        curOrderNumber = latestOrderId + 1;
      });
    } catch (e) {}
  }

  Future<void> _fetchData() async {
    setState(() => isLoading = true);
    try {
      await fetchCategories();
      await _fetchLatestOrderNumber();
    } catch (e) {}
    setState(() => isLoading = false);
  }

  Future<void> _checkActiveShift() async {
    try {
      final shift = await _shiftService.getActiveShift();
      setState(() {
        isShiftOpen = shift != null;
        _activeShiftId = shift?['id'];
      });
    } catch (e) {}
  }

  Future<void> _syncOfflineData() async {
    setState(() => isLoading = true);
    try {
      await _shiftService.syncOfflineShifts();
      await _syncItemsAndCategories();
      await _fetchData();
      await _checkActiveShift();
      await _fetchLatestOrderNumber();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              'failed_to_sync_data',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
    setState(() => isLoading = false);
  }

  Future<void> _syncItemsAndCategories() async {
    try {
      final categorySnapshot = await _firestore.collection('categories').get();
      final itemSnapshot = await _firestore.collection('items').get();

      final categories = categorySnapshot.docs
          .map((doc) => Category.fromMap(doc.data()))
          .toList();
      final items =
          itemSnapshot.docs.map((doc) => Item.fromMap(doc.data())).toList();

      // Only clear items and categories, preserve orders
      await _itmdbHelper.clearItemsAndCategories();

      for (var category in categories) {
        await _itmdbHelper.insertOrUpdateCategory(category);
      }
      for (var item in items) {
        await _itmdbHelper.insertOrUpdateItem(item);
      }

      await _syncOfflineItemsToFirebase();
      await _syncOfflineCategoriesToFirebase();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              'failed_to_sync_data',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
  }

  Future<void> _syncOfflineItemsToFirebase() async {
    final queue = await _itmdbHelper.getSyncQueue();
    for (var entry in queue) {
      try {
        final itemData = jsonDecode(entry['item_data']);
        final item = Item.fromMap(itemData);
        await _firestore
            .collection('items')
            .doc(item.itemCode)
            .set(item.toMap());
        await _itmdbHelper.clearSyncQueue(item.itemCode);
      } catch (e) {
        continue;
      }
    }
  }

  Future<void> _syncOfflineCategoriesToFirebase() async {
    final queue = await _itmdbHelper.getCategorySyncQueue();
    for (var entry in queue) {
      try {
        final categoryData = jsonDecode(entry['category_data']);
        final category = Category.fromMap(categoryData);
        await _firestore
            .collection('categories')
            .doc(category.categoryCode)
            .set(category.toMap());
        await _itmdbHelper.clearCategorySyncQueue(category.categoryCode);
      } catch (e) {
        continue;
      }
    }
  }

  Future<void> _deleteCategory(Category category) async {
    if (_userRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).translate('admin_only_action')),
        ),
      );
      return;
    }
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context).translate('confirm_delete')),
        content: Text(
          AppLocalizations.of(context).translate('delete_category_confirm',
              params: {'category_name': category.categoryName}),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              _searchFocusNode.requestFocus();
            },
            child: Text(AppLocalizations.of(context).translate('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
              _searchFocusNode.requestFocus();
            },
            child: Text(AppLocalizations.of(context).translate('delete')),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      try {
        final connectivityResult = await Connectivity().checkConnectivity();
        bool isOnline = connectivityResult != ConnectivityResult.none;

        await _itmdbHelper.deleteCategory(category.categoryCode);

        if (isOnline) {
          await _firestore
              .collection('categories')
              .doc(category.categoryCode)
              .delete();
          final itemsSnapshot = await _firestore
              .collection('items')
              .where('itm_group_code', isEqualTo: category.categoryCode)
              .get();
          for (var doc in itemsSnapshot.docs) {
            await doc.reference.delete();
          }
          final subcategoriesSnapshot = await _firestore
              .collection('categories')
              .where('main_group', isEqualTo: category.categoryCode)
              .get();
          for (var doc in subcategoriesSnapshot.docs) {
            await doc.reference.delete();
          }
        } else {
          await _itmdbHelper.queueCategoryForSync(category, 'delete');
        }

        setState(() {
          displayGroups.remove(category);
          if (selectedCategory == category.categoryCode) {
            displayItems = [];
            selectedCategory = null;
            isShowingSubcategories = false;
          }
          orderItems.removeWhere(
              (item) => item.itmGroupCode == category.categoryCode);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate(
                'category_deleted',
                params: {'category_name': category.categoryName},
              ),
            ),
          ),
        );
        await fetchCategories();
        _searchFocusNode.requestFocus();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate(
                'failed_to_delete_category',
                params: {'error': e.toString()},
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteItem(Item item) async {
    if (_userRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).translate('admin_only_action')),
        ),
      );
      return;
    }
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context).translate('confirm_delete')),
        content: Text(
          AppLocalizations.of(context).translate('delete_item_confirm',
              params: {'item_name': item.itemName}),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              _searchFocusNode.requestFocus();
            },
            child: Text(AppLocalizations.of(context).translate('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
              _searchFocusNode.requestFocus();
            },
            child: Text(AppLocalizations.of(context).translate('delete')),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      try {
        final connectivityResult = await Connectivity().checkConnectivity();
        bool isOnline = connectivityResult != ConnectivityResult.none;

        await _itmdbHelper.deleteItem(item.itemCode);

        if (isOnline) {
          await _firestore.collection('items').doc(item.itemCode).delete();
        } else {
          await _itmdbHelper.queueItemForSync(item, 'delete');
        }

        setState(() {
          displayItems.remove(item);
          orderItems
              .removeWhere((orderItem) => orderItem.itemCode == item.itemCode);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate(
                'item_deleted',
                params: {'item_name': item.itemName},
              ),
            ),
          ),
        );
        _searchFocusNode.requestFocus();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate(
                'failed_to_delete_item',
                params: {'error': e.toString()},
              ),
            ),
          ),
        );
      }
    }
  }

  void openShift() async {
    try {
      final shiftId = await _shiftService.openShift();
      if (shiftId != null) {
        setState(() {
          isShiftOpen = true;
          _activeShiftId = shiftId;
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
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context).translate('failed_to_open_shift')),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              'failed_to_open_shift',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
  }

  void closeShift() async {
    if (_activeShiftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).translate('no_shift_to_close')),
        ),
      );
      return;
    }

    double? finalCashCount;
    await showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(AppLocalizations.of(context).translate('close_shift')),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText:
                  AppLocalizations.of(context).translate('final_cash_count'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _searchFocusNode.requestFocus();
              },
              child: Text(AppLocalizations.of(context).translate('cancel')),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                finalCashCount = value;
                Navigator.pop(context);
                _searchFocusNode.requestFocus();
              },
              child: Text(AppLocalizations.of(context).translate('confirm')),
            ),
          ],
        );
      },
    );

    if (finalCashCount != null) {
      try {
        final success = await _shiftService.closeShift(_activeShiftId!,
            finalCashCount: finalCashCount);
        if (success) {
          // Reset order number sequence in the database
          await _itmdbHelper.resetOrderSequence();
          setState(() {
            isShiftOpen = false;
            _activeShiftId = null;
            curOrderNumber = 1; // Reset UI order number
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
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)
                  .translate('failed_to_close_shift')),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate(
                'failed_to_close_shift',
                params: {'error': e.toString()},
              ),
            ),
          ),
        );
      }
    }
  }

  void holdOrder() {
    if (orderItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).translate('no_items_to_hold')),
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
          content:
              Text(AppLocalizations.of(context).translate('no_held_orders')),
        ),
      );
      return;
    }

    final selectedOrderIndex = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            Text(AppLocalizations.of(context).translate('select_held_order')),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: heldOrders.length,
            itemBuilder: (context, index) {
              final order = heldOrders[index];
              final orderTotal = order.fold<double>(0,
                  (total, item) => total + (item.salesPrice * item.quantity));
              return ListTile(
                title: Text('Order #${index + 1}'),
                subtitle: Text(
                    '${order.length} items - \$${orderTotal.toStringAsFixed(2)}'),
                onTap: () => Navigator.pop(context, index),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _searchFocusNode.requestFocus();
            },
            child: Text(AppLocalizations.of(context).translate('cancel')),
          ),
        ],
      ),
    );

    if (selectedOrderIndex != null) {
      setState(() {
        orderItems = List.from(heldOrders[selectedOrderIndex]);
        heldOrders.removeAt(selectedOrderIndex);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).translate('order_retrieved')),
        ),
      );
      _searchFocusNode.requestFocus();
    }
  }

  Future<void> checkout() async {
    try {
      if (orderItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context).translate('no_items_to_checkout')),
          ),
        );
        return;
      }

      if (_activeShiftId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).translate('no_active_shift')),
          ),
        );
        return;
      }

      double subtotal = orderItems.fold<double>(
          0, (total, item) => total + (item.salesPrice * item.quantity));
      double serviceCharge = subtotal * 0.10;
      double tax = subtotal * 0.10;
      double total = subtotal + serviceCharge + tax;

      final items = orderItems
          .map((item) => {
                'itemCode': item.itemCode,
                'itemName': item.itemName,
                'salesPrice': item.salesPrice,
                'quantity': item.quantity,
              })
          .toList();

      final txnId = await _shiftService.addTransaction(
        shiftId: _activeShiftId!,
        items: items,
        subtotal: subtotal,
        serviceCharge: serviceCharge,
        tax: tax,
        total: total,
        paymentMethod: 'cash',
      );

      if (txnId != null) {
        OrderModel.Order order = OrderModel.Order(
          items: List.from(orderItems),
          date: DateTime.now().toIso8601String(),
        );
        final dbHelper = ItemDatabaseHelper();
        final orderId = await dbHelper.insertOrder(order);
        setState(() {
          orderItems.clear();
          curOrderNumber++;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)
                .translate('order_checked_out_success')),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context).translate('failed_to_checkout')),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              'failed_to_checkout',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
    _searchFocusNode.requestFocus();
  }

  Future<void> fetchCategories() async {
    setState(() => isLoading = true);
    try {
      List<Category> categories = await getCategories();
      setState(() {
        displayGroups = categories;
        displayItems = [];
        isShowingSubcategories = false;
        selectedCategory = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              'failed_to_fetch_categories',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
    setState(() => isLoading = false);
  }

  Future<void> fetchSubcategories(String categoryCode) async {
    setState(() => isLoading = true);
    try {
      List<Category> subcategories = await getSubcategories(categoryCode);
      if (subcategories.isEmpty) {
        List<Item> items = await getItems(categoryCode);
        setState(() {
          displayItems = items;
          selectedCategory = categoryCode;
        });
      } else {
        setState(() {
          displayGroups = subcategories;
          displayItems = [];
          isShowingSubcategories = true;
          selectedCategory = categoryCode;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              'failed_to_fetch_subcategories',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
    setState(() => isLoading = false);
  }

  Future<List<Category>> getCategories() async {
    try {
      return await _itmdbHelper.getItemGroups();
    } catch (e) {
      return [];
    }
  }

  Future<List<Category>> getSubcategories(String categoryCode) async {
    try {
      final allItems = await _itmdbHelper.getItemGroups();
      return allItems
          .where((item) =>
              item.mainGroup == categoryCode &&
              item.categoryCode != item.mainGroup)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Item>> getItems(String categoryCode) async {
    try {
      final allItems = await _itmdbHelper.getItems();
      return allItems
          .where((item) => item.itmGroupCode == categoryCode)
          .toList();
    } catch (e) {
      return [];
    }
  }

  void _incrementQuantity(Item item) {
    setState(() {
      item.quantity += 1;
    });
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

  void _removeFromOrder(Item item) {
    setState(() {
      orderItems.remove(item);
    });
    _searchFocusNode.requestFocus();
  }

  void addItemToOrder(Item item) {
    setState(() {
      final existingItem = orderItems.firstWhere(
        (orderItem) => orderItem.itemCode == item.itemCode,
        orElse: () => Item(
          itemCode: '',
          itemName: '',
          salesPrice: 0,
          itmGroupCode: 'default',
          quantity: 0,
        ),
      );

      if (existingItem.itemCode != '') {
        existingItem.quantity += 1;
      } else {
        orderItems.add(Item(
          itemCode: item.itemCode,
          itemName: item.itemName,
          salesPrice: item.salesPrice,
          itmGroupCode: item.itmGroupCode,
          barcode: item.barcode,
          isActive: item.isActive,
          quantity: 1,
        ));
      }
    });
  }

  Future<void> _handleScannedBarcode(String barcode) async {
    if (!_isAdding && isShiftOpen) {
      barcode = barcode.trim();
      final items = await _itmdbHelper.getItems();
      final existingItem = items.firstWhere(
        (item) => item.barcode == barcode,
        orElse: () => Item(
          itemCode: '',
          itemName: '',
          salesPrice: 0,
          itmGroupCode: 'default',
          quantity: 0,
        ),
      );

      if (existingItem.itemCode != '') {
        addItemToOrder(existingItem);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate(
                'item_added_to_order',
                params: {'item_name': existingItem.itemName})),
          ),
        );
        _searchController.clear();
        _searchFocusNode.requestFocus();
      } else {
        _barcodeController.text = barcode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).translate('item_not_found')),
            action: SnackBarAction(
              label: AppLocalizations.of(context).translate('add_new_item'),
              onPressed: () {
                setState(() {
                  _isAdding = true;
                  _searchController.clear();
                  _searchFocusNode.requestFocus();
                });
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleSearchSubmit(String value) async {
    if (!_isAdding && isShiftOpen && value.isNotEmpty) {
      value = value.trim();
      final items = await _itmdbHelper.getItems();
      final existingItem = items.firstWhere(
        (item) =>
            item.barcode == value ||
            item.itemName.toLowerCase() == value.toLowerCase(),
        orElse: () => Item(
          itemCode: '',
          itemName: '',
          salesPrice: 0,
          itmGroupCode: 'default',
          quantity: 0,
        ),
      );

      if (existingItem.itemCode != '') {
        addItemToOrder(existingItem);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate(
                'item_added_to_order',
                params: {'item_name': existingItem.itemName})),
          ),
        );
        setState(() {
          _searchController.clear();
          displayItems = [];
          displayGroups = [];
          isShowingSubcategories = false;
          selectedCategory = null;
        });
        _searchFocusNode.requestFocus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).translate('item_not_found')),
            action: SnackBarAction(
              label: AppLocalizations.of(context).translate('add_new_item'),
              onPressed: () {
                setState(() {
                  _isAdding = true;
                  _barcodeController.text = value;
                  _searchController.clear();
                });
                _searchFocusNode.requestFocus();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveNewItem() async {
    if (_nameController.text.isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).translate('fill_all_fields')),
        ),
      );
      return;
    }
    double? price = double.tryParse(_priceController.text);
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).translate('invalid_price')),
        ),
      );
      return;
    }
    final String itmGroupCode = selectedCategory ??
        (displayGroups.isNotEmpty
            ? displayGroups.first.categoryCode
            : 'default');
    final item = Item(
      itemCode: _isEditing
          ? _editingItem!.itemCode
          : DateTime.now().millisecondsSinceEpoch.toString(),
      itemName: _nameController.text,
      salesPrice: price,
      itmGroupCode: itmGroupCode,
      barcode: _barcodeController.text,
      isActive: true,
      quantity: 1,
    );
    try {
      await _itemService.addOrUpdateItem(item);
      if (_isEditing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate('item_updated',
                params: {'item_name': item.itemName})),
          ),
        );
      } else {
        addItemToOrder(item);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate(
                'item_added_to_order',
                params: {'item_name': item.itemName})),
          ),
        );
      }
      setState(() {
        _isAdding = false;
        _isEditing = false;
        _editingItem = null;
        _nameController.clear();
        _priceController.clear();
        _barcodeController.clear();
      });
      await fetchCategories();
      _searchFocusNode.requestFocus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              _isEditing ? 'failed_to_update_item' : 'failed_to_save_item',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
  }

  void _editItem(Item item) {
    if (_userRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).translate('admin_only_action')),
        ),
      );
      return;
    }
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

  Future<void> _signOut() async {
    try {
      await Provider.of<AuthService>(context, listen: false).signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              'failed_to_sign_out',
              params: {'error': e.toString()},
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isArabic = localizations.translate('settings') == 'الإعدادات';
    double subtotal = orderItems.fold<double>(
        0, (total, item) => total + (item.salesPrice * item.quantity));
    double serviceCharge = subtotal * 0.10;
    double tax = subtotal * 0.10;
    double total = subtotal + serviceCharge + tax;

    return SafeArea(
      child: BarcodeKeyboardListener(
        onBarcodeScanned: _handleScannedBarcode,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              '${localizations.translate('welcome')}, ${widget.name}',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            actions: [
              if (_userRole == 'admin')
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _syncOfflineData,
                  tooltip: localizations.translate('refresh_data'),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: ElevatedButton.icon(
                  onPressed: isShiftOpen ? closeShift : openShift,
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
                        borderRadius: BorderRadius.circular(12)),
                  ),
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
                        borderRadius: BorderRadius.circular(12)),
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
                                    hintStyle: TextStyle(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search,
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.grey[400]
                                          : theme.iconTheme.color,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color:
                                            theme.brightness == Brightness.dark
                                                ? Colors.grey[700]!
                                                : Colors.grey[300]!,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color:
                                            theme.brightness == Brightness.dark
                                                ? Colors.grey[700]!
                                                : Colors.grey[300]!,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: theme.primaryColor,
                                        width: 2,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor:
                                        theme.brightness == Brightness.dark
                                            ? Colors.grey[800]
                                            : Colors.grey[100],
                                  ),
                                  style: TextStyle(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                  onChanged: (value) async {
                                    if (value.isEmpty) {
                                      await fetchCategories();
                                    } else {
                                      final items =
                                          await _itmdbHelper.getItems();
                                      setState(() {
                                        displayItems = items
                                            .where((item) =>
                                                item.itemName
                                                    .toLowerCase()
                                                    .contains(
                                                        value.toLowerCase()) ||
                                                (item.barcode != null &&
                                                    item.barcode!
                                                        .contains(value)))
                                            .toList();
                                        displayGroups = [];
                                        isShowingSubcategories = false;
                                        selectedCategory = null;
                                      });
                                    }
                                    _searchFocusNode.requestFocus();
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
                                              horizontal: 8.0, vertical: 4.0),
                                          child: OutlinedButton(
                                            onPressed: () {
                                              fetchCategories();
                                              _searchFocusNode.requestFocus();
                                            },
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(
                                                  color: theme.primaryColor,
                                                  width: 1.5),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12),
                                              textStyle: theme
                                                  .textTheme.labelLarge
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600),
                                              backgroundColor: theme.cardColor,
                                              elevation: 2,
                                            ),
                                            child: Text(
                                              localizations.translate('back'),
                                              style: TextStyle(
                                                  color: theme.primaryColor),
                                            ),
                                          ),
                                        ),
                                      ...displayGroups.map((group) {
                                        final isSelected = selectedCategory ==
                                            group.categoryCode;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8.0, vertical: 4.0),
                                          child: Card(
                                            elevation: 3,
                                            shadowColor: theme.shadowColor
                                                .withOpacity(0.2),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                InkWell(
                                                  onTap: () {
                                                    fetchSubcategories(
                                                        group.categoryCode);
                                                    _searchFocusNode
                                                        .requestFocus();
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  hoverColor: theme.primaryColor
                                                      .withOpacity(0.1),
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 24,
                                                        vertical: 14),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      color: isSelected
                                                          ? theme.primaryColor
                                                              .withOpacity(0.9)
                                                          : theme.primaryColor,
                                                    ),
                                                    child: Text(
                                                      group.categoryName,
                                                      style: theme
                                                          .textTheme.labelLarge
                                                          ?.copyWith(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 16,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                                if (_userRole == 'admin')
                                                  Positioned(
                                                    top: -8,
                                                    right: isArabic ? null : -8,
                                                    left: isArabic ? -8 : null,
                                                    child: Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                        onTap: () {
                                                          _deleteCategory(
                                                              group);
                                                          _searchFocusNode
                                                              .requestFocus();
                                                        },
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(4),
                                                          decoration:
                                                              BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            color: Colors.red
                                                                .withOpacity(
                                                                    0.8),
                                                          ),
                                                          child: const Icon(
                                                            Icons.delete,
                                                            size: 18,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
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
                                              childAspectRatio: 1.2,
                                              crossAxisSpacing: 12,
                                              mainAxisSpacing: 12,
                                            ),
                                            itemCount: displayItems.length,
                                            itemBuilder: (context, itemIndex) {
                                              final item =
                                                  displayItems[itemIndex];
                                              return GestureDetector(
                                                onTap: () {
                                                  if (isShiftOpen) {
                                                    addItemToOrder(item);
                                                    _searchFocusNode
                                                        .requestFocus();
                                                  }
                                                },
                                                child: Card(
                                                  elevation: 4,
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12)),
                                                  child: Stack(
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(12.0),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Expanded(
                                                              child: Center(
                                                                child: Text(
                                                                  item.itemName,
                                                                  style: theme
                                                                      .textTheme
                                                                      .bodyLarge
                                                                      ?.copyWith(
                                                                          fontWeight:
                                                                              FontWeight.w600),
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  maxLines: 2,
                                                                ),
                                                              ),
                                                            ),
                                                            Text(
                                                              '\$${item.salesPrice.toStringAsFixed(2)}',
                                                              style: theme
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .green,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (_userRole == 'admin')
                                                        Positioned(
                                                          top: 8,
                                                          right: 8,
                                                          child: Row(
                                                            children: [
                                                              IconButton(
                                                                icon: const Icon(
                                                                    Icons.edit,
                                                                    size: 20,
                                                                    color: Colors
                                                                        .blue),
                                                                onPressed: () =>
                                                                    _editItem(
                                                                        item),
                                                                tooltip: localizations
                                                                    .translate(
                                                                        'edit_item'),
                                                              ),
                                                              IconButton(
                                                                icon: const Icon(
                                                                    Icons
                                                                        .delete,
                                                                    size: 20,
                                                                    color: Colors
                                                                        .red),
                                                                onPressed: () =>
                                                                    _deleteItem(
                                                                        item),
                                                                tooltip: localizations
                                                                    .translate(
                                                                        'delete_item'),
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
                                                      : 'select_category'),
                                              style: theme.textTheme.bodyLarge,
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
                                left: BorderSide(color: theme.dividerColor)),
                          ),
                          child: AbsorbPointer(
                            absorbing: !isShiftOpen,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Order #$curOrderNumber',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: orderItems.isEmpty
                                      ? Center(
                                          child: Text(
                                            localizations
                                                .translate('no_items_in_order'),
                                            style: theme.textTheme.bodyLarge,
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: orderItems.length,
                                          itemBuilder: (context, index) {
                                            final item = orderItems[index];
                                            return Dismissible(
                                              key: Key(item.itemCode),
                                              direction: isArabic
                                                  ? DismissDirection.startToEnd
                                                  : DismissDirection.endToStart,
                                              background: Container(
                                                color: Colors.red,
                                                alignment: isArabic
                                                    ? Alignment.centerLeft
                                                    : Alignment.centerRight,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 20),
                                                child: const Icon(Icons.delete,
                                                    color: Colors.white),
                                              ),
                                              onDismissed: (direction) {
                                                _removeFromOrder(item);
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      localizations.translate(
                                                        'item_removed_from_order',
                                                        params: {
                                                          'item_name':
                                                              item.itemName
                                                        },
                                                      ),
                                                    ),
                                                    action: SnackBarAction(
                                                      label: localizations
                                                          .translate('undo'),
                                                      onPressed: () {
                                                        setState(() {
                                                          orderItems.insert(
                                                              index, item);
                                                        });
                                                        _searchFocusNode
                                                            .requestFocus();
                                                      },
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Card(
                                                elevation: 2,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                                child: ListTile(
                                                  contentPadding:
                                                      const EdgeInsets.all(8.0),
                                                  title: Text(
                                                    item.itemName,
                                                    style: theme
                                                        .textTheme.bodyMedium
                                                        ?.copyWith(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600),
                                                  ),
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
                                                                size: 20),
                                                            color: theme
                                                                .primaryColor,
                                                            onPressed: () {
                                                              _decrementQuantity(
                                                                  item);
                                                              _searchFocusNode
                                                                  .requestFocus();
                                                            },
                                                          ),
                                                          Text(
                                                            '${item.quantity}',
                                                            style: theme
                                                                .textTheme
                                                                .bodyMedium,
                                                          ),
                                                          IconButton(
                                                            icon: const Icon(
                                                                Icons
                                                                    .add_circle_outline,
                                                                size: 20),
                                                            color: theme
                                                                .primaryColor,
                                                            onPressed: () {
                                                              _incrementQuantity(
                                                                  item);
                                                              _searchFocusNode
                                                                  .requestFocus();
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                      Text(
                                                        '\$${(item.salesPrice * item.quantity).toStringAsFixed(2)}',
                                                        style: theme.textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                                color: Colors
                                                                    .green),
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
                                        '\$${subtotal.toStringAsFixed(2)}'),
                                    buildSummaryRow(
                                        context,
                                        localizations
                                            .translate('service_charge'),
                                        '\$${serviceCharge.toStringAsFixed(2)}'),
                                    buildSummaryRow(
                                        context,
                                        localizations.translate('tax'),
                                        '\$${tax.toStringAsFixed(2)}'),
                                    buildSummaryRow(
                                        context,
                                        localizations.translate('total'),
                                        '\$${total.toStringAsFixed(2)}',
                                        isTotal: true),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: orderItems.isNotEmpty
                                          ? () {
                                              holdOrder();
                                              _searchFocusNode.requestFocus();
                                            }
                                          : null,
                                      icon: const Icon(Icons.pause),
                                      label:
                                          Text(localizations.translate('hold')),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: theme.primaryColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: heldOrders.isNotEmpty
                                          ? () {
                                              getHeldOrders();
                                              _searchFocusNode.requestFocus();
                                            }
                                          : null,
                                      icon: const Icon(Icons.get_app),
                                      label:
                                          Text(localizations.translate('get')),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: theme.primaryColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    checkout();
                                    _searchFocusNode.requestFocus();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    minimumSize: const Size(double.infinity, 0),
                                  ),
                                  child: Text(
                                    localizations.translate('checkout'),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
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
                            AppLocalizations.of(context).translate(
                                _isEditing ? 'edit_item' : 'new_item'),
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)
                                  .translate('item_name'),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)
                                  .translate('price'),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _barcodeController,
                            enabled: !_isEditing,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)
                                  .translate('barcode'),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedCategory,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)
                                  .translate('category'),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            items: displayGroups.isEmpty
                                ? [
                                    DropdownMenuItem(
                                      value: 'default',
                                      enabled: false,
                                      child: Text(AppLocalizations.of(context)
                                          .translate('no_categories')),
                                    ),
                                  ]
                                : displayGroups
                                    .map((category) => DropdownMenuItem(
                                          value: category.categoryCode,
                                          child: Text(category.categoryName),
                                        ))
                                    .toList(),
                            onChanged: displayGroups.isEmpty
                                ? null
                                : (value) {
                                    setState(() {
                                      selectedCategory = value;
                                    });
                                    _searchFocusNode.requestFocus();
                                  },
                            hint: Text(AppLocalizations.of(context)
                                .translate('select_category')),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _isAdding = false;
                                    _isEditing = false;
                                    _editingItem = null;
                                    _nameController.clear();
                                    _priceController.clear();
                                    _barcodeController.clear();
                                  });
                                  _searchFocusNode.requestFocus();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(AppLocalizations.of(context)
                                    .translate('cancel')),
                              ),
                              ElevatedButton(
                                onPressed: _saveNewItem,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(AppLocalizations.of(context)
                                    .translate(_isEditing ? 'update' : 'save')),
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
    _nameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
}
