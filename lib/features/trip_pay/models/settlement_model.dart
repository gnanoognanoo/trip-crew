library;

/// Domain models for the TripCrew Pay Settlement module.

/// Net financial position of a member in a trip.
class MemberBalance {
  final String uid;
  final String displayName;
  final int totalContributedPaise;
  final int totalSpentInitiatedPaise;
  final int fairSharePaise;

  const MemberBalance({
    required this.uid,
    required this.displayName,
    this.totalContributedPaise = 0,
    this.totalSpentInitiatedPaise = 0,
    this.fairSharePaise = 0,
  });

  /// Net balance in paise.
  /// Positive (+) = Member over-contributed / is owed money.
  /// Negative (-) = Member under-contributed / owes money.
  int get netBalancePaise => totalContributedPaise - fairSharePaise;

  double get netBalanceRupees => netBalancePaise / 100.0;
  double get contributedRupees => totalContributedPaise / 100.0;
  double get fairShareRupees => fairSharePaise / 100.0;
}

/// Represents a single peer-to-peer or pot settlement transfer ("Who Pays Whom").
class SettlementTransfer {
  final String id;
  final String fromUid;
  final String fromName;
  final String toUid;
  final String toName;
  final int amountPaise;
  final String type; // 'peer_to_peer', 'pot_refund', or 'pot_topup'

  const SettlementTransfer({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.toName,
    required this.amountPaise,
    this.type = 'peer_to_peer',
  });

  double get amountRupees => amountPaise / 100.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromUid': fromUid,
      'fromName': fromName,
      'toUid': toUid,
      'toName': toName,
      'amountPaise': amountPaise,
      'type': type,
    };
  }

  factory SettlementTransfer.fromMap(Map<String, dynamic> map, String id) {
    return SettlementTransfer(
      id: id,
      fromUid: map['fromUid'] as String? ?? '',
      fromName: map['fromName'] as String? ?? 'Member',
      toUid: map['toUid'] as String? ?? '',
      toName: map['toName'] as String? ?? 'Member',
      amountPaise: (map['amountPaise'] as num?)?.toInt() ?? 0,
      type: map['type'] as String? ?? 'peer_to_peer',
    );
  }
}

/// Comprehensive Settlement Plan for a Trip.
class SettlementPlan {
  final String tripId;
  final int totalContributedPaise;
  final int totalSpentPaise;
  final int remainingPotPaise;
  final List<MemberBalance> memberBalances;
  final List<SettlementTransfer> transfers;
  final bool isSettled;
  final DateTime? settledAt;

  const SettlementPlan({
    required this.tripId,
    required this.totalContributedPaise,
    required this.totalSpentPaise,
    required this.remainingPotPaise,
    required this.memberBalances,
    required this.transfers,
    this.isSettled = false,
    this.settledAt,
  });

  bool get hasRemainingPot => remainingPotPaise > 0;

  Map<String, dynamic> toMap() {
    return {
      'tripId': tripId,
      'totalContributedPaise': totalContributedPaise,
      'totalSpentPaise': totalSpentPaise,
      'remainingPotPaise': remainingPotPaise,
      'memberBalances': memberBalances
          .map((mb) => {
                'uid': mb.uid,
                'displayName': mb.displayName,
                'totalContributedPaise': mb.totalContributedPaise,
                'totalSpentInitiatedPaise': mb.totalSpentInitiatedPaise,
                'fairSharePaise': mb.fairSharePaise,
                'netBalancePaise': mb.netBalancePaise,
              })
          .toList(),
      'transfers': transfers.map((t) => t.toMap()).toList(),
      'isSettled': isSettled,
      'settledAt': settledAt?.toIso8601String(),
    };
  }
}
