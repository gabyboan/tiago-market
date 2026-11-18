import 'package:flutter/material.dart';
import 'package:tiago_market_app/src/widgets/product_image_fallback.dart';

/// The demo bundles product photos; the live catalog supplies HTTPS URLs.
class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    required this.imageUrl,
    required this.productName,
    required this.storeName,
    super.key,
  });

  final String? imageUrl;
  final String productName;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    final image = imageUrl;
    final fallback = ProductImageFallback(storeName: storeName);
    if (image == null || image.isEmpty) return fallback;

    return ColoredBox(
      color: Colors.white,
      child: image.startsWith('assets/demo_products/')
          ? Image.asset(
              image,
              fit: BoxFit.contain,
              semanticLabel: productName,
              errorBuilder: (_, __, ___) => fallback,
            )
          : Image.network(
              image,
              // Retailer CDNs often do not allow CanvasKit cross-origin fetches.
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              fit: BoxFit.contain,
              semanticLabel: productName,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}
