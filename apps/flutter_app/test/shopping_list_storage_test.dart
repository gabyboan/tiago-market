import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/services/shopping_list_storage.dart';

class MemoryCartBackend implements CartBackend {
  final Map<String, List<ShoppingItem>> accounts = {};
  bool offline = false;
  Completer<void>? delayedLoad;

  @override
  Future<List<ShoppingItem>> load(String userId) async {
    if (delayedLoad != null) await delayedLoad!.future;
    if (offline) throw StateError('offline');
    return [...?accounts[userId]];
  }

  @override
  Future<void> save(String userId, List<ShoppingItem> items) async {
    if (offline) throw StateError('offline');
    accounts[userId] = [...items];
  }
}

ShoppingItem milk(int quantity) => ShoppingItem(
    comparisonKey: 'milk',
    productName: 'Leche',
    quantity: quantity,
    prices: const []);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('el invitado no guarda el carrito ni lo recupera al reiniciar',
      () async {
    final cart = ShoppingListStorage();
    await cart.change((_) => [milk(2)]);
    expect(cart.items.single.quantity, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    expect(ShoppingListStorage().items, isEmpty);
    cart.clearGuest();
    expect(cart.items, isEmpty);
    cart.dispose();
  });

  test('fusiona invitado con Google y recupera el carrito en otra instalación',
      () async {
    final backend = MemoryCartBackend()..accounts['a'] = [milk(3)];
    final cart = ShoppingListStorage(backend: backend);
    await cart.change((_) => [milk(2)]);
    await cart.selectAccount('a');
    expect(cart.items.single.quantity, 5);
    expect(backend.accounts['a']!.single.quantity, 5);
    // Simulate a new device without an offline cache.
    SharedPreferences.setMockInitialValues({});
    final other = ShoppingListStorage(backend: backend);
    await other.selectAccount('a');
    expect(other.items.single.quantity, 5);
    cart.dispose();
    other.dispose();
  });

  test('cerrar sesión vacía el carrito y no lo mezcla con otra cuenta',
      () async {
    final backend = MemoryCartBackend();
    final cart = ShoppingListStorage(backend: backend);
    await cart.selectAccount('a');
    await cart.change((_) => [milk(7)]);
    await cart.selectAccount(null);
    expect(cart.items, isEmpty);
    await cart.selectAccount('b');
    expect(cart.items, isEmpty);
    await cart.selectAccount('a');
    expect(cart.items.single.quantity, 7);
    cart.dispose();
  });

  test('reintenta los cambios offline incluso después de reiniciar', () async {
    final backend = MemoryCartBackend()..accounts['a'] = [milk(1)];
    final cart = ShoppingListStorage(backend: backend);
    await cart.selectAccount('a');
    backend.offline = true;
    await cart.change((_) => [milk(4)]);
    expect(cart.syncError, isNotNull);
    cart.dispose();
    final restarted = ShoppingListStorage(backend: backend);
    await restarted.selectAccount('a');
    expect(restarted.items.single.quantity, 4);
    backend.offline = false;
    await restarted.synchronize();
    expect(backend.accounts['a']!.single.quantity, 4);
    expect(restarted.syncError, isNull);
    restarted.dispose();
  });

  test('el primer login offline no sobrescribe el carrito de la cuenta',
      () async {
    final backend = MemoryCartBackend()
      ..accounts['a'] = [milk(8)]
      ..offline = true;
    final cart = ShoppingListStorage(backend: backend);
    await cart.selectAccount('a');
    await cart.change((_) => [milk(2)]);
    cart.dispose();
    backend.offline = false;
    final restarted = ShoppingListStorage(backend: backend);
    await restarted.selectAccount('a');
    expect(restarted.items.single.quantity, 10);
    expect(backend.accounts['a']!.single.quantity, 10);
    restarted.dispose();
  });

  test('los toques rápidos conservan todas las cantidades', () async {
    final backend = MemoryCartBackend();
    final cart = ShoppingListStorage(backend: backend);
    await cart.selectAccount('a');
    await cart.change((_) => [milk(1)]);
    await Future.wait(List.generate(
        10,
        (_) => cart.change((items) => [
              items.single.copyWith(quantity: items.single.quantity + 1),
            ])));
    expect(cart.items.single.quantity, 11);
    expect(backend.accounts['a']!.single.quantity, 11);
    cart.dispose();
  });

  test('una lectura pendiente no filtra datos después de cerrar sesión',
      () async {
    final backend = MemoryCartBackend()
      ..accounts['a'] = [milk(9)]
      ..delayedLoad = Completer<void>();
    final cart = ShoppingListStorage(backend: backend);
    final loading = cart.selectAccount('a');
    await Future<void>.delayed(Duration.zero);
    final logout = cart.selectAccount(null);
    backend.delayedLoad!.complete();
    await Future.wait([loading, logout]);
    expect(cart.items, isEmpty);
    expect(cart.signedIn, isFalse);
    cart.dispose();
  });
}
