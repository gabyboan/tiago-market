import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiago_market_app/src/models/models.dart';

abstract class CartBackend {
  Future<List<ShoppingItem>> load(String userId);
  Future<void> save(String userId, List<ShoppingItem> items);
}

class SupabaseCartBackend implements CartBackend {
  SupabaseCartBackend(this.client);
  final SupabaseClient client;

  @override
  Future<List<ShoppingItem>> load(String userId) async {
    final row = await client
        .from('shopping_carts')
        .select('items')
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    return ShoppingListStorage.decode(row?['items'] ?? []);
  }

  @override
  Future<void> save(String userId, List<ShoppingItem> items) async {
    await client.from('shopping_carts').upsert({
      'user_id': userId,
      'items': items.map((item) => item.toJson()).toList(),
    }).timeout(const Duration(seconds: 10));
  }
}

/// Guests live only in memory. Signed-in carts have a per-account offline
/// cache and synchronize to the account protected by Supabase RLS.
class ShoppingListStorage extends ChangeNotifier {
  ShoppingListStorage({this.backend});
  final CartBackend? backend;
  List<ShoppingItem> _items = [];
  String? _userId;
  int _generation = 0;
  bool _pending = false;
  bool _needsRemoteMerge = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();
  String? syncError;

  List<ShoppingItem> get items => List.unmodifiable(_items);
  bool get signedIn => _userId != null;
  String get status => !signedIn
      ? 'Sin cuenta, tu carrito se pierde al cerrar la app. Ingresá con Google para guardarlo.'
      : syncError != null
          ? 'Carrito guardado en este dispositivo. Falta conexión para sincronizarlo con tu cuenta.'
          : _pending
              ? 'Guardando tu carrito en tu cuenta…'
              : 'Tu carrito está guardado en tu cuenta de Google en Tiago Market.';

  static List<ShoppingItem> decode(dynamic value) => (value as List)
      .map((item) =>
          ShoppingItem.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    // A failed operation must not block future changes.
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> selectAccount(String? userId) {
    final guestItems = _userId == null ? [..._items] : <ShoppingItem>[];
    _userId = userId;
    final generation = ++_generation;
    _items = [];
    _pending = false;
    _needsRemoteMerge = false;
    syncError = null;
    _notify();
    return _enqueue(() => _restore(userId, generation, guestItems));
  }

  Future<void> _restore(
      String? userId, int generation, List<ShoppingItem> guestItems) async {
    if (generation != _generation || _disposed) return;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    var restored = <ShoppingItem>[];
    var pending = false;
    var cachedRemoteKnown = false;
    var needsRemoteMerge = false;
    try {
      final cached = prefs.getString('tiago_market_cart_$userId');
      if (cached != null) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        restored = decode(data['items']);
        pending = data['pending'] == true;
        needsRemoteMerge = data['needsRemoteMerge'] == true;
        cachedRemoteKnown = !needsRemoteMerge;
      }
    } catch (_) {
      // A damaged cache can still be recovered from the account.
    }
    try {
      final remote = await backend!.load(userId);
      if (!pending) {
        restored = remote;
      } else if (needsRemoteMerge) {
        restored = _merge(remote, restored);
      }
      needsRemoteMerge = false;
      if (generation == _generation) syncError = null;
    } catch (_) {
      needsRemoteMerge = !cachedRemoteKnown;
      if (generation == _generation) syncError = 'offline';
    }
    if (generation != _generation || _disposed) return;
    _items = _merge(restored, guestItems);
    _needsRemoteMerge = needsRemoteMerge;
    _pending = pending || guestItems.isNotEmpty;
    _notify();
    if (_pending) {
      await _persist(userId, generation);
    } else {
      await _cache(prefs, userId, false);
    }
  }

  static List<ShoppingItem> _merge(
      List<ShoppingItem> saved, List<ShoppingItem> additions) {
    final merged = {for (final item in saved) item.comparisonKey: item};
    for (final item in additions) {
      final existing = merged[item.comparisonKey];
      merged[item.comparisonKey] = existing == null
          ? item
          : existing.copyWith(quantity: existing.quantity + item.quantity);
    }
    return merged.values.toList();
  }

  Future<void> _cache(SharedPreferences prefs, String userId, bool pending) =>
      prefs
          .setString(
              'tiago_market_cart_$userId',
              jsonEncode({
                'items': _items.map((item) => item.toJson()).toList(),
                'pending': pending,
                'needsRemoteMerge': _needsRemoteMerge,
              }))
          .then((_) {});

  Future<void> _persist(String userId, int generation) async {
    if (generation != _generation || _disposed) return;
    var snapshot = [..._items];
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _disposed) return;
    await _cache(prefs, userId, true);
    try {
      // If the account has never loaded on this device, fetch it before writing
      // so an offline first login cannot replace an existing cloud cart.
      if (_needsRemoteMerge) {
        final remote = await backend!.load(userId);
        if (generation != _generation || _disposed) return;
        snapshot = _merge(remote, snapshot);
        _items = snapshot;
        _needsRemoteMerge = false;
        await _cache(prefs, userId, true);
      }
      await backend!.save(userId, snapshot);
      if (generation != _generation || _disposed) return;
      _pending = false;
      syncError = null;
      await _cache(prefs, userId, false);
    } catch (_) {
      if (generation == _generation) syncError = 'offline';
    }
    _notify();
  }

  Future<void> change(List<ShoppingItem> Function(List<ShoppingItem>) update) {
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation || _disposed) return;
      _items = update([..._items]);
      _pending = signedIn;
      _notify();
      final userId = _userId;
      if (userId != null) await _persist(userId, generation);
    });
  }

  Future<void> synchronize() {
    final userId = _userId;
    final generation = _generation;
    return _enqueue(() async {
      if (userId == null || generation != _generation || _disposed) return;
      if (_pending) {
        await _persist(userId, generation);
      } else {
        await _restore(userId, generation, []);
      }
    });
  }

  void clearGuest() {
    if (signedIn) return;
    ++_generation;
    _items = [];
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
