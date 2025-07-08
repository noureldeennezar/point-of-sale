import 'package:flutter/material.dart';
import '../services/sql_shift_helper.dart';

class ShiftTableScreen extends StatefulWidget {
  const ShiftTableScreen({super.key});

  @override
  _ShiftTableScreenState createState() => _ShiftTableScreenState();
}

class _ShiftTableScreenState extends State<ShiftTableScreen> {
  late Future<List<Map<String, dynamic>>> shiftsData;

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  // Method to load shifts data
  void _loadShifts() {
    setState(() {
      shiftsData = ShiftDatabaseHelper().getShifts();
    });
  }

  // Helper method to format column names
  String formatColumnName(String columnName) {
    return columnName
        .split('_') // Split by underscores
        .map((word) =>
            word[0].toUpperCase() + word.substring(1)) // Capitalize each word
        .join(' '); // Join words with spaces
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift Table'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              bool? confirmClear = await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Database'),
                  content:
                      const Text('Are you sure you want to clear all shifts?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (confirmClear == true) {
                ShiftDatabaseHelper().clearShifts();
                _loadShifts();
              }
            },
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: shiftsData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
                child: Text('Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white)));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
                child: Text('No shift data available.',
                    style: TextStyle(color: Colors.white)));
          } else {
            final shiftData = snapshot.data!;
            final columnsToShow =
                shiftData[0].keys.where((key) => key != 'device_code').toList();

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: columnsToShow
                    .map((key) => DataColumn(
                          label: Text(formatColumnName(key),
                              style: const TextStyle(color: Colors.white)),
                        ))
                    .toList(),
                rows: shiftData.map((row) {
                  return DataRow(
                    cells: columnsToShow
                        .map((key) => DataCell(
                              Text(row[key].toString(),
                                  style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                  );
                }).toList(),
              ),
            );
          }
        },
      ),
    );
  }
}
