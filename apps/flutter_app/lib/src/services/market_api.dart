import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/models/models.dart';

typedef RpcInvoker = Future<List<dynamic>> Function(
    String name, Map<String, dynamic> params);

class MarketApi {
  MarketApi({RpcInvoker? rpcInvoker}) : _rpcInvoker = rpcInvoker;
  final RpcInvoker? _rpcInvoker;
  bool get _hasRpc => authEnabled || _rpcInvoker != null;

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
        page: page,
        category: category,
        orderBy: orderBy,
      );
    }

    return onlinePrices(query,
        page: page, category: category, orderBy: orderBy);
  }

  Future<List<PriceResult>> onlinePrices(
    String query, {
    int page = 1,
    String? category,
    String orderBy = 'price_asc',
  }) async {
    if (_hasRpc) {
      return _onlinePricesFromSupabase(query,
          page: page, category: category, orderBy: orderBy);
    }

    if (apiBaseUrl.isEmpty) {
      throw Exception('API no configurada');
    }

    final uri = _apiUri('online-prices').replace(
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
      final results = _validPilotResults(
        data.map((item) => PriceResult.fromJson(item as Map<String, dynamic>)),
        requireBranch: false,
      );
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
      return _validPilotResults(
        (jsonDecode(cached) as List<dynamic>)
            .map((item) => PriceResult.fromJson(item as Map<String, dynamic>)),
        requireBranch: false,
      );
    }
  }

  Future<List<PriceResult>> _nearbyPrices(
    String query, {
    required double latitude,
    required double longitude,
    required double radiusKm,
    required int page,
    String? category,
    required String orderBy,
  }) async {
    if (!_hasRpc) {
      throw Exception(
        'Supabase no configurado. Agrega SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY para buscar precios cercanos.',
      );
    }

    final response = await _rpcList(
      'nearby_prices_v4',
      params: {
        'search_query': query.trim(),
        'user_latitude': latitude,
        'user_longitude': longitude,
        'radius_km': radiusKm,
        'limit_count': 100,
        'page_number': page,
        'category_filter': category,
        'sort_order': orderBy,
        'only_available': true,
      },
    );

    usedCache = false;
    return _validPilotResults(
      response
          .map((item) => PriceResult.fromJson(item as Map<String, dynamic>)),
      requireBranch: true,
    );
  }

  Future<List<PriceResult>> _onlinePricesFromSupabase(
    String query, {
    required int page,
    String? category,
    required String orderBy,
  }) async {
    final response = await _rpcList(
      'online_prices_v4',
      params: {
        'search_query': query.trim(),
        'limit_count': 100,
        'page_number': page,
        'category_filter': category,
        'sort_order': orderBy,
        'only_available': true,
      },
    );

    usedCache = false;
    return _validPilotResults(
      response
          .map((item) => PriceResult.fromJson(item as Map<String, dynamic>)),
      requireBranch: false,
    );
  }

  Future<List<ProductCategory>> categories(
      {double? latitude, double? longitude, double radiusKm = 10}) async {
    if (_hasRpc) {
      final rows = await _rpcList('catalog_categories_v3', params: {
        'user_latitude': latitude,
        'user_longitude': longitude,
        'radius_km': radiusKm,
      });
      return rows
          .map((row) => ProductCategory.fromJson(row as Map<String, dynamic>))
          .toList();
    }
    if (apiBaseUrl.isEmpty) return const [];
    final response = await http
        .get(_apiUri('categories'))
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
    final userId =
        authEnabled ? Supabase.instance.client.auth.currentUser?.id : null;
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/api/v1/feedback'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': message.trim(),
            'user_id': userId,
            'context': {'platform': 'flutter', 'app_version': '0.2.2'},
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
    if (!_hasRpc) {
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
    if (_rpcInvoker != null) return _rpcInvoker(functionName, params);
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

  List<PriceResult> _validPilotResults(
    Iterable<PriceResult> results, {
    required bool requireBranch,
  }) {
    final now = DateTime.now().toUtc();
    return results
        .where(
          (result) =>
              result.pilotRejectionReason(
                requireBranch: requireBranch,
                now: now,
              ) ==
              null,
        )
        .toList();
  }

  Uri _apiUri(String endpoint) {
    final base = apiBaseUrl.replaceFirst(RegExp(r'/$'), '');
    final prefix = base.endsWith('/api') ? '$base/v1' : '$base/api/v1';
    return Uri.parse('$prefix/$endpoint');
  }
}
