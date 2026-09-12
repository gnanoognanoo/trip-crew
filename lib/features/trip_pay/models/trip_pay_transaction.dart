/// Possible transaction types for the TripCrew Pay ledger.
enum TripPayTransactionType {
  contribution,
  payment,
  refund,
  adjustment;

  String get label {
    switch (this) {
      case TripPayTransactionType.contribution:
        return 'Contribution';
      case TripPayTransactionType.payment:
        return 'Payment';
      case TripPayTransactionType.refund:
        return 'Refund';
      case TripPayTransactionType.adjustment:
        return 'Adjustment';
    }
  }

  static TripPayTransactionType fromString(String value) {
    switch (value) {
      case 'contribution':
        return TripPayTransactionType.contribution;
      case 'payment':
        return TripPayTransactionType.payment;
      case 'refund':
        return TripPayTransactionType.refund;
      case 'adjustment':
        return TripPayTransactionType.adjustment;
      default:
        return TripPayTransactionType.payment;
    }
  }
}

/// Possible transaction statuses.
enum TripPayTransactionStatus {
  sandboxSuccess,
  pending,
  failed,
  refunded;

  String get label {
    switch (this) {
      case TripPayTransactionStatus.sandboxSuccess:
        return 'Sandbox Success';
      case TripPayTransactionStatus.pending:
        return 'Pending';
      case TripPayTransactionStatus.failed:
        return 'Failed';
      case TripPayTransactionStatus.refunded:
        return 'Refunded';
    }
  }

  String get value {
    switch (this) {
      case TripPayTransactionStatus.sandboxSuccess:
        return 'sandbox_success';
      case TripPayTransactionStatus.pending:
        return 'pending';
      case TripPayTransactionStatus.failed:
        return 'failed';
      case TripPayTransactionStatus.refunded:
        return 'refunded';
    }
  }

  static TripPayTransactionStatus fromString(String value) {
    switch (value) {
      case 'sandbox_success':
        return TripPayTransactionStatus.sandboxSuccess;
      case 'pending':
        return TripPayTransactionStatus.pending;
      case 'failed':
        return TripPayTransactionStatus.failed;
      case 'refunded':
        return TripPayTransactionStatus.refunded;
      default:
        return TripPayTransactionStatus.pending;
    }
  }
}

/// Domain model representing a single transaction in the TripCrew Pay ledger.
///
/// Stored at: trips/{tripId}/transactions/{transactionId}
///
/// This is an append-only record. Existing transactions must never be
/// edited or deleted. Refunds create a new transaction referencing the original.
class TripPayTransaction {
  final String id;
  final String tripId;
  final TripPayTransactionType type;
  final int amountPaise;
  final String currency;
  final String initiatedByUid;
  final String initiatedByName;
  final String category;
  final String description;
  final String? merchantName;
  final TripPayTransactionStatus status;
  final DateTime createdAt;
  final int balanceBeforePaise;
  final int balanceAfterPaise;
  final String? relatedExpenseId;
  final String? relatedTransactionId;
  final int calculatedPlatformFeePaise;
  final String? provider;
  final String? providerReference;
  final String mode;
  final String clientRequestId;

  const TripPayTransaction({
    required this.id,
    required this.tripId,
    required this.type,
    required this.amountPaise,
    this.currency = 'INR',
    required this.initiatedByUid,
    required this.initiatedByName,
    this.category = 'General',
    this.description = '',
    this.merchantName,
    this.status = TripPayTransactionStatus.sandboxSuccess,
    required this.createdAt,
    this.balanceBeforePaise = 0,
    this.balanceAfterPaise = 0,
    this.relatedExpenseId,
    this.relatedTransactionId,
    this.calculatedPlatformFeePaise = 0,
    this.provider,
    this.providerReference,
    this.mode = 'sandbox',
    required this.clientRequestId,
  });

  /// Whether this transaction adds money to the pot.
  bool get isCredit =>
      type == TripPayTransactionType.contribution ||
      type == TripPayTransactionType.refund;

  /// Whether this transaction removes money from the pot.
  bool get isDebit => type == TripPayTransactionType.payment;

  double get amountRupees => amountPaise / 100.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'type': type.name,
      'amountPaise': amountPaise,
      'currency': currency,
      'initiatedByUid': initiatedByUid,
      'initiatedByName': initiatedByName,
      'category': category,
      'description': description,
      'merchantName': merchantName,
      'status': status.value,
      'createdAt': createdAt.toIso8601String(),
      'balanceBeforePaise': balanceBeforePaise,
      'balanceAfterPaise': balanceAfterPaise,
      'relatedExpenseId': relatedExpenseId,
      'relatedTransactionId': relatedTransactionId,
      'calculatedPlatformFeePaise': calculatedPlatformFeePaise,
      'provider': provider,
      'providerReference': providerReference,
      'mode': mode,
      'clientRequestId': clientRequestId,
    };
  }

  factory TripPayTransaction.fromMap(Map<String, dynamic> map, String id) {
    return TripPayTransaction(
      id: id,
      tripId: map['tripId'] as String? ?? '',
      type: TripPayTransactionType.fromString(
        map['type'] as String? ?? 'payment',
      ),
      amountPaise: (map['amountPaise'] as num?)?.toInt() ?? 0,
      currency: map['currency'] as String? ?? 'INR',
      initiatedByUid: map['initiatedByUid'] as String? ?? '',
      initiatedByName: map['initiatedByName'] as String? ?? 'Member',
      category: map['category'] as String? ?? 'General',
      description: map['description'] as String? ?? '',
      merchantName: map['merchantName'] as String?,
      status: TripPayTransactionStatus.fromString(
        map['status'] as String? ?? 'pending',
      ),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      balanceBeforePaise: (map['balanceBeforePaise'] as num?)?.toInt() ?? 0,
      balanceAfterPaise: (map['balanceAfterPaise'] as num?)?.toInt() ?? 0,
      relatedExpenseId: map['relatedExpenseId'] as String?,
      relatedTransactionId: map['relatedTransactionId'] as String?,
      calculatedPlatformFeePaise:
          (map['calculatedPlatformFeePaise'] as num?)?.toInt() ?? 0,
      provider: map['provider'] as String?,
      providerReference: map['providerReference'] as String?,
      mode: map['mode'] as String? ?? 'sandbox',
      clientRequestId: map['clientRequestId'] as String? ?? '',
    );
  }
}
