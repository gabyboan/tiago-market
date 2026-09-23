import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/services/market_api.dart';
import 'package:tiago_market_app/src/services/shopping_list_storage.dart';
import 'package:tiago_market_app/src/services/favorite_storage.dart';
import 'package:tiago_market_app/src/services/search_history_storage.dart';

class SearchController extends ChangeNotifier {
  SearchController({MarketApi? api, bool? loadOnStart})
      : _api = api ?? MarketApi() {
    _attachScrollListener();
    _loadShoppingList();
    _loadFavorites();
    _loadSearchHistory();
    _loadCategories();
    if (loadOnStart ?? (apiBaseUrl.isNotEmpty || authEnabled)) {
      Future.microtask(search);
    }
  }

  final MarketApi _api;

  final TextEditingController queryController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<PriceResult> results = [];
  bool loading = false;
  bool loadingMore = false;
  bool usingDemo = false;
  bool usingCache = false;
  bool locating = false;
  double? latitude;
  double? longitude;
  double radiusKm = 10;
  String orderBy = 'price';
  String sortMode = 'price_asc';
  int page = 1;
  bool hasMore = true;
  String? error;
  String? localEmptyMessage;
  int nearbyBranches = 0;
  List<ShoppingItem> shoppingItems = const [];
  List<FavoriteItem> favorites = const [];
  List<String> searchHistory = const [];
  List<ProductCategory> categories = const [];
  String? selectedCategory;
  bool freshOnly = false;
  String? _lastSubmittedQuery;
  bool _categorySelectedAfterSearch = false;
  int _requestId = 0;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool get hasLocation => latitude != null && longitude != null;
  String get queryText => queryController.text.trim();

  String get emptyMessage {
    final category = selectedCategory;
    if (category != null && _categorySelectedAfterSearch) {
      final query = queryText;
      if (query.isNotEmpty) {
        return 'No encontramos resultados para “$query” en $category. Probá con Todo.';
      }
    }
    if (localEmptyMessage != null) {
      return localEmptyMessage!;
    }
    return hasLocation
        ? 'No hay precios vigentes de sucursales verificadas en esta zona. Podés consultar el catálogo online por separado.'
        : 'No hay precios online vigentes para esta búsqueda. Probá otro producto o categoría.';
  }

  List<PriceResult> get filteredResults {
    return results.where((result) {
      return !freshOnly || result.freshness == 'fresh';
    }).toList();
  }

  List<ProductComparisonGroup> get groupedResults => groupPriceResults(
        filteredResults,
        sortMode: sortMode,
      );

  void _attachScrollListener() {
    scrollController.addListener(() {
      if (!scrollController.hasClients ||
          loading ||
          loadingMore ||
          !hasMore ||
          usingDemo) {
        return;
      }
      if (scrollController.position.extentAfter < 700) {
        search(append: true);
      }
    });
  }

  Future<void> _loadCategories() async {
    try {
      final localLatitude = latitude;
      final localLongitude = longitude;
      final localRadius = radiusKm;
      final loaded = await _api.categories(
          latitude: localLatitude,
          longitude: localLongitude,
          radiusKm: localRadius);
      if (localLatitude != latitude ||
          localLongitude != longitude ||
          localRadius != radiusKm) {
        return;
      }
      categories = loaded;
      notifyListeners();
    } catch (_) {
      // El catálogo no es crítico para la experiencia principal.
    }
  }

  Future<void> _loadShoppingList() async {
    final items = await ShoppingListStorage.load();
    shoppingItems = items;
    notifyListeners();
  }

  Future<void> _loadFavorites() async {
    final items = await FavoritesStorage.load();
    favorites = items;
    notifyListeners();
  }

  Future<void> _loadSearchHistory() async {
    final history = await SearchHistoryStorage.load();
    searchHistory = history;
    notifyListeners();
  }

  Future<void> _saveSearchHistory() async {
    await SearchHistoryStorage.save(searchHistory);
  }

  Future<void> addSearchHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final existingIndex = searchHistory.indexWhere(
      (item) => item.toLowerCase() == trimmed.toLowerCase(),
    );
    final entries = [...searchHistory];
    if (existingIndex >= 0) {
      entries.removeAt(existingIndex);
    }
    entries.insert(0, trimmed);
    if (entries.length > 10) entries.removeRange(10, entries.length);

    searchHistory = entries;
    await _saveSearchHistory();
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    searchHistory = const [];
    await _saveSearchHistory();
    notifyListeners();
  }

  bool isFavorite(ProductComparisonGroup group) {
    return favorites.any((item) => item.comparisonKey == group.comparisonKey);
  }

  Future<void> toggleFavorite(ProductComparisonGroup group) async {
    final exists = favorites.indexWhere(
      (item) => item.comparisonKey == group.comparisonKey,
    );
    final items = [...favorites];
    if (exists >= 0) {
      items.removeAt(exists);
    } else {
      items.add(FavoriteItem.fromGroup(group));
    }
    await FavoritesStorage.save(items);
    favorites = items;
    notifyListeners();
  }

  Future<void> removeFavorite(FavoriteItem item) async {
    final items = favorites
        .where(
          (value) => value.comparisonKey != item.comparisonKey,
        )
        .toList();
    await FavoritesStorage.save(items);
    favorites = items;
    notifyListeners();
  }

  Future<void> addFavoriteToShoppingList(FavoriteItem favoriteItem) async {
    final existingIndex = shoppingItems.indexWhere(
      (item) => item.comparisonKey == favoriteItem.comparisonKey,
    );
    final items = [...shoppingItems];
    if (existingIndex >= 0) {
      items[existingIndex] = items[existingIndex].copyWith(
        quantity: items[existingIndex].quantity + 1,
      );
    } else {
      items.add(
        ShoppingItem(
          comparisonKey: favoriteItem.comparisonKey,
          productName: favoriteItem.productName,
          quantity: 1,
          prices: [favoriteItem.toBestPriceResult()],
        ),
      );
    }
    await ShoppingListStorage.save(items);
    shoppingItems = items;
    notifyListeners();
  }

  Future<void> search({
    String? quickQuery,
    bool append = false,
  }) async {
    if (append && (loading || loadingMore || !hasMore)) return;
    final requestId = ++_requestId;
    if (quickQuery != null) {
      queryController.text = quickQuery;
    }
    if (!append) {
      localEmptyMessage = null;
    }

    final query = queryController.text.trim();
    if (!append) {
      _lastSubmittedQuery = query;
    }
    final nextPage = append ? page + 1 : 1;
    if (!append) results = [];
    loadingMore = append;
    loading = !append;
    error = null;
    notifyListeners();

    if (!append && query.isNotEmpty) {
      unawaited(addSearchHistory(query));
    }

    try {
      final results = await _api.compare(
        query,
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
        orderBy: sortMode,
        page: nextPage,
        category: selectedCategory,
      );
      if (_disposed || requestId != _requestId) return;
      final unique = <String, PriceResult>{
        if (append)
          for (final row in this.results) row.identityKey: row,
        for (final row in results) row.identityKey: row,
      };
      this.results = unique.values.toList();
      page = nextPage;
      hasMore = results.length == 100;
      usingDemo = false;
      usingCache = _api.usedCache;
    } catch (exception) {
      if (_disposed || requestId != _requestId) return;
      if (!append) {
        results = [];
      }
      usingDemo = false;
      usingCache = false;
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      if (!_disposed && requestId == _requestId) {
        loading = false;
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> submitSearch({String? quickQuery}) async {
    if (quickQuery != null) {
      queryController.text = quickQuery;
      _resetCategoryFilter();
    } else {
      final query = queryText;
      if (!_sameQuery(query, _lastSubmittedQuery)) {
        _resetCategoryFilter();
      }
    }
    if (hasLocation) {
      await searchNearby();
    } else {
      await search();
    }
  }

  Future<void> useLocation() async {
    locating = true;
    error = null;
    notifyListeners();

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Activa la ubicación del dispositivo para continuar.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('No se concedió permiso de ubicación.');
      }

      final position = await Geolocator.getCurrentPosition();
      latitude = position.latitude;
      longitude = position.longitude;
      selectedCategory = null;
      categories = [];
      orderBy = 'distance';
      sortMode = 'distance';
      await searchNearby();
    } catch (error) {
      this.error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      locating = false;
      notifyListeners();
    }
  }

  Future<void> searchNearby() async {
    localEmptyMessage = null;
    unawaited(_loadCategories());
    await search();
  }

  void clearLocation() {
    latitude = null;
    longitude = null;
    orderBy = 'price';
    if (sortMode == 'distance') sortMode = 'price_asc';
    nearbyBranches = 0;
    localEmptyMessage = null;
    selectedCategory = null;
    categories = [];
    unawaited(_loadCategories());
    search();
    notifyListeners();
  }

  void setCategory(String? category) {
    selectedCategory = category;
    _categorySelectedAfterSearch = category != null;
    if (hasLocation) {
      unawaited(searchNearby());
    } else {
      unawaited(search());
    }
  }

  bool _sameQuery(String query, String? previousQuery) {
    return query.trim().toLowerCase() == previousQuery?.trim().toLowerCase();
  }

  void _resetCategoryFilter() {
    selectedCategory = null;
    _categorySelectedAfterSearch = false;
  }

  void setSortMode(String value) {
    sortMode = value;
    orderBy = value == 'distance' ? 'distance' : 'price';
    notifyListeners();
    unawaited(search());
  }

  void setFreshOnly(bool value) {
    freshOnly = value;
    notifyListeners();
  }

  void setRadiusKm(double value) {
    radiusKm = value;
    notifyListeners();
  }

  Future<void> addToShoppingList(ProductComparisonGroup group) async {
    final existingIndex = shoppingItems.indexWhere(
      (item) => item.comparisonKey == group.comparisonKey,
    );
    final items = [...shoppingItems];
    if (existingIndex >= 0) {
      items[existingIndex] = items[existingIndex].copyWith(
        quantity: items[existingIndex].quantity + 1,
        prices: group.prices,
      );
    } else {
      items.add(
        ShoppingItem(
          comparisonKey: group.comparisonKey,
          productName: group.productName,
          quantity: 1,
          prices: group.prices,
        ),
      );
    }

    await ShoppingListStorage.save(items);
    shoppingItems = items;
    notifyListeners();
  }

  Future<void> updateShoppingItem(ShoppingItem item, int quantity) async {
    final items = [...shoppingItems];
    final index =
        items.indexWhere((value) => value.comparisonKey == item.comparisonKey);
    if (index < 0) return;
    if (quantity <= 0) {
      items.removeAt(index);
    } else {
      items[index] = item.copyWith(quantity: quantity);
    }
    await ShoppingListStorage.save(items);
    shoppingItems = items;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestId++;
    queryController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
