import 'package:tripcrew/features/trip_pay/models/payment_status.dart';

/// Represents an attempt to make a contribution via external payment rails.
/// Stored in `trips/{tripId}/paymentAttempts/{attemptId}`.
///
/// IMPORTANT: Payment attempts do NOT represent money. They track the state
/// machine between user intent and provider confirmation. The immutable
/// `transactions` ledger remains the sole financial record after verification.
class PaymentAttempt {
  final String id;
  final String tripId;
  final String uid;
  final String type; // 'contribution'
  final int amountPaise;
  final int platformFeePaise;
  final int totalChargePaise;
  final String provider;
  final String? providerReference;
  final String clientRequestId;
  final String paymentIntentId;
  final PaymentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? verifiedAt;
  final String? ledgerTransactionId;
  final String? failureReason;

  const PaymentAttempt({
    required this.id,
    required this.tripId,
    required this.uid,
    this.type = 'contribution',
    required this.amountPaise,
    required this.platformFeePaise,
    required this.totalChargePaise,
    required this.provider,
    this.providerReference,
    required this.clientRequestId,
    required this.paymentIntentId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.verifiedAt,
    this.ledgerTransactionId,
    this.failureReason,
  });

  bool get isPending =>
      status == PaymentStatus.created ||
      status == PaymentStatus.pending ||
      status == PaymentStatus.verifying;

  bool get isSuccess => status == PaymentStatus.success;
  bool get isFailed => status == PaymentStatus.failed;
  bool get isExpired => status == PaymentStatus.expired;

  Map<String, dynamic> toMap() => {
    'id': id,
    'tripId': tripId,
    'uid': uid,
    'type': type,
    'amountPaise': amountPaise,
    'platformFeePaise': platformFeePaise,
    'totalChargePaise': totalChargePaise,
    'provider': provider,
    'providerReference': providerReference,
    'clientRequestId': clientRequestId,
    'paymentIntentId': paymentIntentId,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (verifiedAt != null) 'verifiedAt': verifiedAt!.toIso8601String(),
    if (ledgerTransactionId != null) 'ledgerTransactionId': ledgerTransactionId,
    if (failureReason != null) 'failureReason': failureReason,
  };

  factory PaymentAttempt.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDate(dynamic val) {
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      try {
        final dynamic dyn = val;
        if (dyn.toDate != null) return dyn.toDate() as DateTime;
      } catch (_) {}
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is String) return DateTime.tryParse(val);
      try {
        final dynamic dyn = val;
        if (dyn.toDate != null) return dyn.toDate() as DateTime;
      } catch (_) {}
      return null;
    }

    return PaymentAttempt(
      id: id,
      tripId: (map['tripId'] ?? map['trip_id']) as String? ?? '',
      uid: (map['uid'] ?? map['user_id']) as String? ?? '',
      type: map['type'] as String? ?? 'contribution',
      amountPaise: ((map['amountPaise'] ?? map['amount_paise']) as num?)?.toInt() ?? 0,
      platformFeePaise: ((map['platformFeePaise'] ?? map['platform_fee_paise']) as num?)?.toInt() ?? 0,
      totalChargePaise: ((map['totalChargePaise'] ?? map['total_charge_paise']) as num?)?.toInt() ?? 0,
      provider: map['provider'] as String? ?? 'sandbox',
      providerReference: (map['providerReference'] ?? map['provider_reference']) as String?,
      clientRequestId: (map['clientRequestId'] ?? map['client_request_id']) as String? ?? '',
      paymentIntentId: (map['paymentIntentId'] ?? map['payment_intent_id']) as String? ?? '',
      status: PaymentStatus.fromString(map['status'] as String? ?? 'created'),
      createdAt: parseDate(map['createdAt'] ?? map['created_at']),
      updatedAt: parseDate(map['updatedAt'] ?? map['updated_at']),
      verifiedAt: parseNullableDate(map['verifiedAt'] ?? map['verified_at']),
      ledgerTransactionId: (map['ledgerTransactionId'] ?? map['ledger_transaction_id']) as String?,
      failureReason: (map['failureReason'] ?? map['failure_reason']) as String?,
    );
  }

  PaymentAttempt copyWith({
    PaymentStatus? status,
    DateTime? updatedAt,
    DateTime? verifiedAt,
    String? providerReference,
    String? ledgerTransactionId,
    String? failureReason,
  }) {
    return PaymentAttempt(
      id: id,
      tripId: tripId,
      uid: uid,
      type: type,
      amountPaise: amountPaise,
      platformFeePaise: platformFeePaise,
      totalChargePaise: totalChargePaise,
      provider: provider,
      providerReference: providerReference ?? this.providerReference,
      clientRequestId: clientRequestId,
      paymentIntentId: paymentIntentId,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      ledgerTransactionId: ledgerTransactionId ?? this.ledgerTransactionId,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}
