import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zpos/Widget/Order_history.dart';
import 'package:zpos/Widget/display_shift.dart';
import 'package:zpos/Widget/fetch.dart';
import 'package:zpos/Widget/transactions.dart';
import 'package:zpos/services/sql_item_helper.dart';
import 'package:zpos/services/sql_order_helper.dart';
import 'package:zpos/classes/MenuItem.dart';
import 'package:zpos/services/sql_shift_helper.dart';
import 'Widget/settings.dart';
import 'classes/Catgeory.dart';

int cur = 1;

class MyHomePage extends StatefulWidget {
  final String loggedInUserName;
  final String title;
  final String name;

  const MyHomePage(
      {super.key,
      required this.title,
      required this.name,
      required this.loggedInUserName});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late Future<List<Map<String, dynamic>>> menuItems;
  final ShiftDatabaseHelper _dbHelper = ShiftDatabaseHelper();
  String deviceId = ''; // Device ID will be the logged-in username
  final ItemDatabaseHelper _itmdbHelper = ItemDatabaseHelper();
  String? selectedCategory;
  List<ItemGroup> displayGroups = []; // Categories or subcategories
  List<Item> displayItems = []; // Items to be displayed below the row
  List<Item> orderItems = []; // Items added to the order
  List<Item> heldItems = []; //
  bool isShiftOpen = false;

  // Track if the shift is open

  bool isShowingSubcategories =
      false; // Track if subcategories are being displayed

  int _selectedIndex = 0;

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

  void initeState() {
    super.initState();
    // Set the deviceId to the logged-in username
    deviceId = widget.loggedInUserName;
  }

  void openShift() async {
    DateTime now = DateTime.now();
    String formattedTime = DateFormat('HH:mm').format(now);

    // Insert shift details into the database
    await _dbHelper.insertShift({
      'day_code': 'D1', // Replace with appropriate day code
      'day_shift_begin': '09:00',
      'day_shift_end': '17:00',
      'night_shift_begin': '20:00',
      'night_shift_end': '04:00',
      'device_code': deviceId,
      'open_shift': formattedTime,
      'close_shift': '',
      'extra_time': 0,
    });

    setState(() {
      isShiftOpen = true; // Update shift status
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Shift opened at $formattedTime')),
    );
  }

  void closeShift() async {
    DateTime now = DateTime.now();
    String formattedTime = DateFormat('HH:mm').format(now);

    // Retrieve and update the last open shift
    List<Map<String, dynamic>> shifts = await _dbHelper.getShifts();
    if (shifts.isNotEmpty) {
      int lastShiftId = shifts.last['id'];
      await _dbHelper.updateShift(lastShiftId, {
        'close_shift': formattedTime,
        'extra_time': calculateExtraTime(shifts.last, formattedTime),
      });

      setState(() {
        isShiftOpen = false; // Update shift status
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shift closed at $formattedTime')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No shift to close')),
      );
    }
  }

  int calculateExtraTime(Map<String, dynamic> shift, String closeTime) {
    String officialEndTime = shift['day_shift_end'];
    DateTime closeDateTime = DateFormat('HH:mm').parse(closeTime);
    DateTime endDateTime = DateFormat('HH:mm').parse(officialEndTime);

    return closeDateTime.isAfter(endDateTime)
        ? closeDateTime.difference(endDateTime).inMinutes
        : 0;
  }

  Future<void> checkout() async {
    try {
      if (orderItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items to checkout')),
        );
        return;
      }

      // Define the order number (replace with logic to generate a unique order number)
      int orderNumber = cur + 1;

      // Create an order object
      Order order = Order(
        orderNumber: orderNumber,
        items: orderItems,
      );

      // Insert the order into the database
      DBHelper dbHelper = DBHelper();
      await dbHelper.insertOrder(order);

      // Clear the order after successful checkout
      setState(() {
        cur = orderNumber; // Update current order number
        orderItems.clear();
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order checked out successfully')),
      );
    } catch (e) {
      print("Error during checkout: $e"); // Log the error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to checkout: $e')),
      ); // Show error message
    }
  }

  @override
  void initState() {
    super.initState();
    fetchCategories(); // Load categories initially
  }

  // Fetch categories from the database
  Future<void> fetchCategories() async {
    try {
      List<ItemGroup> categories = await getCategories();
      setState(() {
        displayGroups = categories; // Display categories initially
        displayItems = []; // Clear items when navigating back to categories
        isShowingSubcategories = false; // Hide "Back" button
      });
    } catch (e) {
      print("Error fetching categories: $e"); // Log the error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch categories: $e')),
      ); // Show error message
    }
  }

// Fetch subcategories based on the selected category
  Future<void> fetchSubcategories(String categoryCode) async {
    try {
      List<ItemGroup> subcategories = await getSubcategories(categoryCode);
      if (subcategories.isEmpty) {
        // No subcategories, show items directly
        List<Item> items = await getItems(categoryCode);
        setState(() {
          displayItems = items; // Display items when no subcategories
        });
      } else {
        // Show subcategories in the same row
        setState(() {
          displayGroups = subcategories;
          displayItems = []; // Clear items while showing subcategories
          isShowingSubcategories = true; // Show "Back" button
        });
      }
    } catch (e) {
      print("Error fetching subcategories: $e"); // Log the error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch subcategories: $e')),
      ); // Show error message
    }
  }

// Fetch categories from the database
  Future<List<ItemGroup>> getCategories() async {
    try {
      final allItems = await _itmdbHelper.getItemGroups();
      return allItems
          .where((item) => item.itmGroupCode == item.mainGroup)
          .toList();
    } catch (e) {
      print("Error fetching categories from database: $e"); // Log the error
      return []; // Return an empty list if an error occurs
    }
  }

// Fetch subcategories based on the selected category
  Future<List<ItemGroup>> getSubcategories(String categoryCode) async {
    try {
      final allItems = await _itmdbHelper.getItemGroups();
      return allItems
          .where((item) =>
              item.mainGroup == categoryCode &&
              item.itmGroupCode != item.mainGroup)
          .toList();
    } catch (e) {
      print("Error fetching subcategories from database: $e"); // Log the error
      return []; // Return an empty list if an error occurs
    }
  }

// Fetch items based on the selected subcategory
  Future<List<Item>> getItems(String categoryCode) async {
    try {
      final allItems = await _itmdbHelper.getItems();
      return allItems
          .where((item) => item.itmGroupCode == categoryCode)
          .toList();
    } catch (e) {
      print("Error fetching items from database: $e"); // Log the error
      return []; // Return an empty list if an error occurs
    }
  }

  // Function to fetch and save data from the API

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

  // Add item to the order list
  void addItemToOrder(Item item) {
    setState(() {
      final existingItem = orderItems.firstWhere(
        (orderItem) => orderItem.itemCode == item.itemCode,
        orElse: () => Item(
            itemCode: '',
            itemName: '',
            salesPrice: 0,
            itmGroupCode: ' '), // Corrected syntax
      );

      if (existingItem.itemCode != '') {
        existingItem.quantity += 1;
      } else {
        orderItems.add(Item(
          itemCode: item.itemCode,
          // Corrected to access item fields
          itemName: item.itemName,
          salesPrice: item.salesPrice,
          itmGroupCode: item.itmGroupCode,
          // Make sure to provide this value
          quantity: 1,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double subtotal = orderItems.fold<double>(
        0, (total, item) => total + (item.salesPrice * item.quantity));
    double serviceCharge = subtotal * 0.10;
    double tax = subtotal * 0.10;
    double total = subtotal + serviceCharge + tax;
    return SafeArea(
      child: Scaffold(
        body: SizedBox(
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                NavigationRail(
                  leading: SizedBox(
                    height: 40,
                    width: 40,
                    child: Image.network(
                      "https://th.bing.com/th/id/R.5a54ed8571a62fb031d256087797c21b?rik=O81X%2fbvOUZuE2g&riu=http%3a%2f%2fwww.pixelstalk.net%2fwp-content%2fuploads%2f2015%2f12%2fnike-logo-wallpapers-white-black.jpg&ehk=OS8whl5LL8mGvd2rrN9gSVQTttmuXNkqsxEUEoaQG84%3d&risl=&pid=ImgRaw&r=0",
                    ),
                  ),
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                    if (index == 0) {
                      // Assuming "Settings" is at index 1
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const FetchPage()),
                      );
                    } else if (index == 1) {
                      // Assuming "Settings" is at index 1
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const settings()),
                      );
                    } else if (index == 2) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const OrdersTable()),
                      );
                    } else if (index == 3) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ShiftTableScreen()),
                      );
                    }
                  },
                  labelType: NavigationRailLabelType.all,
                  useIndicator: true,
                  backgroundColor: Colors.black45,
                  indicatorColor: Colors.white30,
                  unselectedLabelTextStyle:
                      const TextStyle(color: Colors.white),
                  selectedLabelTextStyle: const TextStyle(color: Colors.white),
                  unselectedIconTheme: const IconThemeData(color: Colors.white),
                  selectedIconTheme: const IconThemeData(color: Colors.white),
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.refresh),
                      label: Text('Fetch'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.account_box),
                      label: Text('Settings'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.table_chart),
                      label: Text('Order'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.access_time_filled),
                      label: Text('Shifts'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 30,
                          width: 130,
                          child: TextField(
                            decoration: InputDecoration(
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: const BorderSide(
                                  color: Colors.white,
                                  width: 1.0,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade300,
                              floatingLabelStyle:
                                  const TextStyle(color: Colors.black),
                              labelText: 'Search',
                              prefixIcon:
                                  const Icon(Icons.search, color: Colors.black),
                            ),
                          ),
                        ),
                        const SizedBox(width: 30),
                        BarcodeWidget(
                          color: Colors.white,
                          barcode: Barcode.code128(),
                          data: '1234567890',
                          width: 200,
                          height: 40,
                          drawText: false,
                        ),
                        const SizedBox(width: 20),
                        Text(
                          'Welcome, ${widget.name} ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(
                          width: 20,
                        ),
                        MaterialButton(
                          onPressed: () {
                            if (isShiftOpen) {
                              closeShift();
                            } else {
                              openShift();
                            }
                          },
                          child: Text(
                            isShiftOpen ? 'Close Shift' : 'Open Shift',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Wrap the content in a SingleChildScrollView to prevent overflow
                    Expanded(
                      child: SingleChildScrollView(
                        child: AbsorbPointer(
                          absorbing: !isShiftOpen,
                          child: Column(
                            children: [
                              SizedBox(
                                height: 650,
                                // You can adjust this height if needed
                                width: 810,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                    const SizedBox(height: 3),
                                    // Row for categories/subcategories and back button
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          if (isShowingSubcategories)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8.0),
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  fetchCategories(); // Return to categories when "Back" is pressed
                                                },
                                                child: const Text('Back'),
                                              ),
                                            ),
                                          ...displayGroups.map((group) {
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 7.0),
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  fetchSubcategories(group
                                                      .itmGroupCode); // Show subcategories or items
                                                },
                                                child: Text(group.itmGroupName),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    // Grid view to display items under the category/subcategory row
                                    if (displayItems.isNotEmpty)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: GridView.builder(
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 4,
                                              childAspectRatio: 20 / 16,
                                              crossAxisSpacing: 2,
                                              mainAxisSpacing: 2,
                                            ),
                                            itemCount: displayItems.length,
                                            itemBuilder: (context, itemIndex) {
                                              final item =
                                                  displayItems[itemIndex];
                                              return GestureDetector(
                                                onTap: () {
                                                  addItemToOrder(
                                                      item); // Add item to the order list
                                                },
                                                child: Card(
                                                  elevation: 2,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            8.0),
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          item.itemName,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 14),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                        const SizedBox(
                                                            height: 10),
                                                        Text(
                                                          '${item.salesPrice}',
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
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
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const SizedBox(height: 100),
                    Expanded(
                      child: SizedBox(
                        width: 60,
                        child: Column(
                          children: [
                            // Hold button
                            MaterialButton(
                              onPressed: () {
                                if (orderItems.isNotEmpty) {
                                  holdOrder();
                                }
                              },
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.pause,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'Hold',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Get Hold button
                            MaterialButton(
                              onPressed: () {
                                if (heldItems.isNotEmpty) {
                                  getHeldOrders();
                                }
                              },
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.get_app,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Get',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                SingleChildScrollView(
                  child: AbsorbPointer(
                    absorbing: !isShiftOpen,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 270,
                          height: 64,
                          child: Stack(
                            children: [
                              Positioned(
                                top: 5,
                                child: Text(
                                  'Order#$cur',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                              const Positioned(
                                top: 40,
                                child: Text(
                                  'QTY',
                                  style: TextStyle(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const Positioned(
                                top: 40,
                                left: 60,
                                child: Text(
                                  "ITEM",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              const Positioned(
                                top: 40,
                                right: 30,
                                child: Text(
                                  'PRICE',
                                  style: TextStyle(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Order items list
                        SizedBox(
                          width: 270,
                          height: 550,
                          child: ListView.builder(
                            itemCount: orderItems.length,
                            itemBuilder: (context, index) {
                              final item = orderItems[index];
                              return Dismissible(
                                key: Key(item.itemCode),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: const Icon(Icons.delete,
                                      color: Colors.white),
                                ),
                                onDismissed: (direction) {
                                  _removeFromOrder(item);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${item.itemName} removed from order'),
                                      action: SnackBarAction(
                                        label: 'Undo',
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
                                  color: Colors.grey.shade800,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(8.0),
                                    title: Text(
                                      item.itemName,
                                      style: const TextStyle(
                                          fontSize: 13, color: Colors.white),
                                    ),
                                    subtitle: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                  color: Colors.white),
                                              onPressed: () =>
                                                  _decrementQuantity(item),
                                            ),
                                            Text(
                                              '${item.quantity}',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.white),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.add_circle_outline,
                                                  color: Colors.white),
                                              onPressed: () =>
                                                  _incrementQuantity(item),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          (item.salesPrice * item.quantity)
                                              .toStringAsFixed(2),
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: 250,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              buildSummaryRow(
                                  'Subtotal:', subtotal.toStringAsFixed(2)),
                              buildSummaryRow('Service Charge:',
                                  serviceCharge.toStringAsFixed(2)),
                              buildSummaryRow('Tax:', tax.toStringAsFixed(2)),
                              buildSummaryRow(
                                  'Total:', total.toStringAsFixed(2),
                                  isTotal: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const SizedBox(width: 100),
                            SizedBox(
                              width: 200,
                              child: Row(
                                children: [
                                  // Checkout button
                                  Center(
                                    child: MaterialButton(
                                      onPressed: () {
                                        try {
                                          checkout();
                                        } catch (e) {
                                          print('Error during navigation: $e');
                                        }
                                        Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (context) =>
                                                    const TransactionPage()));
                                      },
                                      child: const Center(
                                        child: Text(
                                          'Check out',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
