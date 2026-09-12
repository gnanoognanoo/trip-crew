import 'package:tripcrew/features/trip_pay/models/payment_status.dart';

/// Result of verifying a payment with the provider or processing a verified webhook.
class PaymentVerification {
  final bool isVerified;
  final String providerReference;
  final String paymentIntentId;
  final PaymentStatus status;
  final int amountPaise;
  final String currency;
  final DateTime verifiedAt;
  final Map<String, dynamic> rawResponse;
  final String? failureReason;

  const PaymentVerification({
    required this.isVerified,
    required this.providerReference,
    required this.paymentIntentId,
    required this.status,
    required this.amountPaise,
    this.currency = 'INR',
    required this.verifiedAt,
    this.rawResponse = const {},
    this.failureReason,
  });

  Map<String, dynamic> toMap() => {
    'isVerified': isVerified,
    'providerReference': providerReference,
    'paymentIntentId': paymentIntentId,
    'status': status.name,
    'amountPaise': amountPaise,
    'currency': currency,
    'verifiedAt': verifiedAt.toIso8601String(),
    'rawResponse': rawResponse,
    if (failureReason != null) 'failureReason': failureReason,
  };
}
