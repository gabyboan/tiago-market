import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tiago_market_app/auth/auth_account_button.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/pages/checkout_page.dart';
import 'package:tiago_market_app/src/widgets/store_logo.dart';

class ShoppingListSheet extends StatefulWidget {
  const ShoppingListSheet({
    required this.items,
    required this.onQuantityChanged,
    this.signedIn = false,
    this.persistenceStatus,
    this.onRetrySync,
    this.demo = false,
    super.key,
  });

  final List<ShoppingItem> items;
  final bool demo;
  final bool signedIn;
  final String? persistenceStatus;
  final Future<void> Function()? onRetrySync;
  final Future<void> Function(ShoppingItem item, int quantity)
      onQuantityChanged;

  @override
  State<ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<ShoppingListSheet> {
  late final List<ShoppingItem> _items = [...widget.items];

  @override
  void didUpdateWidget(covariant ShoppingListSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _items
      ..clear()
      ..addAll(widget.items);
  }

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
    // Offers from different stores are alternatives, not additional purchases.
    final grandTotal = _items.fold<double>(
        0,
        (sum, item) =>
            sum +
            (item.prices.isEmpty ? 0 : item.prices.first.price) *
                item.quantity);
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
              if (widget.persistenceStatus != null) ...[
                const SizedBox(height: 12),
                Text(widget.persistenceStatus!),
                if (!widget.signedIn && authEnabled)
                  const GoogleSignInButton(expanded: true),
                if (widget.signedIn && widget.onRetrySync != null)
                  TextButton.icon(
                    onPressed: widget.onRetrySync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar carrito'),
                  ),
              ],
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Costo estimado',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
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
                    key: const ValueKey('shopping-list-estimate'),
                    style: const TextStyle(
                      color: Color(0xFF006C51),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _items.isEmpty ? null : _shareShoppingList,
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Compartir lista'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _items.isEmpty ? null : _clearList,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Vaciar lista'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.demo)
                const Text(
                    'Demo: no se crean pedidos ni se solicitan datos personales.')
              else
                FilledButton.icon(
                  onPressed: _items.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CheckoutPage(
                                  items: List.unmodifiable(_items)),
                            ),
                          ),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Preparar envío y pago'),
                ),
              const SizedBox(height: 18),
              if (_items.isEmpty)
                const _EmptyState()
              else
                for (final item in _items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(item.productName,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        if (item.prices.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StoreLogo(
                                  storeName: item.prices.first.storeName,
                                  storeSlug: item.prices.first.storeSlug),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(item.prices.first.storeName)),
                            ],
                          ),
                        ],
                        Text('${item.prices.length} precios disponibles'),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Subtotal: \$${((item.prices.isEmpty ? 0 : item.prices.first.price) * item.quantity).toStringAsFixed(2)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () =>
                                      _changeQuantity(item, item.quantity - 1),
                                  icon: const Icon(Icons.remove_circle_outline),
                                  tooltip: 'Disminuir cantidad',
                                ),
                                Text('${item.quantity}'),
                                IconButton(
                                  onPressed: () =>
                                      _changeQuantity(item, item.quantity + 1),
                                  icon: const Icon(Icons.add_circle_outline),
                                  tooltip: 'Aumentar cantidad',
                                ),
                                IconButton(
                                  onPressed: () => _removeItem(item),
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Eliminar producto',
                                ),
                              ],
                            ),
                          ],
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StoreLogo(storeName: total.storeName, size: 36),
                            const SizedBox(width: 8),
                            Expanded(child: Text(total.storeName)),
                          ],
                        ),
                        Text(
                            '${total.coveredItems} de ${_items.length} productos disponibles'),
                        Text(
                          '\$${total.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Color(0xFF006C51),
                              fontWeight: FontWeight.w900,
                              fontSize: 18),
                        ),
                      ],
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
