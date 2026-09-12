import 'package:tripcrew/features/trip_pay/models/payment_status.dart';

/// Payment intent representing an initiated contribution request.
/// Created before directing the user to external payment rails (e.g. UPI).
class PaymentIntent {
  final String id;
  final String tripId;
  final String uid;
  final int amountPaise;
  final int platformFeePaise;
  final int totalChargePaise;
  final String currency;
  final String clientRequestId;
  final String provider;
  final PaymentStatus status;
  final String? paymentUrl;
  final String? upiIntentUrl;
  final String? qrCodeData;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Map<String, dynamic> metadata;

  const PaymentIntent({
    required this.id,
    required this.tripId,
    required this.uid,
    required this.amountPaise,
    required this.platformFeePaise,
    required this.totalChargePaise,
    this.currency = 'INR',
    required this.clientRequestId,
    required this.provider,
    required this.status,
    this.paymentUrl,
    this.upiIntentUrl,
    this.qrCodeData,
    required this.createdAt,
    required this.expiresAt,
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'tripId': tripId,
    'uid': uid,
    'amountPaise': amountPaise,
    'platformFeePaise': platformFeePaise,
    'totalChargePaise': totalChargePaise,
    'currency': currency,
    'clientRequestId': clientRequestId,
    'provider': provider,
    'status': status.name,
    'paymentUrl': paymentUrl,
    'upiIntentUrl': upiIntentUrl,
    'qrCodeData': qrCodeData,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'metadata': metadata,
  };

  factory PaymentIntent.fromMap(Map<String, dynamic> map, String id) {
    return PaymentIntent(
      id: id,
      tripId: map['tripId'] as String? ?? '',
      uid: map['uid'] as String? ?? '',
      amountPaise: (map['amountPaise'] as num?)?.toInt() ?? 0,
      platformFeePaise: (map['platformFeePaise'] as num?)?.toInt() ?? 0,
      totalChargePaise: (map['totalChargePaise'] as num?)?.toInt() ?? 0,
      currency: map['currency'] as String? ?? 'INR',
      clientRequestId: map['clientRequestId'] as String? ?? '',
      provider: map['provider'] as String? ?? 'sandbox',
      status: PaymentStatus.fromString(map['status'] as String? ?? 'created'),
      paymentUrl: map['paymentUrl'] as String?,
      upiIntentUrl: map['upiIntentUrl'] as String?,
      qrCodeData: map['qrCodeData'] as String?,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(map['expiresAt'] as String? ?? '') ??
          DateTime.now().add(const Duration(minutes: 15)),
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
    );
  }
}
