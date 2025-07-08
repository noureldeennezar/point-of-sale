// TODO Implement this library.
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../classes/Catgeory.dart';
import '../classes/MenuItem.dart';

class ItemDatabaseHelper {
  static final ItemDatabaseHelper _instance = ItemDatabaseHelper._internal();
  static Database? _database;

  factory ItemDatabaseHelper() {
    return _instance;
  }

  ItemDatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'pos.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE item_group (
        itm_group_code TEXT PRIMARY KEY,
        itm_group_name TEXT,
        main_group TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE item (
        item_code TEXT PRIMARY KEY,
        item_name TEXT,
        sales_price REAL,
        itm_group_code TEXT
      )
    ''');
  }

  Future<void> insertItemGroup(ItemGroup itemGroup) async {
    final db = await database;
    await db.insert('item_group', itemGroup.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertItem(Item item) async {
    final db = await database;
    await db.insert('item', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ItemGroup>> getItemGroups() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('item_group');
    return List.generate(maps.length, (i) {
      return ItemGroup(
        itmGroupCode: maps[i]['itm_group_code'],
        itmGroupName: maps[i]['itm_group_name'],
        mainGroup: maps[i]['main_group'],
      );
    });
  }

  Future<List<Item>> getItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('item');
    return List.generate(maps.length, (i) {
      return Item(
        itemCode: maps[i]['item_code'],
        itemName: maps[i]['item_name'],
        salesPrice: maps[i]['sales_price'],
        itmGroupCode: maps[i]['itm_group_code'],
      );
    });
  }
}

Widget buildSummaryRow(String label, String amount, {bool isTotal = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? Colors.white : Colors.grey,
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? Colors.white : Colors.grey,
          ),
        ),
      ],
    ),
  );
}
