import 'package:flutter/material.dart';
import 'package:tiago_market_app/src/widgets/store_logo.dart';

class ProductImageFallback extends StatelessWidget {
  const ProductImageFallback({required this.storeName, super.key});

  final String storeName;

  @override
  Widget build(BuildContext context) {
    return Center(child: StoreLogo(storeName: storeName, size: 48));
  }
}
