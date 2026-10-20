import 'package:tiago_market_app/src/models/models.dart';

enum DeliveryMethod { homeDelivery }

enum PaymentMethod { card, bankTransfer, cashOnDelivery }

/// Money crosses the integration boundary as integer minor units, never doubles.
class CheckoutLine {
  const CheckoutLine({
    required this.productKey,
    required this.quantity,
    required this.offer,
  });

  final String productKey;
  final int quantity;
  final PriceResult offer;

  int get unitAmountMinor => (offer.price * 100).round();
  int get subtotalMinor => unitAmountMinor * quantity;

  Map<String, dynamic> toJson() => {
        'product_key': productKey,
        'quantity': quantity,
        'unit_amount_minor': unitAmountMinor,
        'currency': 'MXN',
        'offer': offer.toJson(),
      };
}

class CheckoutBasket {
  CheckoutBasket({
    required this.merchantKey,
    required this.storeName,
    required this.branchId,
    required this.branchName,
    required List<CheckoutLine> lines,
    required this.expectedItems,
  }) : lines = List.unmodifiable(lines);

  final String merchantKey;
  final String storeName;
  final String? branchId;
  final String? branchName;
  final List<CheckoutLine> lines;
  final int expectedItems;

  bool get isComplete => expectedItems > 0 && lines.length == expectedItems;
  int get subtotalMinor =>
      lines.fold(0, (sum, line) => sum + line.subtotalMinor);
  int get units => lines.fold(0, (sum, line) => sum + line.quantity);

  String get label => branchName == null || branchName!.isEmpty
      ? storeName
      : '$storeName · $branchName';
}

/// Each basket belongs to one merchant and branch. Online offers stay separate
/// from branch offers. Prices are references; a server must revalidate them.
List<CheckoutBasket> buildCheckoutBaskets(List<ShoppingItem> items) {
  final offers = <String, Map<String, CheckoutLine>>{};
  final merchants = <String, PriceResult>{};
  for (final item in items) {
    if (item.quantity <= 0) continue;
    for (final price in item.prices) {
      if (!price.available ||
          !price.price.isFinite ||
          price.price <= 0 ||
          price.currency.toUpperCase() != 'MXN' ||
          price.storeName.trim().isEmpty) {
        continue;
      }
      final key =
          '${price.storeSlug ?? price.storeName}|${price.branchId ?? price.branchName ?? 'online'}';
      merchants[key] = price;
      final merchantOffers = offers.putIfAbsent(key, () => {});
      final previous = merchantOffers[item.comparisonKey];
      if (previous == null || price.price < previous.offer.price) {
        merchantOffers[item.comparisonKey] = CheckoutLine(
          productKey: item.comparisonKey,
          quantity: item.quantity,
          offer: price,
        );
      }
    }
  }
  final expectedItems = items.where((item) => item.quantity > 0).length;
  return offers.entries.map((entry) {
    final merchant = merchants[entry.key]!;
    return CheckoutBasket(
      merchantKey: entry.key,
      storeName: merchant.storeName,
      branchId: merchant.branchId,
      branchName: merchant.branchName,
      lines: entry.value.values.toList(),
      expectedItems: expectedItems,
    );
  }).toList()
    ..sort((a, b) {
      final coverage = b.lines.length.compareTo(a.lines.length);
      return coverage != 0
          ? coverage
          : a.subtotalMinor.compareTo(b.subtotalMinor);
    });
}

class DeliveryContact {
  const DeliveryContact({
    required this.fullName,
    required this.phone,
    this.street = '',
    this.neighborhood = '',
    this.city = '',
    this.state = '',
    this.postalCode = '',
    this.instructions = '',
  });

  final String fullName;
  final String phone;
  final String street;
  final String neighborhood;
  final String city;
  final String state;
  final String postalCode;
  final String instructions;

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'phone': phone,
        'street': street,
        'neighborhood': neighborhood,
        'city': city,
        'state': state,
        'postal_code': postalCode,
        'country_code': 'MX',
        'instructions': instructions,
      };
}

class CheckoutDraft {
  const CheckoutDraft({
    required this.basket,
    required this.deliveryMethod,
    required this.paymentMethod,
    required this.contact,
  });

  final CheckoutBasket basket;
  final DeliveryMethod deliveryMethod;
  final PaymentMethod paymentMethod;
  final DeliveryContact contact;

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'status': 'draft',
        'merchant_key': basket.merchantKey,
        'branch_id': basket.branchId,
        'currency': 'MXN',
        'items': basket.lines.map((line) => line.toJson()).toList(),
        'estimated_subtotal_minor': basket.subtotalMinor,
        'delivery_method': deliveryMethod.name,
        'payment_method': paymentMethod.name,
        'contact': contact.toJson(),
      };
}
