import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/src/models/models.dart';

final _now = DateTime.utc(2026, 6, 28, 12);

PriceResult _localPrice({
  String? branchId = '11111111-1111-1111-1111-111111111111',
  String? branchName = 'Centro',
  bool available = true,
  String capturedAt = '2026-06-27T12:00:00Z',
}) {
  return PriceResult(
    storeName: 'Home Depot',
    storeSlug: 'home-depot-mx',
    productName: 'Pintura blanca',
    normalizedName: 'pintura blanca',
    branchId: branchId,
    branchName: branchName,
    branchAddress: 'Dirección verificada',
    price: 499,
    currency: 'MXN',
    available: available,
    capturedAt: capturedAt,
    source: 'home-depot-mx',
    freshness: 'fresh',
    daysOld: 1,
    distanceKm: 2.5,
    observationUrl: 'https://example.com/evidence',
  );
}

void main() {
  test('acepta precio local con sucursal, fecha y disponibilidad', () {
    expect(
      _localPrice().pilotRejectionReason(requireBranch: true, now: _now),
      isNull,
    );
  });

  test('rechaza precio local sin branch_id', () {
    expect(
      _localPrice(branchId: null).pilotRejectionReason(
        requireBranch: true,
        now: _now,
      ),
      'missing_branch_id',
    );
  });

  test('rechaza precio sin disponibilidad confirmada', () {
    expect(
      _localPrice(available: false).pilotRejectionReason(
        requireBranch: true,
        now: _now,
      ),
      'unavailable',
    );
  });

  test('rechaza precio vencido aunque el backend lo marque fresh', () {
    expect(
      _localPrice(capturedAt: '2026-05-01T12:00:00Z').pilotRejectionReason(
        requireBranch: true,
        now: _now,
      ),
      'expired',
    );
  });

  test('acepta referencia online sólo con evidencia y sin sucursal', () {
    const online = PriceResult(
      storeName: 'Tienda online',
      productName: 'Pintura blanca',
      price: 520,
      currency: 'MXN',
      available: true,
      capturedAt: '2026-06-27T12:00:00Z',
      source: 'catalogo-directo',
      freshness: 'fresh',
      daysOld: 1,
      storeProductUrl: 'https://example.com/product',
    );

    expect(
      online.pilotRejectionReason(requireBranch: false, now: _now),
      isNull,
    );
  });

  test('rechaza referencia online sin URL de evidencia', () {
    const online = PriceResult(
      storeName: 'Tienda online',
      productName: 'Pintura blanca',
      price: 520,
      currency: 'MXN',
      available: true,
      capturedAt: '2026-06-27T12:00:00Z',
      source: 'catalogo-directo',
      freshness: 'fresh',
      daysOld: 1,
    );

    expect(
      online.pilotRejectionReason(requireBranch: false, now: _now),
      'missing_online_evidence',
    );
  });
}
