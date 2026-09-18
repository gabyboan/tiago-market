import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tools/ingestion/bin/chedraui_branch_probe.dart' as probe;

void main() {
  const firstBranch = probe.BranchTarget(
    externalKey: 'chedraui-mx:013',
    name: 'Chedraui México Buen Tono',
    address: 'Buen Tono 8, Centro, Cuauhtémoc, CDMX, 06070',
    rawRegionId: 'SW#chedrauimx0013',
  );
  const secondBranch = probe.BranchTarget(
    externalKey: 'chedraui-mx:016',
    name: 'Chedraui México Ánfora',
    address: 'Ánfora 71, Madero, Venustiano Carranza, CDMX, 15320',
    rawRegionId: 'SW#chedrauimx0016',
  );

  test('confirms only attributable observations with a local difference', () {
    final outcomes = [
      probe.BranchOutcome.observed(
        branch: firstBranch,
        snapshot: snapshot(price: 31, quantity: 10),
        observedRegionId: firstBranch.rawRegionId,
        attributable: true,
        reason: 'ok',
        sessionStatusCode: 200,
        productStatusCode: 200,
      ),
      probe.BranchOutcome.observed(
        branch: secondBranch,
        snapshot: snapshot(price: 32, quantity: 10),
        observedRegionId: secondBranch.rawRegionId,
        attributable: true,
        reason: 'ok',
        sessionStatusCode: 200,
        productStatusCode: 200,
      ),
    ];

    expect(
      probe.classifyProbe(outcomes),
      probe.ProbeClassification.confirmedBranchLocal,
    );
  });

  test('keeps identical attributable observations ambiguous', () {
    final outcomes = [
      probe.BranchOutcome.observed(
        branch: firstBranch,
        snapshot: snapshot(price: 31, quantity: 10),
        observedRegionId: firstBranch.rawRegionId,
        attributable: true,
        reason: 'ok',
        sessionStatusCode: 200,
        productStatusCode: 200,
      ),
      probe.BranchOutcome.observed(
        branch: secondBranch,
        snapshot: snapshot(price: 31, quantity: 10),
        observedRegionId: secondBranch.rawRegionId,
        attributable: true,
        reason: 'ok',
        sessionStatusCode: 200,
        productStatusCode: 200,
      ),
    ];

    expect(probe.classifyProbe(outcomes), probe.ProbeClassification.ambiguous);
  });

  test('decodes nested VTEX region identifiers', () {
    final segment = base64.encode(
      utf8.encode(
        jsonEncode({
          'regionId': base64.encode(utf8.encode(firstBranch.rawRegionId)),
        }),
      ),
    );

    expect(
      probe.decodeRegionFromSegmentToken(segment),
      firstBranch.rawRegionId,
    );
  });
}

probe.ProductSnapshot snapshot({required double price, required int quantity}) {
  return probe.ProductSnapshot(
    sku: '3061483',
    name: 'Refresco Coca-Cola Original 1L',
    price: price,
    currency: 'MXN',
    available: quantity > 0,
    availableQuantity: quantity,
    evidenceUrl:
        'https://www.chedraui.com.mx/refresco-coca-cola-original-1l-3061483/p',
    capturedAt: '2026-06-24T00:00:00Z',
  );
}
