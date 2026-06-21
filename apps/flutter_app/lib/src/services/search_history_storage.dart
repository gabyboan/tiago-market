import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryStorage {
  static const _key = 'tiago_market_search_history';

  static Future<List<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final jsonString = preferences.getString(_key);
    if (jsonString == null) return const [];

    try {
      final records = jsonDecode(jsonString) as List<dynamic>;
      return records.map((record) => record as String).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<String> queries) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(queries));
  }
}
