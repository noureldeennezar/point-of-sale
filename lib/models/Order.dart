import 'dart:convert';

import 'Item.dart';

class Order {
  final int? orderNumber;
  final List<Item> items;
  final String date;

  Order({this.orderNumber, required this.items, required this.date});

  Map<String, dynamic> toMap() {
    return {
      'orderNumber': orderNumber,
      'date': date,
      'items': items.map((item) => item.toMap()).toList(),
    };
  }

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      orderNumber: map['orderNumber'],
      items: List<Item>.from(map['items'].map((item) => Item.fromMap(item))),
      date: map['date'],
    );
  }

  String toJson() => jsonEncode(toMap());

  factory Order.fromJson(String source) => Order.fromMap(jsonDecode(source));
}
