import 'package:tiago_market_app/src/models/checkout.dart';

/// Implement with your backend, which owns credentials and provider adapters.
/// The backend resolves merchant/product IDs and revalidates stock and prices.
abstract interface class ShippingGateway {
  Future<List<ShippingQuote>> quote(CheckoutDraft draft);

  Future<ShipmentTracking> track(String orderId);
}

class ShippingQuote {
  const ShippingQuote({
    required this.id,
    required this.providerId,
    required this.serviceName,
    required this.amountMinor,
    required this.currency,
    required this.expiresAt,
    this.estimatedDeliveryFrom,
    this.estimatedDeliveryTo,
  });

  final String id;
  final String providerId;
  final String serviceName;
  final int amountMinor;
  final String currency;
  final DateTime expiresAt;
  final DateTime? estimatedDeliveryFrom;
  final DateTime? estimatedDeliveryTo;
}

enum ShipmentStatus { preparing, dispatched, inTransit, delivered, cancelled }

class ShipmentTracking {
  const ShipmentTracking({required this.status, this.trackingUrl});

  final ShipmentStatus status;
  final Uri? trackingUrl;
}

abstract interface class PaymentGateway {
  /// A server-created order owns the final amount and accepted shipping quote.
  /// Reuse an idempotency key on retries to prevent duplicate payments.
  Future<PaymentSession> createSession({
    required String orderId,
    required PaymentMethod method,
    required String idempotencyKey,
  });

  /// Return the server's webhook-verified status, not a browser return value.
  Future<PaymentStatus> status(String orderId);
}

enum PaymentStatus { pending, processing, paid, failed, cancelled, refunded }

class PaymentSession {
  const PaymentSession({
    required this.id,
    required this.providerId,
    required this.expiresAt,
    this.checkoutUrl,
    this.instructions,
  });

  final String id;
  final String providerId;
  final DateTime expiresAt;
  final Uri? checkoutUrl;
  final String? instructions;
}
