import 'package:flutter/material.dart';
import 'package:tiago_market_app/src/models/models.dart';

class FavoritesSheet extends StatefulWidget {
  const FavoritesSheet({
    required this.items,
    required this.onRemove,
    required this.onAdd,
    super.key,
  });

  final List<FavoriteItem> items;
  final Future<void> Function(FavoriteItem item) onRemove;
  final Future<void> Function(FavoriteItem item) onAdd;

  @override
  State<FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<FavoritesSheet> {
  late final List<FavoriteItem> _items = [...widget.items];

  Future<void> _removeFavorite(FavoriteItem item) async {
    await widget.onRemove(item);
    if (!mounted) return;
    setState(() {
      _items.removeWhere((value) => value.comparisonKey == item.comparisonKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: ListView(
            children: [
              Text(
                'Favoritos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Guarda productos para volver a consultarlos rápido.',
              ),
              const SizedBox(height: 18),
              if (_items.isEmpty)
                const _EmptyFavoritesState()
              else
                for (final item in _items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: item.imageUrl == null
                        ? CircleAvatar(
                            backgroundColor: const Color(0xFFE1E8E4),
                            child: const Icon(
                              Icons.favorite_border,
                              color: Color(0xFF006C51),
                            ),
                          )
                        : CircleAvatar(
                            backgroundImage: NetworkImage(item.imageUrl!),
                            backgroundColor: const Color(0xFFE1E8E4),
                          ),
                    title: Text(item.productName),
                    subtitle: Text(
                      '${item.bestStoreName} · \$${item.bestPrice.toStringAsFixed(2)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => widget.onAdd(item),
                          icon: const Icon(Icons.add_shopping_cart_outlined),
                          tooltip: 'Agregar a lista',
                        ),
                        IconButton(
                          onPressed: () => _removeFavorite(item),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Eliminar favorito',
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFavoritesState extends StatelessWidget {
  const _EmptyFavoritesState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const Icon(
          Icons.favorite_outline,
          size: 62,
          color: Color(0xFF006C51),
        ),
        const SizedBox(height: 16),
        const Text(
          'No tienes favoritos aún',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Marca un producto con el corazón para guardarlo y consultarlo luego.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
