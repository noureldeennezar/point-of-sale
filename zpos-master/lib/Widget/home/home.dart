import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zpos/Core/app_localizations.dart';
import 'package:zpos/Widget/Order_history.dart';
import 'package:zpos/Widget/settings.dart';
import 'package:zpos/models/MenuItem.dart';
import 'package:zpos/Widget/auth/login.dart';
import 'package:zpos/Widget/shifts/ShiftReportScreen.dart';
import 'package:zpos/local_services/sql_item_helper.dart';
import 'package:zpos/local_services/sql_order_helper.dart';
import 'package:zpos/cloud_services/AuthService.dart';
import 'package:zpos/cloud_services/shift_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'Core/BottomNavBar.dart';
import 'models/Catgeory.dart';

int cur = 1;

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
  final ShiftService _shiftService = ShiftService();
  final AuthService _authService = AuthService();
  final ItemDatabaseHelper _itmdbHelper = ItemDatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? selectedCategory;
  List<ItemGroup> displayGroups = [];
  List<Item> displayItems = [];
  List<Item> orderItems = [];
  List<Item> heldItems = [];
  bool isShiftOpen = false;
  bool isShowingSubcategories = false;
  int _selectedIndex = 0;
  String? _activeShiftId;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    fetchCategories();
    _checkActiveShift();
    _syncOfflineData();

    _shiftService.fixExistingShift('YOUR_SHIFT_ID').then((_) {
      _shiftService.getActiveShift().then((activeShift) {
        if (activeShift != null && activeShift['status'] == 'open' && activeShift['endTime'] != null) {
          _firestore.collection('shifts').doc(activeShift['id']).update({
            'endTime': null,
          }).then((_) => print('Fixed endTime for shift ${activeShift['id']}'))
              .catchError((e) => print('Error fixing endTime: $e'));
        }
      });
    });

    _authService.currentUserWithRole.listen((userData) {
      setState(() {
        _userRole = userData?['role'];
      });
    });
  }

  Future<void> _checkActiveShift() async {
    final shift = await _shiftService.getActiveShift();
    setState(() {
      isShiftOpen = shift != null;
      _activeShiftId = shift?['id'];
    });
  }

  Future<void> _syncOfflineData() async {
    await _shiftService.syncOfflineShifts();
    _checkActiveShift();
  }

  void openShift() async {
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
          content: Text(AppLocalizations.of(context).translate('failed_to_open_shift')),
        ),
      );
    }
  }

  void closeShift() async {
    if (_activeShiftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('no_shift_to_close')),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(AppLocalizations.of(context).translate('close_shift')),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).translate('final_cash_count'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).translate('cancel')), // Fixed missing quote
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                finalCashCount = value;
                Navigator.pop(context);
              },
              child: Text(AppLocalizations.of(context).translate('confirm')),
            ),
          ],
        );
      },
    );
    if (finalCashCount != null) {
      final success = await _shiftService.closeShift(_activeShiftId!, finalCashCount: finalCashCount);
      if (success) {
        setState(() {
          isShiftOpen = false;
          _activeShiftId = null;
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
            content: Text(AppLocalizations.of(context).translate('failed_to_close_shift')),
          ),
        );
      }
    }
  }

  void getHeldOrders() {
    setState(() {
      orderItems = List.from(heldItems);
      heldItems.clear();
    });
  }

  void holdOrder() {
    setState(() {
      heldItems = List.from(orderItems);
      orderItems.clear();
    });
  }

  Future<void> checkout() async {
    try {
      if (orderItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate('no_items_to_checkout')),
          ),
        );
        return;
      }

      if (_activeShiftId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate('no_active_shift')),
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
        Order order = Order(
          orderNumber: null,
          items: List.from(orderItems),
          date: DateTime.now().toString(),
        );
        DBHelper dbHelper = DBHelper();
        int orderId = await dbHelper.insertOrder(order);

        setState(() {
          cur = orderId;
          orderItems.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate('order_checked_out_success')),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate('failed_to_checkout')),
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
  }

  Future<void> fetchCategories() async {
    try {
      List<ItemGroup> categories = await getCategories();
      setState(() {
        displayGroups = categories;
        displayItems = [];
        isShowingSubcategories = false;
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
  }

  Future<void> fetchSubcategories(String categoryCode) async {
    try {
      List<ItemGroup> subcategories = await getSubcategories(categoryCode);
      if (subcategories.isEmpty) {
        List<Item> items = await getItems(categoryCode);
        setState(() {
          displayItems = items;
        });
      } else {
        setState(() {
          displayGroups = subcategories;
          displayItems = [];
          isShowingSubcategories = true;
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
  }

  Future<List<ItemGroup>> getCategories() async {
    try {
      final allItems = await _itmdbHelper.getItemGroups();
      return allItems.where((item) => item.itmGroupCode == item.mainGroup).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ItemGroup>> getSubcategories(String categoryCode) async {
    try {
      final allItems = await _itmdbHelper.getItemGroups();
      return allItems
          .where((item) => item.mainGroup == categoryCode && item.itmGroupCode != item.mainGroup)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Item>> getItems(String categoryCode) async {
    try {
      final allItems = await _itmdbHelper.getItems();
      return allItems.where((item) => item.itmGroupCode == categoryCode).toList();
    } catch (e) {
      return [];
    }
  }

  void _incrementQuantity(Item item) {
    setState(() {
      item.quantity += 1;
    });
  }

  void _decrementQuantity(Item item) {
    setState(() {
      if (item.quantity > 1) {
        item.quantity -= 1;
      } else {
        orderItems.remove(item);
      }
    });
  }

  void _removeFromOrder(Item item) {
    setState(() {
      orderItems.remove(item);
    });
  }

  void addItemToOrder(Item item) {
    setState(() {
      final existingItem = orderItems.firstWhere(
            (orderItem) => orderItem.itemCode == item.itemCode,
        orElse: () => Item(itemCode: '', itemName: '', salesPrice: 0, itmGroupCode: ''),
      );

      if (existingItem.itemCode != '') {
        existingItem.quantity += 1;
      } else {
        orderItems.add(Item(
          itemCode: item.itemCode,
          itemName: item.itemName,
          salesPrice: item.salesPrice,
          itmGroupCode: item.itmGroupCode,
          quantity: 1,
        ));
      }
    });
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    double subtotal = orderItems.fold<double>(
        0, (total, item) => total + (item.salesPrice * item.quantity));
    double serviceCharge = subtotal * 0.10;
    double tax = subtotal * 0.10;
    double total = subtotal + serviceCharge + tax;

    return SafeArea(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            '${localizations.translate('welcome')}, ${widget.name}',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          actions: [
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        body: Row(
          children: [
            // Main Content Area
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search Bar
                    TextField(
                      decoration: InputDecoration(
                        hintText: localizations.translate('search'),
                        prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.inputDecorationTheme.fillColor ?? Colors.grey.shade100,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Categories/Subcategories
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: localizations.translate('settings') == 'الإعدادات',
                      child: Row(
                        children: [
                          if (isShowingSubcategories)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: OutlinedButton(
                                onPressed: fetchCategories,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: theme.primaryColor),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(localizations.translate('back')),
                              ),
                            ),
                          ...displayGroups.map((group) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: ElevatedButton(
                                onPressed: () => fetchSubcategories(group.itmGroupCode),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                child: Text(group.itmGroupName),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Items Grid
                    Expanded(
                      child: AbsorbPointer(
                        absorbing: !isShiftOpen,
                        child: displayItems.isNotEmpty
                            ? GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            childAspectRatio: 1.2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: displayItems.length,
                          itemBuilder: (context, itemIndex) {
                            final item = displayItems[itemIndex];
                            return GestureDetector(
                              onTap: () => addItemToOrder(item),
                              child: Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            item.itemName,
                                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '\$${item.salesPrice.toStringAsFixed(2)}',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                            : Center(
                          child: Text(
                            localizations.translate('select_category'),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Order Summary Area
            Container(
              width: 350,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(left: BorderSide(color: theme.dividerColor)),
              ),
              child: AbsorbPointer(
                absorbing: !isShiftOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #$cur',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    // Order Items List
                    Expanded(
                      child: orderItems.isEmpty
                          ? Center(
                        child: Text(
                          localizations.translate('no_items_in_order'),
                          style: theme.textTheme.bodyLarge,
                        ),
                      )
                          : ListView.builder(
                        itemCount: orderItems.length,
                        itemBuilder: (context, index) {
                          final item = orderItems[index];
                          return Dismissible(
                            key: Key(item.itemCode),
                            direction: localizations.translate('settings') == 'الإعدادات'
                                ? DismissDirection.startToEnd
                                : DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: localizations.translate('settings') == 'الإعدادات'
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (direction) {
                              _removeFromOrder(item);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    localizations.translate(
                                      'item_removed_from_order',
                                      params: {'item_name': item.itemName},
                                    ),
                                  ),
                                  action: SnackBarAction(
                                    label: localizations.translate('undo'),
                                    onPressed: () {
                                      setState(() {
                                        orderItems.insert(index, item);
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(8.0),
                                title: Text(
                                  item.itemName,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                                          color: theme.primaryColor,
                                          onPressed: () => _decrementQuantity(item),
                                        ),
                                        Text(
                                          '${item.quantity}',
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, size: 20),
                                          color: theme.primaryColor,
                                          onPressed: () => _incrementQuantity(item),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '\$${(item.salesPrice * item.quantity).toStringAsFixed(2)}',
                                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.green),
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
                    // Order Summary
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildSummaryRow(localizations.translate('subtotal'), '\$${subtotal.toStringAsFixed(2)}'),
                        buildSummaryRow(localizations.translate('service_charge'), '\$${serviceCharge.toStringAsFixed(2)}'),
                        buildSummaryRow(localizations.translate('tax'), '\$${tax.toStringAsFixed(2)}'),
                        buildSummaryRow(localizations.translate('total'), '\$${total.toStringAsFixed(2)}', isTotal: true),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Hold and Get Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: orderItems.isNotEmpty ? holdOrder : null,
                          icon: const Icon(Icons.pause),
                          label: Text(localizations.translate('hold')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: heldItems.isNotEmpty ? getHeldOrders : null,
                          icon: const Icon(Icons.get_app),
                          label: Text(localizations.translate('get')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Checkout Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: checkout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          localizations.translate('checkout'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavBar(
          selectedIndex: _selectedIndex,
          userName: widget.name,
          loggedInUserName: widget.loggedInUserName,
          onItemTapped: _onItemTapped,
        ),
      ),
    );
  }

  Widget buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
              color: isTotal ? Colors.green : null,
            ),
          ),
        ],
      ),
    );
  }
}