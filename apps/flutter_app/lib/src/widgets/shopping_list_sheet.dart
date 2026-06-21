import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tiago_market_app/src/models/models.dart';

class ShoppingListSheet extends StatefulWidget {
  const ShoppingListSheet({
    required this.items,
    required this.onQuantityChanged,
    super.key,
  });

  final List<ShoppingItem> items;
  final Future<void> Function(ShoppingItem item, int quantity)
      onQuantityChanged;

  @override
  State<ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<ShoppingListSheet> {
  late final List<ShoppingItem> _items = [...widget.items];

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeQuantity(ShoppingItem item, int quantity) async {
    await widget.onQuantityChanged(item, quantity);
    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere(
        (value) => value.comparisonKey == item.comparisonKey,
      );
      if (index < 0) return;
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index] = item.copyWith(quantity: quantity);
      }
    });
    if (quantity <= 0) {
      _showMessage('${item.productName} eliminado de la lista.');
    } else {
      _showMessage(
        'Cantidad de ${item.productName} actualizada a $quantity.',
      );
    }
  }

  Future<void> _removeItem(ShoppingItem item) async {
    await _changeQuantity(item, 0);
  }

  Future<void> _clearList() async {
    if (_items.isEmpty) return;
    final items = [..._items];
    for (final item in items) {
      await widget.onQuantityChanged(item, 0);
    }
    if (!mounted) return;
    setState(() => _items.clear());
    _showMessage('Lista vaciada.');
  }

  Future<void> _shareShoppingList() async {
    if (_items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos para compartir.')),
      );
      return;
    }

    final shareText = _items.map((item) {
      final price = item.prices.isEmpty ? 0 : item.prices.first.price;
      return '${item.productName} x${item.quantity} - \$${(price * item.quantity).toStringAsFixed(2)}';
    }).join('\n');

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: 'Mi lista de compras',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lista compartida correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al compartir la lista: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = calculateStoreTotals(_items);
    final grandTotal = totals.fold<double>(0, (sum, total) => sum + total.total);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: ListView(
            children: [
              Text(
                'Mi lista de compras',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Los totales usan los últimos precios guardados al agregar cada producto.',
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Costo estimado',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        '${_items.length} ${_items.length == 1 ? 'producto' : 'productos'}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  Text(
                    '\$${grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFF006C51),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _items.isEmpty ? null : _shareShoppingList,
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Compartir lista'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _items.isEmpty ? null : _clearList,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Vaciar lista'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_items.isEmpty)
                const _EmptyState()
              else
                for (final item in _items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.productName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.prices.length} precios disponibles'),
                        const SizedBox(height: 4),
                        Text(
                          'Subtotal: \$${((item.prices.isEmpty ? 0 : item.prices.first.price) * item.quantity).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    leading: IconButton(
                      onPressed: () => _changeQuantity(item, item.quantity - 1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${item.quantity}'),
                        IconButton(
                          onPressed: () =>
                              _changeQuantity(item, item.quantity + 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton(
                          onPressed: () => _removeItem(item),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Eliminar producto',
                        ),
                      ],
                    ),
                  ),
              if (totals.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'Estimación por tienda',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                for (final total in totals)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(total.storeName),
                    subtitle: Text(
                      '${total.coveredItems} de ${_items.length} productos disponibles',
                    ),
                    trailing: Text(
                      '\$${total.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF006C51),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const Icon(
          Icons.shopping_cart_outlined,
          size: 62,
          color: Color(0xFF006C51),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tu lista está vacía',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Agrega productos desde la pantalla principal para ver una estimación de precios por tienda.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
