import 'package:tripcrew/features/trip_pay/models/trip_pay_summary.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';

/// Result of an audit reconciling the append-only ledger against the cached summary.
class TripPayReconciliationResult {
  final bool isConsistent;
  final int ledgerCalculatedBalancePaise;
  final int summaryAvailableBalancePaise;
  final int discrepancyPaise;
  final int totalContributedPaise;
  final int totalSpentPaise;
  final int totalRefundedPaise;
  final int netSpentPaise;
  final List<String> discrepancies;

  const TripPayReconciliationResult({
    required this.isConsistent,
    required this.ledgerCalculatedBalancePaise,
    required this.summaryAvailableBalancePaise,
    required this.discrepancyPaise,
    required this.totalContributedPaise,
    required this.totalSpentPaise,
    required this.totalRefundedPaise,
    required this.netSpentPaise,
    required this.discrepancies,
  });

  @override
  String toString() {
    if (isConsistent) {
      return 'TripPayReconciliation: MATCH (Ledger = ₹${(ledgerCalculatedBalancePaise / 100).toStringAsFixed(2)}, Summary = ₹${(summaryAvailableBalancePaise / 100).toStringAsFixed(2)})';
    }
    return 'TripPayReconciliation: INCONSISTENCY DETECTED! Discrepancy: ₹${(discrepancyPaise / 100).toStringAsFixed(2)}. Issues: ${discrepancies.join("; ")}';
  }
}

/// Audits and reconciles TripCrew Pay ledger against cached summary.
/// The append-only ledger in `trips/{tripId}/transactions` is the source of truth.
class TripPayReconciler {
  TripPayReconciler._();

  /// Reconciles the append-only transaction ledger against the cached summary document.
  static TripPayReconciliationResult reconcile({
    required List<TripPayTransaction> transactions,
    required TripPaySummary summary,
  }) {
    int totalContributedPaise = 0;
    int totalSpentPaise = 0;
    int totalRefundedPaise = 0;

    for (final tx in transactions) {
      // Only include successful sandbox transactions in ledger balance
      if (tx.status != TripPayTransactionStatus.sandboxSuccess) {
        continue;
      }

      switch (tx.type) {
        case TripPayTransactionType.contribution:
          totalContributedPaise += tx.amountPaise;
          break;
        case TripPayTransactionType.payment:
        case TripPayTransactionType.expense:
          totalSpentPaise += tx.amountPaise;
          break;
        case TripPayTransactionType.refund:
          totalRefundedPaise += tx.amountPaise;
          break;
        case TripPayTransactionType.adjustment:
          break;
      }
    }

    final netSpentPaise = totalSpentPaise - totalRefundedPaise;
    final ledgerCalculatedBalancePaise = totalContributedPaise - netSpentPaise;

    final List<String> discrepancies = [];

    if (summary.availableBalancePaise != ledgerCalculatedBalancePaise) {
      discrepancies.add(
        'Available balance mismatch: summary has ${summary.availableBalancePaise} paise, but ledger calculates $ledgerCalculatedBalancePaise paise',
      );
    }

    if (summary.totalContributedPaise != totalContributedPaise) {
      discrepancies.add(
        'Total contributed mismatch: summary has ${summary.totalContributedPaise} paise, but ledger calculates $totalContributedPaise paise',
      );
    }

    if (summary.totalSpentPaise != netSpentPaise) {
      discrepancies.add(
        'Total spent mismatch: summary has ${summary.totalSpentPaise} paise, but ledger net spent calculates $netSpentPaise paise',
      );
    }

    final discrepancyPaise =
        (summary.availableBalancePaise - ledgerCalculatedBalancePaise).abs();

    return TripPayReconciliationResult(
      isConsistent: discrepancies.isEmpty,
      ledgerCalculatedBalancePaise: ledgerCalculatedBalancePaise,
      summaryAvailableBalancePaise: summary.availableBalancePaise,
      discrepancyPaise: discrepancyPaise,
      totalContributedPaise: totalContributedPaise,
      totalSpentPaise: totalSpentPaise,
      totalRefundedPaise: totalRefundedPaise,
      netSpentPaise: netSpentPaise,
      discrepancies: discrepancies,
    );
  }
}
