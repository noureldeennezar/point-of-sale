import 'package:flutter/material.dart';
import 'package:flutter_barcode_listener/flutter_barcode_listener.dart';
import 'package:provider/provider.dart';

import '../Core/app_localizations.dart';
import '../Core/theme_provider.dart';
import '../cloud_services/AuthService.dart';
import '../local_services/category_db_helper.dart';
import '../local_services/item_db_helper.dart';
import '../main.dart';
import '../models/Item.dart';
import '../models/ProductCategory.dart';
import 'auth/login.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Text(
            localizations.translate('settings'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            labelStyle: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: theme.textTheme.bodyLarge,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.primary,
            tabs: [
              Tab(text: localizations.translate('items')),
              Tab(text: localizations.translate('appearance')),
              Tab(text: localizations.translate('accounts')),
            ],
          ),
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          centerTitle: true,
        ),
        body: TabBarView(
          controller: _tabController,
          children: const [ItemManagementTab(), SettingsTab(), AccountsTab()],
        ),
      ),
    );
  }
}

class ItemManagementTab extends StatefulWidget {
  const ItemManagementTab({super.key});

  @override
  _ItemManagementTabState createState() => _ItemManagementTabState();
}

class _ItemManagementTabState extends State<ItemManagementTab> {
  final CategoryDbHelper _categoryDb = CategoryDbHelper();
  final ItemDbHelper _itemDb = ItemDbHelper();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _initialStockController =
      TextEditingController(); // ← NEW: for stock quantity
  final TextEditingController _categoryNameController = TextEditingController();

  String? _selectedCategory;
  List<ProductCategory> _categories = [];

  bool _isAdding = false;
  bool _isAddingCategory = false;
  bool _isScanning = false;

  String? _editingItemCode;
  String? _scannedBarcode;
  String _rawBarcodeInput = '';

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<String> _getStoreId() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userData = await authService.currentUserWithRole.first;
    return userData?['storeId'] as String? ?? 'local_store_001';
  }

  Future<void> _fetchCategories() async {
    final storeId = await _getStoreId();
    try {
      final categories = await _categoryDb.getCategories(storeId);
      setState(() {
        _categories = categories;
        if (_categories.isNotEmpty &&
            (_selectedCategory == null ||
                !_categories.any((c) => c.categoryCode == _selectedCategory))) {
          _selectedCategory = _categories.first.categoryCode;
        } else if (_categories.isEmpty) {
          _selectedCategory = null;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load categories: $e')));
    }
  }

  Future<void> _saveCategory() async {
    final storeId = await _getStoreId();
    if (_categoryNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('fill_category_name'),
          ),
        ),
      );
      return;
    }

    final category = ProductCategory(
      categoryCode: DateTime.now().millisecondsSinceEpoch.toString(),
      categoryName: _categoryNameController.text.trim(),
      mainGroup: 'Default',
    );

    try {
      await _categoryDb.insertCategory(category, storeId);
      await _fetchCategories();
      setState(() {
        _isAddingCategory = false;
        _selectedCategory = category.categoryCode;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('category_added'),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save category: $e')));
    }
  }

  Future<void> _saveItem({
    bool isMerge = false,
    String? existingItemCode,
  }) async {
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

    final double? price = double.tryParse(_priceController.text);
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

    // NEW: Validate initial stock quantity
    final stockText = _initialStockController.text.trim();
    int stockQuantity = 0;
    if (stockText.isNotEmpty) {
      final parsed = int.tryParse(stockText);
      if (parsed == null || parsed < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Initial stock must be a non-negative number'),
          ),
        );
        return;
      }
      stockQuantity = parsed;
    }

    final String itmGroupCode =
        _selectedCategory ??
        (_categories.isNotEmpty ? _categories.first.categoryCode : 'default');

    final item = Item(
      itemCode: isMerge
          ? existingItemCode!
          : (_editingItemCode ??
                DateTime.now().millisecondsSinceEpoch.toString()),
      itemName: _nameController.text.trim(),
      salesPrice: price,
      itmGroupCode: itmGroupCode,
      barcode: _barcodeController.text.isEmpty
          ? _scannedBarcode
          : _barcodeController.text.trim(),
      isActive: true,
      stockQuantity: stockQuantity,
      // ← NEW: Save the entered initial stock
      minStockLevel: 0,
      quantity: 0, // runtime only
    );

    try {
      await _itemDb.insertItem(item, storeId);
      setState(() {
        _isAdding = false;
        _isScanning = false;
        _scannedBarcode = null;
        _rawBarcodeInput = '';
        _initialStockController.clear(); // Clear for next add
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate(
              isMerge
                  ? 'item_merged'
                  : (_editingItemCode == null ? 'item_added' : 'item_updated'),
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save item: $e')));
    }
  }

  void _showAddEditDialog({Item? item, String? barcode}) {
    if (item != null) {
      _nameController.text = item.itemName;
      _priceController.text = item.salesPrice.toString();
      _barcodeController.text = item.barcode ?? '';
      _initialStockController.text = item.stockQuantity
          .toString(); // ← NEW: Load existing stock
      _editingItemCode = item.itemCode;
      _scannedBarcode = null;
      _selectedCategory =
          _categories.isNotEmpty &&
              _categories.any((c) => c.categoryCode == item.itmGroupCode)
          ? item.itmGroupCode
          : _categories.isNotEmpty
          ? _categories.first.categoryCode
          : null;
    } else {
      _nameController.clear();
      _priceController.clear();
      _barcodeController.text = barcode ?? '';
      _initialStockController.clear(); // ← NEW: Reset stock field
      _scannedBarcode = barcode;
      _editingItemCode = null;
      _selectedCategory = _categories.isNotEmpty
          ? _categories.first.categoryCode
          : null;
    }

    setState(() {
      _isAdding = true;
      _rawBarcodeInput = barcode ?? '';
    });
  }

  void _showAddCategoryDialog() {
    _categoryNameController.clear();
    setState(() {
      _isAddingCategory = true;
    });
  }

  Future<void> _handleScannedBarcode(String barcode) async {
    final storeId = await _getStoreId();
    if (storeId == null || storeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('no_store_id')),
        ),
      );
      setState(() {
        _isScanning = false;
        _rawBarcodeInput = '';
      });
      return;
    }

    setState(() {
      _rawBarcodeInput = barcode;
    });

    barcode = barcode.trim();
    if (barcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('no_barcode_detected'),
          ),
        ),
      );
      setState(() {
        _isScanning = false;
        _rawBarcodeInput = '';
      });
      return;
    }

    if (!RegExp(r'^\d{12,13}$').hasMatch(barcode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('invalid_barcode_format'),
          ),
        ),
      );
      setState(() {
        _isScanning = false;
        _rawBarcodeInput = '';
      });
      return;
    }

    try {
      final items = await _itemDb.getItems(storeId);
      final existingItem = items.firstWhere(
        (i) => i.barcode == barcode,
        orElse: () => Item(
          itemCode: '',
          itemName: '',
          salesPrice: 0,
          itmGroupCode: 'default',
          quantity: 0,
          barcode: '',
        ),
      );

      if (existingItem.itemCode.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate(
                'barcode_already_exists',
                params: {'item_name': existingItem.itemName},
              ),
            ),
          ),
        );
        setState(() {
          _isScanning = false;
          _rawBarcodeInput = '';
        });
        return;
      }

      setState(() {
        _scannedBarcode = barcode;
        _barcodeController.text = barcode;
        _isScanning = false;
      });

      _showAddEditDialog(barcode: barcode);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to process barcode: $e')));
      setState(() {
        _isScanning = false;
        _rawBarcodeInput = '';
      });
    }
  }

  Future<void> _checkSimilarNames(
    String name, {
    bool saveDirectly = false,
  }) async {
    if (name.isEmpty) return;

    final storeId = await _getStoreId();
    if (storeId == null || storeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('no_store_id')),
        ),
      );
      return;
    }

    try {
      final items = await _itemDb.getItems(storeId);
      final similarItems = items
          .where(
            (item) => item.itemName.toLowerCase().contains(name.toLowerCase()),
          )
          .toList();

      if (similarItems.isNotEmpty && saveDirectly) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              AppLocalizations.of(context).translate('similar_item_found'),
            ),
            content: Text(
              AppLocalizations.of(context).translate(
                'merge_or_separate',
                params: {'item_name': similarItems.first.itemName},
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _saveItem();
                },
                child: Text(
                  AppLocalizations.of(context).translate('add_as_new'),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _saveItem(
                    isMerge: true,
                    existingItemCode: similarItems.first.itemCode,
                  );
                },
                child: Text(AppLocalizations.of(context).translate('merge')),
              ),
            ],
          ),
        );
      } else if (saveDirectly) {
        _saveItem();
      }
    } catch (e) {
      // Silently fail on check – not critical
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.translate('item_management'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        localizations.translate('manage_items_categories'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showAddCategoryDialog,
                              icon: const Icon(Icons.category),
                              label: Text(
                                localizations.translate('add_category'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showAddEditDialog(),
                              icon: const Icon(Icons.add),
                              label: Text(localizations.translate('add_item')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
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
        ),

        // Add/Edit Item Dialog – NOW WITH QUANTITY FIELD
        if (_isAdding)
          Container(
            color: Colors.black54,
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _editingItemCode == null
                            ? localizations.translate('add_item')
                            : localizations.translate('edit_item'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 24),

                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: localizations.translate('item_name'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            _checkSimilarNames(value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: localizations.translate('price'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _barcodeController,
                        decoration: InputDecoration(
                          labelText: localizations.translate('barcode'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // NEW: Initial Stock Quantity field
                      TextField(
                        controller: _initialStockController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Initial Stock Quantity',
                          hintText: 'Enter starting stock (0 if none)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: InputDecoration(
                          labelText: localizations.translate('category'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                        ),
                        items: _categories.isEmpty
                            ? [
                                DropdownMenuItem(
                                  value: 'default',
                                  enabled: false,
                                  child: Text(
                                    localizations.translate('no_categories'),
                                  ),
                                ),
                              ]
                            : _categories
                                  .map(
                                    (category) => DropdownMenuItem(
                                      value: category.categoryCode,
                                      child: Text(category.categoryName),
                                    ),
                                  )
                                  .toList(),
                        onChanged: _categories.isEmpty
                            ? null
                            : (value) =>
                                  setState(() => _selectedCategory = value),
                        hint: Text(localizations.translate('select_category')),
                      ),
                      const SizedBox(height: 32),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isAdding = false;
                                _isScanning = false;
                                _scannedBarcode = null;
                                _rawBarcodeInput = '';
                              });
                              _nameController.clear();
                              _priceController.clear();
                              _barcodeController.clear();
                              _initialStockController.clear();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            child: Text(localizations.translate('cancel')),
                          ),
                          ElevatedButton(
                            onPressed: () => _checkSimilarNames(
                              _nameController.text,
                              saveDirectly: true,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            child: Text(localizations.translate('save')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Add Category Dialog (unchanged)
        if (_isAddingCategory)
          Container(
            color: Colors.black54,
            child: Center(
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      localizations.translate('add_category'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _categoryNameController,
                      decoration: InputDecoration(
                        labelText: localizations.translate('category_name'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _isAddingCategory = false);
                            _categoryNameController.clear();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          child: Text(localizations.translate('cancel')),
                        ),
                        ElevatedButton(
                          onPressed: _saveCategory,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          child: Text(localizations.translate('save')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Scanning overlay (unchanged)
        if (_isScanning && !_isAdding)
          BarcodeKeyboardListener(
            onBarcodeScanned: _handleScannedBarcode,
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizations.translate('scan_new_item'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        localizations.translate('scan_barcode_prompt'),
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Raw input: $_rawBarcodeInput',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isScanning = false;
                            _rawBarcodeInput = '';
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(localizations.translate('cancel')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    _initialStockController.dispose(); // NEW controller cleanup
    _categoryNameController.dispose();
    super.dispose();
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final localeModel = Provider.of<LocaleModel>(context, listen: false);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.translate('appearance'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  localizations.translate('language'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<Locale>(
                  value: localeModel.locale,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: Locale('en', ''),
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: Locale('ar', ''),
                      child: Text('العربية'),
                    ),
                  ],
                  onChanged: (Locale? newLocale) {
                    if (newLocale != null) {
                      localeModel.setLocale(newLocale);
                    }
                  },
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  dropdownColor: theme.colorScheme.surfaceContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  localizations.translate('theme'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Light'),
                          icon: Icon(Icons.wb_sunny),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Dark'),
                          icon: Icon(Icons.nights_stay),
                        ),
                      ],
                      selected: {themeProvider.themeMode == ThemeMode.dark},
                      onSelectionChanged: (Set<bool> newSelection) {
                        themeProvider.toggleTheme(newSelection.first);
                      },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith<Color>(
                          (states) => states.contains(WidgetState.selected)
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainer,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith<Color>(
                          (states) => states.contains(WidgetState.selected)
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AccountsTab extends StatelessWidget {
  const AccountsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.translate('account'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          localizations.translate('logout_confirmation'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        content: Text(
                          localizations.translate('logout_question'),
                          style: theme.textTheme.bodyLarge,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              localizations.translate('cancel'),
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final authService = Provider.of<AuthService>(
                                context,
                                listen: false,
                              );
                              await authService.signOut();
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                                (route) => false,
                              );
                            },
                            child: Text(
                              localizations.translate('logout'),
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                    elevation: 4,
                  ),
                  child: Text(
                    localizations.translate('logout'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
