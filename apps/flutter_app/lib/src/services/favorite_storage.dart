import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiago_market_app/src/models/models.dart';

class FavoritesStorage {
  static const _key = 'tiago_market_favorites';

  static Future<List<FavoriteItem>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final jsonString = preferences.getString(_key);
    if (jsonString == null) return const [];

    try {
      final records = jsonDecode(jsonString) as List<dynamic>;
      return records
          .map((record) => FavoriteItem.fromJson(record as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<FavoriteItem> items) async {
    final preferences = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(items.map((item) => item.toJson()).toList());
    await preferences.setString(_key, jsonString);
  }
}
