import 'package:flutter/material.dart';

/// Logos bundled with the app so identifying a seller works offline too.
class StoreLogo extends StatelessWidget {
  const StoreLogo({
    required this.storeName,
    this.storeSlug,
    this.size = 28,
    super.key,
  });

  final String storeName;
  final String? storeSlug;
  final double size;

  static String? assetFor(String storeName, {String? storeSlug}) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('á', 'a')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    String? match(String value) {
      final name = normalize(value);
      for (final entry in const {
        'chedraui': 'chedraui',
        'merco': 'merco',
        'arteli': 'arteli',
        'smartfinal': 'smart-final',
        'smartnfinal': 'smart-final',
        'homedepot': 'home-depot',
        'steren': 'steren',
        'walmart': 'walmart',
        'bodegaaurrera': 'bodega-aurrera',
        'lacomer': 'la-comer',
        'citymarket': 'city-market',
      }.entries) {
        if (name == entry.key || name.startsWith(entry.key)) {
          return 'assets/store_logos/${entry.value}.png';
        }
      }
      return null;
    }

    return match(storeSlug ?? '') ?? match(storeName);
  }

  @override
  Widget build(BuildContext context) {
    final asset = assetFor(storeName, storeSlug: storeSlug);
    final fallback = Center(
      child: Icon(Icons.storefront_rounded,
          size: size * .65, color: const Color(0xFF006C51)),
    );
    return Semantics(
      label: 'Logo de $storeName',
      image: true,
      child: Tooltip(
        message: storeName,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE1E8E4)),
          ),
          child: asset == null
              ? fallback
              : Image.asset(asset,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => fallback),
        ),
      ),
    );
  }
}
