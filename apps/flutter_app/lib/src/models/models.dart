class ProductCategory {
  const ProductCategory({required this.name, required this.count});

  factory ProductCategory.fromJson(Map<String, dynamic> json) =>
      ProductCategory(
        name: json['name'] as String? ?? 'Otros',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  final String name;
  final int count;
}

class PriceResult {
  const PriceResult({
    required this.storeName,
    required this.productName,
    this.normalizedName = '',
    this.branchName,
    required this.price,
    required this.capturedAt,
    this.source = 'direct',
    this.freshness = 'fresh',
    this.daysOld = 0,
    this.distanceKm,
    this.storeProductUrl,
    this.imageUrl,
    this.presentation,
    this.category,
  });

  factory PriceResult.fromJson(Map<String, dynamic> json) {
    return PriceResult(
      storeName: json['store_name'] as String? ?? 'Tienda',
      productName: json['product_name'] as String? ?? 'Producto',
      normalizedName: json['normalized_name'] as String? ??
          json['product_name'] as String? ??
          'producto',
      branchName: json['branch_name'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      source: json['source'] as String? ?? 'fuente no informada',
      capturedAt: json['captured_at'] as String? ?? '',
      freshness: json['freshness'] as String? ?? 'old',
      daysOld: (json['days_old'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      storeProductUrl: json['store_product_url'] as String?,
      imageUrl: json['image_url'] as String?,
      presentation: json['presentation'] as String?,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'store_name': storeName,
        'product_name': productName,
        'normalized_name': normalizedName,
        'branch_name': branchName,
        'price': price,
        'source': source,
        'captured_at': capturedAt,
        'freshness': freshness,
        'days_old': daysOld,
        'distance_km': distanceKm,
        'store_product_url': storeProductUrl,
        'image_url': imageUrl,
        'presentation': presentation,
        'category': category,
      };

  final String storeName;
  final String productName;
  final String normalizedName;
  final String? branchName;
  final double price;
  final String source;
  final String capturedAt;
  final String freshness;
  final int daysOld;
  final double? distanceKm;
  final String? storeProductUrl;
  final String? imageUrl;
  final String? presentation;
  final String? category;

  String get comparisonKey {
    final name = normalizedName.isEmpty
        ? productName.toLowerCase().trim()
        : normalizedName.toLowerCase().trim();
    final pack = _normalizedPresentation(presentation ?? name);
    final baseName = name
        .replaceAll(
          RegExp(
            r'\b\d+\s*(?:pza|pack|paquete)?\s*(?:de|x)\s*\d+(?:[.,]\d+)?\s*(?:ml|l|g|kg)\b',
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'\b\d+(?:[.,]\d+)?\s*(?:ml|l|g|kg|pza|rollos?|gal)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return pack == null ? baseName : '$baseName|$pack';
  }

  String get observationLabel {
    final age = daysOld == 1 ? 'hace 1 día' : 'hace $daysOld días';
    return 'Actualizado $age · fuente directa';
  }
}

String? _normalizedPresentation(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll(RegExp(r'kilogramos?|kilos?'), 'kg')
      .replaceAll(RegExp(r'gramos?'), 'g')
      .replaceAll(RegExp(r'litros?|lts?'), 'l')
      .replaceAll(RegExp(r'mililitros?'), 'ml')
      .replaceAll(RegExp(r'piezas?|pzas?'), 'pza');
  final multipack = RegExp(
    r'\b(\d+)\s*(?:pza|pack|paquete)?\s*(?:de|x)\s*(\d+(?:[.,]\d+)?)\s*(ml|l|g|kg)\b',
  ).firstMatch(normalized);
  if (multipack != null) {
    final count = int.tryParse(multipack.group(1)!);
    final amount = double.tryParse(multipack.group(2)!.replaceAll(',', '.'));
    final unit = multipack.group(3);
    if (count != null && amount != null && unit != null) {
      final canonicalAmount =
          unit == 'kg' || unit == 'l' ? amount * 1000 : amount;
      final canonicalUnit = unit == 'kg'
          ? 'g'
          : unit == 'l'
              ? 'ml'
              : unit;
      return '${count}x$canonicalAmount:$canonicalUnit';
    }
  }
  final match = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*(ml|l|g|kg|pza|rollos?|gal)\b',
  ).firstMatch(normalized);
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  final unit = match.group(2);
  if (amount == null || unit == null) return null;
  if (unit == 'kg') return '${amount * 1000}:g';
  if (unit == 'l') return '${amount * 1000}:ml';
  if (unit == 'gal') return '${(amount * 3785.41).round()}:ml';
  if (unit.startsWith('rollo')) return '$amount:rollos';
  return '$amount:$unit';
}

class ProductComparisonGroup {
  const ProductComparisonGroup({
    required this.comparisonKey,
    required this.productName,
    required this.prices,
  });

  final String comparisonKey;
  final String productName;
  final List<PriceResult> prices;

  PriceResult get best => prices.first;

  PriceResult get worst => prices.reduce(
        (current, next) => next.price > current.price ? next : current,
      );

  int get storeCount => prices.map((price) => price.storeName).toSet().length;

  int get newestDaysOld => prices
      .map((price) => price.daysOld)
      .reduce((current, next) => next < current ? next : current);

  double get closestDistanceKm =>
      prices.map((price) => price.distanceKm).whereType<double>().fold<double>(
            double.infinity,
            (current, next) => next < current ? next : current,
          );
}

List<ProductComparisonGroup> groupPriceResults(
  List<PriceResult> results, {
  String sortMode = 'price_asc',
}) {
  final grouped = <String, List<PriceResult>>{};
  for (final result in results) {
    final key = result.comparisonKey;
    grouped.putIfAbsent(key, () => []).add(result);
  }

  return grouped.entries.map((entry) {
    final prices = _sortPricesForMode(entry.value, sortMode);
    return ProductComparisonGroup(
      comparisonKey: entry.key,
      productName: prices.first.productName,
      prices: prices,
    );
  }).toList()
    ..sort((a, b) {
      switch (sortMode) {
        case 'price_desc':
          return b.worst.price.compareTo(a.worst.price);
        case 'stores_desc':
          final storeOrder = b.storeCount.compareTo(a.storeCount);
          return storeOrder != 0
              ? storeOrder
              : a.best.price.compareTo(b.best.price);
        case 'fresh_desc':
          final freshnessOrder = a.newestDaysOld.compareTo(b.newestDaysOld);
          return freshnessOrder != 0
              ? freshnessOrder
              : a.best.price.compareTo(b.best.price);
        case 'distance':
          final distanceOrder = a.closestDistanceKm.compareTo(
            b.closestDistanceKm,
          );
          return distanceOrder != 0
              ? distanceOrder
              : a.best.price.compareTo(b.best.price);
        case 'price_asc':
        default:
          return a.best.price.compareTo(b.best.price);
      }
    });
}

List<PriceResult> _sortPricesForMode(
  List<PriceResult> prices,
  String sortMode,
) {
  final sorted = [...prices];
  if (sortMode == 'distance') {
    return sorted
      ..sort((a, b) {
        final aDistance = a.distanceKm;
        final bDistance = b.distanceKm;
        if (aDistance != null && bDistance != null) {
          final distanceOrder = aDistance.compareTo(bDistance);
          return distanceOrder != 0
              ? distanceOrder
              : a.price.compareTo(b.price);
        }
        if (aDistance != null) return -1;
        if (bDistance != null) return 1;
        return a.price.compareTo(b.price);
      });
  }
  return sorted..sort((a, b) => a.price.compareTo(b.price));
}

class ShoppingItem {
  const ShoppingItem({
    required this.comparisonKey,
    required this.productName,
    required this.quantity,
    required this.prices,
  });

  factory ShoppingItem.fromJson(Map<String, dynamic> json) => ShoppingItem(
        comparisonKey: json['comparison_key'] as String,
        productName: json['product_name'] as String,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        prices: (json['prices'] as List<dynamic>? ?? [])
            .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String comparisonKey;
  final String productName;
  final int quantity;
  final List<PriceResult> prices;

  ShoppingItem copyWith({int? quantity, List<PriceResult>? prices}) =>
      ShoppingItem(
        comparisonKey: comparisonKey,
        productName: productName,
        quantity: quantity ?? this.quantity,
        prices: prices ?? this.prices,
      );

  Map<String, dynamic> toJson() => {
        'comparison_key': comparisonKey,
        'product_name': productName,
        'quantity': quantity,
        'prices': prices.map((price) => price.toJson()).toList(),
      };
}

class FavoriteItem {
  const FavoriteItem({
    required this.comparisonKey,
    required this.productName,
    required this.bestPrice,
    required this.bestStoreName,
    required this.addedAt,
    this.imageUrl,
    this.presentation,
    this.category,
  });

  factory FavoriteItem.fromGroup(ProductComparisonGroup group) => FavoriteItem(
        comparisonKey: group.comparisonKey,
        productName: group.productName,
        bestPrice: group.best.price,
        bestStoreName: group.best.storeName,
        imageUrl: group.best.imageUrl,
        presentation: group.best.presentation,
        category: group.best.category,
        addedAt: DateTime.now().toIso8601String(),
      );

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
        comparisonKey: json['comparison_key'] as String,
        productName: json['product_name'] as String,
        bestPrice: (json['best_price'] as num?)?.toDouble() ?? 0,
        bestStoreName: json['best_store_name'] as String? ?? 'Tienda',
        imageUrl: json['image_url'] as String?,
        presentation: json['presentation'] as String?,
        category: json['category'] as String?,
        addedAt: json['added_at'] as String? ?? DateTime.now().toIso8601String(),
      );

  final String comparisonKey;
  final String productName;
  final double bestPrice;
  final String bestStoreName;
  final String addedAt;
  final String? imageUrl;
  final String? presentation;
  final String? category;

  Map<String, dynamic> toJson() => {
        'comparison_key': comparisonKey,
        'product_name': productName,
        'best_price': bestPrice,
        'best_store_name': bestStoreName,
        'image_url': imageUrl,
        'presentation': presentation,
        'category': category,
        'added_at': addedAt,
      };

  PriceResult toBestPriceResult() => PriceResult(
        storeName: bestStoreName,
        productName: productName,
        normalizedName: productName.toLowerCase(),
        price: bestPrice,
        capturedAt: addedAt,
        source: 'favorito',
        freshness: 'fresh',
        daysOld: 0,
        imageUrl: imageUrl,
        presentation: presentation,
        category: category,
      );
}

class StoreCartTotal {
  const StoreCartTotal({
    required this.storeName,
    required this.total,
    required this.coveredItems,
  });

  final String storeName;
  final double total;
  final int coveredItems;
}

List<StoreCartTotal> calculateStoreTotals(List<ShoppingItem> items) {
  final totals = <String, double>{};
  final coverage = <String, int>{};
  for (final item in items) {
    final bestByStore = <String, double>{};
    for (final price in item.prices) {
      final current = bestByStore[price.storeName];
      if (current == null || price.price < current) {
        bestByStore[price.storeName] = price.price;
      }
    }
    for (final entry in bestByStore.entries) {
      totals[entry.key] =
          (totals[entry.key] ?? 0) + entry.value * item.quantity;
      coverage[entry.key] = (coverage[entry.key] ?? 0) + 1;
    }
  }
  return totals.entries
      .map(
        (entry) => StoreCartTotal(
          storeName: entry.key,
          total: entry.value,
          coveredItems: coverage[entry.key] ?? 0,
        ),
      )
      .toList()
    ..sort((a, b) {
      final coverageOrder = b.coveredItems.compareTo(a.coveredItems);
      return coverageOrder != 0 ? coverageOrder : a.total.compareTo(b.total);
    });
}
