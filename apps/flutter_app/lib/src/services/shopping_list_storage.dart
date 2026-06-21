import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiago_market_app/src/models/models.dart';

class ShoppingListStorage {
  static const _key = 'tiago_market_shopping_list';

  static Future<List<ShoppingItem>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final json = preferences.getString(_key);
    if (json == null) return const [];
    try {
      final items = (jsonDecode(json) as List<dynamic>)
          .map((item) => ShoppingItem.fromJson(item as Map<String, dynamic>))
          .toList();
      return items;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<ShoppingItem> items) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}
