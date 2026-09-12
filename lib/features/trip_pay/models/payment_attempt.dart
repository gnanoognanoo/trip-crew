import 'package:cloud_firestore/cloud_firestore.dart';
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
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return PaymentAttempt(
      id: id,
      tripId: map['tripId'] as String? ?? '',
      uid: map['uid'] as String? ?? '',
      type: map['type'] as String? ?? 'contribution',
      amountPaise: (map['amountPaise'] as num?)?.toInt() ?? 0,
      platformFeePaise: (map['platformFeePaise'] as num?)?.toInt() ?? 0,
      totalChargePaise: (map['totalChargePaise'] as num?)?.toInt() ?? 0,
      provider: map['provider'] as String? ?? 'sandbox',
      providerReference: map['providerReference'] as String?,
      clientRequestId: map['clientRequestId'] as String? ?? '',
      paymentIntentId: map['paymentIntentId'] as String? ?? '',
      status: PaymentStatus.fromString(map['status'] as String? ?? 'created'),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      verifiedAt: parseNullableDate(map['verifiedAt']),
      ledgerTransactionId: map['ledgerTransactionId'] as String?,
      failureReason: map['failureReason'] as String?,
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
