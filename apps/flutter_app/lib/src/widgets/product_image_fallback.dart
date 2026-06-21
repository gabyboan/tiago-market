import 'package:flutter/material.dart';

class ProductImageFallback extends StatelessWidget {
  const ProductImageFallback({required this.storeName, super.key});

  final String storeName;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE2F3EB),
      child: Center(
        child: Text(
          storeName.isEmpty ? '?' : storeName.characters.first.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF006C51),
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
