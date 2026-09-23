import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/widgets/product_image_fallback.dart';

class ProductComparisonCard extends StatelessWidget {
  const ProductComparisonCard({
    required this.group,
    required this.onAdd,
    required this.favorite,
    this.onToggleFavorite,
    this.recommendationMode = 'price',
    super.key,
  });

  final ProductComparisonGroup group;
  final VoidCallback onAdd;
  final bool favorite;
  final VoidCallback? onToggleFavorite;
  final String recommendationMode;

  @override
  Widget build(BuildContext context) {
    final best = group.best;
    final hasDistanceRecommendation =
        recommendationMode == 'distance' && best.distanceKm != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: 58,
            child: best.imageUrl == null
                ? ProductImageFallback(storeName: best.storeName)
                : Image.network(
                    best.imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        ProductImageFallback(storeName: best.storeName),
                  ),
          ),
        ),
        title: Text(
          group.productName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasDistanceRecommendation
                  ? 'Más cerca en ${best.storeName}'
                  : 'Mejor precio en ${best.storeName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${best.presentation ?? "Presentación por verificar"} - ${group.prices.length} ${group.prices.length == 1 ? "precio" : "precios"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: _BestPriceActions(
          price: best.price,
          onAdd: onAdd,
          favorite: favorite,
          onToggleFavorite: onToggleFavorite,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (var index = 0; index < group.prices.length; index++) ...[
            PriceCard(
              result: group.prices[index],
              recommended: index == 0,
              recommendationMode: recommendationMode,
            ),
            if (index < group.prices.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _BestPriceActions extends StatelessWidget {
  const _BestPriceActions({
    required this.price,
    required this.onAdd,
    required this.favorite,
    this.onToggleFavorite,
  });

  final double price;
  final VoidCallback onAdd;
  final bool favorite;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onToggleFavorite,
            tooltip: favorite ? 'Quitar de favoritos' : 'Agregar a favoritos',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 34),
            icon: Icon(
              favorite ? Icons.favorite : Icons.favorite_border,
              color: favorite ? const Color(0xFFB00020) : null,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF006C51),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onAdd,
            tooltip: 'Agregar a mi lista',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 34),
            icon: const Icon(Icons.add_shopping_cart_rounded),
          ),
        ],
      ),
    );
  }
}

class PriceCard extends StatelessWidget {
  const PriceCard({
    required this.result,
    this.recommended = false,
    this.recommendationMode = 'price',
    super.key,
  });

  final PriceResult result;
  final bool recommended;
  final String recommendationMode;

  @override
  Widget build(BuildContext context) {
    final detail = result.branchName == null
        ? 'Precios online, no verificados para una sucursal cercana.'
        : 'Sucursal: ${result.branchName}';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          result.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 8),
                        _RecommendationBadge(
                          label: recommendationMode == 'distance' &&
                                  result.distanceKm != null
                              ? 'Más cerca'
                              : 'Conviene acá',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (result.presentation != null) Text(result.presentation!),
                  if (result.branchAddress != null)
                    Text(result.branchAddress!,
                        style: const TextStyle(fontSize: 12)),
                  Text(
                    result.observationLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (result.distanceKm != null)
                    Text(
                      '${result.distanceKm!.toStringAsFixed(1)} km de distancia',
                      style: const TextStyle(
                        color: Color(0xFF006C51),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (result.evidenceUrl != null) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _openUrl(result.evidenceUrl!),
                        icon: const Icon(Icons.open_in_new_rounded, size: 17),
                        label: const Text('Ver fuente'),
                      ),
                    ),
                  ],
                  if (result.freshness == 'old') ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Este precio puede estar desactualizado.',
                      style: TextStyle(
                        color: Color(0xFF9A3412),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '\$${result.price.toStringAsFixed(2)} MXN',
              style: const TextStyle(
                color: Color(0xFF006C51),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _RecommendationBadge extends StatelessWidget {
  const _RecommendationBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE1F6ED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF006C51),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
