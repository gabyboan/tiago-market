import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/models/models.dart';

class MarketApi {
  bool usedCache = false;

  Future<List<PriceResult>> compare(
    String query, {
    double? latitude,
    double? longitude,
    double radiusKm = 10,
    String orderBy = 'price',
    int page = 1,
    String? category,
  }) async {
    if (latitude != null && longitude != null) {
      return _nearbyPrices(
        query,
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );
    }

    return onlinePrices(query, page: page, category: category);
  }

  Future<List<PriceResult>> onlinePrices(
    String query, {
    int page = 1,
    String? category,
  }) async {
    if (authEnabled) {
      return _onlinePricesFromSupabase(query, page: page, category: category);
    }

    if (apiBaseUrl.isEmpty) {
      throw Exception('API no configurada');
    }

    final uri = Uri.parse('$apiBaseUrl/api/v1/online-prices').replace(
      queryParameters: {
        'limit': '100',
        'page': page.toString(),
        if (query.trim().isNotEmpty) 'query': query,
        if (category != null) 'category': category,
      },
    );
    final cacheKey = 'price-cache:${uri.toString()}';
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('API respondió ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      final results = data
          .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
          .toList();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        cacheKey,
        jsonEncode(results.map((result) => result.toJson()).toList()),
      );
      usedCache = false;
      return results;
    } catch (_) {
      final preferences = await SharedPreferences.getInstance();
      final cached = preferences.getString(cacheKey);
      if (cached == null) rethrow;
      usedCache = true;
      return (jsonDecode(cached) as List<dynamic>)
          .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
          .toList();
    }
  }

  Future<List<PriceResult>> _nearbyPrices(
    String query, {
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    if (!authEnabled) {
      throw Exception(
        'Supabase no configurado. Agrega SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY para buscar precios cercanos.',
      );
    }

    final response = await _rpcList(
      'nearby_prices',
      params: {
        'search_query': query.trim(),
        'user_latitude': latitude,
        'user_longitude': longitude,
        'radius_km': radiusKm,
        'only_available': true,
      },
    );

    usedCache = false;
    return response
        .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
        .where((result) => result.branchName != null)
        .toList();
  }

  Future<List<PriceResult>> _onlinePricesFromSupabase(
    String query, {
    required int page,
    String? category,
  }) async {
    final response = await _rpcList(
      'online_prices',
      params: {
        'search_query': query.trim(),
        'limit_count': 100,
        'page_number': page,
        'category_filter': category,
        'only_available': true,
      },
    );

    usedCache = false;
    return response
        .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ProductCategory>> categories() async {
    if (apiBaseUrl.isEmpty) return const [];
    final response = await http
        .get(Uri.parse('$apiBaseUrl/api/v1/categories'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('API respondió ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['data'] as List<dynamic>? ?? [])
        .map((item) => ProductCategory.fromJson(item as Map<String, dynamic>))
        .where((category) => category.count > 0)
        .toList();
  }

  Future<void> sendFeedback(String message) async {
    if (apiBaseUrl.isEmpty) throw Exception('API no configurada');
    final userId = authEnabled
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/api/v1/feedback'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': message.trim(),
            'user_id': userId,
            'context': {'platform': 'flutter', 'app_version': '0.2.1'},
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 201) {
      throw Exception('API respondió ${response.statusCode}');
    }
  }

  Future<int> nearbyBranchCount(
    double latitude,
    double longitude,
    double radiusKm,
  ) async {
    if (!authEnabled) {
      throw Exception(
        'Supabase no configurado. Agrega SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY para buscar sucursales cercanas.',
      );
    }

    final response = await _rpcList(
      'nearby_branches',
      params: {
        'user_latitude': latitude,
        'user_longitude': longitude,
        'radius_km': radiusKm,
      },
    );
    return response.length;
  }

  Future<List<dynamic>> _rpcList(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    try {
      final response = await Supabase.instance.client
          .rpc(functionName, params: params)
          .timeout(const Duration(seconds: 10));
      return response as List<dynamic>? ?? const [];
    } catch (error, stackTrace) {
      debugPrint('$functionName RPC failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
