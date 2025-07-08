import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../classes/Catgeory.dart';
import '../classes/MenuItem.dart';
import '../services/sql_item_helper.dart';

class FetchPage extends StatefulWidget {
  const FetchPage({super.key});

  @override
  _FetchPageState createState() => _FetchPageState();
}

class _FetchPageState extends State<FetchPage> {
  final ItemDatabaseHelper _itmdbHelper = ItemDatabaseHelper();
  String _message = ''; // Message to show the status of data fetch/save
  DateTime? _lastFetchTime; // Variable to store the time of the last fetch

  // Function to fetch and save data from the API
  Future<void> _fetchAndSaveData() async {
    try {
      await saveItemGroupsToDatabase();
      await saveItemsToDatabase();
      setState(() {
        _message = 'Data fetched and saved successfully!';
        _lastFetchTime = DateTime.now(); // Store the current time
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to save data: $e';
      });
    }
  }

  // Save item groups to the database
  Future<void> saveItemGroupsToDatabase() async {
    List<ItemGroup> items = await fetchItemGroupsFromApi();
    for (var item in items) {
      await _itmdbHelper.insertItemGroup(item);
    }
  }

  // Save items to the database
  Future<void> saveItemsToDatabase() async {
    List<Item> items = await fetchItemsFromApi();
    for (var item in items) {
      await _itmdbHelper.insertItem(item);
    }
  }

  // Fetch item groups from the API
  Future<List<ItemGroup>> fetchItemGroupsFromApi() async {
    final response = await http.get(Uri.parse(
        'http://192.168.1.47:8082/api/v1/POSJsonFile/RunSQL/select%20ITM_GROUP_CODE,ITM_GROUP_NAME%20,%20MAIN_GROUP%20from%20INV_ITEM_MAIN_GROUP%20where%20SALEABLE=1/6B4A010D-ED68-42CA-3535-77871FFE3DE'));
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data
          .map((item) => ItemGroup(
              itmGroupCode: item['ITM_GROUP_CODE'],
              itmGroupName: item['ITM_GROUP_NAME'],
              mainGroup: item['MAIN_GROUP']))
          .toList();
    } else {
      throw Exception('Failed to load data');
    }
  }

  // Fetch items from the API
  Future<List<Item>> fetchItemsFromApi() async {
    final response = await http.get(Uri.parse(
        'http://192.168.1.47:8082/api/v1/POSJsonFile/RunSQL/select ITM_GROUP_CODE,%20item_code,item_name,isnull(sales_price,0)%20sales_price%20from%20inv_item_master%20where%20ordered=1 and item_status=1 and item_type=\'n\'%20and%20SALEABLE=1%20and%20sales_price%20<>0/6B4A010D-ED68-42CA-3535-77871FFE3DE'));
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data
          .map((item) => Item(
              itemCode: item['item_code'],
              itemName: item['item_name'],
              salesPrice: item['sales_price'],
              itmGroupCode: item['ITM_GROUP_CODE']))
          .toList();
    } else {
      throw Exception('Failed to load data');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fetch & Save Data'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed: _fetchAndSaveData,
                  child: const Text('Fetch & Save Data'),
                ),
                const SizedBox(height: 10),
                Text(
                  _message,
                  style: const TextStyle(color: Colors.green, fontSize: 14),
                ),
                if (_lastFetchTime != null)
                  Text(
                    'Last Fetch Time: ${_lastFetchTime!.hour}:${_lastFetchTime!.minute}:${_lastFetchTime!.second}',
                    style: const TextStyle(color: Colors.blue, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
