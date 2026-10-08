/// Summary model for the shared Trip Pot balance.
///
/// Stored at: trips/{tripId}/tripPay/summary
///
/// This is a cached aggregation of the transaction ledger. The ledger
/// (transactions subcollection) remains the source of truth.
class TripPaySummary {
  final String tripId;
  final String currency;
  final int totalContributedPaise;
  final int totalSpentPaise;
  final int availableBalancePaise;
  final bool isSettled;
  final DateTime updatedAt;

  const TripPaySummary({
    required this.tripId,
    this.currency = 'INR',
    this.totalContributedPaise = 0,
    this.totalSpentPaise = 0,
    this.availableBalancePaise = 0,
    this.isSettled = false,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'tripId': tripId,
      'currency': currency,
      'totalContributedPaise': totalContributedPaise,
      'totalSpentPaise': totalSpentPaise,
      'availableBalancePaise': availableBalancePaise,
      'isSettled': isSettled,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory TripPaySummary.fromMap(Map<String, dynamic> map) {
    return TripPaySummary(
      tripId: (map['tripId'] ?? map['trip_id']) as String? ?? '',
      currency: map['currency'] as String? ?? 'INR',
      totalContributedPaise:
          ((map['totalContributedPaise'] ?? map['total_contributed_paise']) as num?)?.toInt() ?? 0,
      totalSpentPaise:
          ((map['totalSpentPaise'] ?? map['total_spent_paise']) as num?)?.toInt() ?? 0,
      availableBalancePaise:
          ((map['availableBalancePaise'] ?? map['available_balance_paise']) as num?)?.toInt() ?? 0,
      isSettled: (map['isSettled'] ?? map['is_settled']) as bool? ?? false,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString()) ?? DateTime.now()
          : (map['updated_at'] != null
              ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
    );
  }

  /// Creates an empty summary for a new trip.
  factory TripPaySummary.empty(String tripId) {
    return TripPaySummary(tripId: tripId, updatedAt: DateTime.now());
  }

  TripPaySummary copyWith({
    int? totalContributedPaise,
    int? totalSpentPaise,
    int? availableBalancePaise,
    bool? isSettled,
    DateTime? updatedAt,
  }) {
    return TripPaySummary(
      tripId: tripId,
      currency: currency,
      totalContributedPaise:
          totalContributedPaise ?? this.totalContributedPaise,
      totalSpentPaise: totalSpentPaise ?? this.totalSpentPaise,
      availableBalancePaise:
          availableBalancePaise ?? this.availableBalancePaise,
      isSettled: isSettled ?? this.isSettled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
