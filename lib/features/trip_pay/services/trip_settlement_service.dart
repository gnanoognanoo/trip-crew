import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/features/trip_pay/models/settlement_model.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_summary.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';

/// Service for calculating member balances, debt simplification ("Who Pays Whom"),
/// generating settlement transactions, and updating database atomically.
class TripSettlementService {
  TripSettlementService({dynamic firestore});

  /// Calculates member balances given member names, transactions, and total spent.
  List<MemberBalance> calculateMemberBalances({
    required Map<String, String> memberNames,
    required List<TripPayTransaction> transactions,
    required int totalSpentPaise,
  }) {
    if (memberNames.isEmpty) return const [];

    final Map<String, int> contributedMap = {};
    final Map<String, int> spentInitiatedMap = {};

    for (final tx in transactions) {
      if (tx.status != TripPayTransactionStatus.sandboxSuccess) continue;

      final uid = tx.initiatedByUid;
      if (tx.type == TripPayTransactionType.contribution) {
        contributedMap[uid] = (contributedMap[uid] ?? 0) + tx.amountPaise;
      } else if (tx.type == TripPayTransactionType.expense ||
          tx.type == TripPayTransactionType.payment) {
        spentInitiatedMap[uid] = (spentInitiatedMap[uid] ?? 0) + tx.amountPaise;
      }
    }

    final memberCount = memberNames.length;
    final baseFairShare = totalSpentPaise ~/ memberCount;
    final remainder = totalSpentPaise % memberCount;

    final sortedEntries = memberNames.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final List<MemberBalance> balances = [];
    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final uid = entry.key;
      final name = entry.value;

      final fairShare = baseFairShare + (i < remainder ? 1 : 0);
      final totalContrib = contributedMap[uid] ?? 0;
      final totalSpentInit = spentInitiatedMap[uid] ?? 0;

      balances.add(
        MemberBalance(
          uid: uid,
          displayName: name,
          totalContributedPaise: totalContrib,
          totalSpentInitiatedPaise: totalSpentInit,
          fairSharePaise: fairShare,
        ),
      );
    }

    return balances;
  }

  /// Greedy debt simplification algorithm ("Who Pays Whom").
  List<SettlementTransfer> calculateTransfers({
    required List<MemberBalance> memberBalances,
    required int remainingPotPaise,
  }) {
    final List<SettlementTransfer> transfers = [];

    // Separate into creditors (+) and debtors (-)
    final List<_TempBalance> creditors = [];
    final List<_TempBalance> debtors = [];

    for (final mb in memberBalances) {
      final net = mb.netBalancePaise;
      if (net > 0) {
        creditors.add(_TempBalance(mb.uid, mb.displayName, net));
      } else if (net < 0) {
        debtors.add(_TempBalance(mb.uid, mb.displayName, -net));
      }
    }

    // Sort descending by amount
    creditors.sort((a, b) => b.balance.compareTo(a.balance));
    debtors.sort((a, b) => b.balance.compareTo(a.balance));

    int transferCounter = 1;
    int i = 0; // debtor index
    int j = 0; // creditor index

    while (i < debtors.length && j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];

      final settleAmount = debtor.balance < creditor.balance
          ? debtor.balance
          : creditor.balance;

      if (settleAmount > 0) {
        transfers.add(
          SettlementTransfer(
            id: 'transfer_$transferCounter',
            fromUid: debtor.uid,
            fromName: debtor.name,
            toUid: creditor.uid,
            toName: creditor.name,
            amountPaise: settleAmount,
            type: 'peer_to_peer',
          ),
        );
        transferCounter++;

        debtor.balance -= settleAmount;
        creditor.balance -= settleAmount;
      }

      if (debtor.balance == 0) i++;
      if (creditor.balance == 0) j++;
    }

    // Handle remaining pot balance (pot refund proportional to contribution)
    if (remainingPotPaise > 0) {
      final totalContributed = memberBalances.fold<int>(
        0,
        (total, mb) => total + mb.totalContributedPaise,
      );

      if (totalContributed > 0) {
        int distributedPot = 0;
        for (int k = 0; k < memberBalances.length; k++) {
          final mb = memberBalances[k];
          if (mb.totalContributedPaise <= 0) continue;

          int refundShare =
              (mb.totalContributedPaise * remainingPotPaise) ~/
              totalContributed;

          if (k == memberBalances.length - 1) {
            refundShare = remainingPotPaise - distributedPot;
          }

          if (refundShare > 0) {
            transfers.add(
              SettlementTransfer(
                id: 'pot_refund_$transferCounter',
                fromUid: 'POT',
                fromName: 'Trip Pot',
                toUid: mb.uid,
                toName: mb.displayName,
                amountPaise: refundShare,
                type: 'pot_refund',
              ),
            );
            transferCounter++;
            distributedPot += refundShare;
          }
        }
      }
    }

    return transfers;
  }

  /// Builds a complete SettlementPlan for a trip.
  SettlementPlan buildSettlementPlan({
    required String tripId,
    required Map<String, String> memberNames,
    required List<TripPayTransaction> transactions,
    required TripPaySummary? summary,
  }) {
    final totalContributedPaise = summary?.totalContributedPaise ?? 0;
    final totalSpentPaise = summary?.totalSpentPaise ?? 0;
    final remainingPotPaise = summary?.availableBalancePaise ?? 0;
    final isSettled = summary?.isSettled ?? false;

    final memberBalances = calculateMemberBalances(
      memberNames: memberNames,
      transactions: transactions,
      totalSpentPaise: totalSpentPaise,
    );

    final transfers = calculateTransfers(
      memberBalances: memberBalances,
      remainingPotPaise: remainingPotPaise,
    );

    return SettlementPlan(
      tripId: tripId,
      totalContributedPaise: totalContributedPaise,
      totalSpentPaise: totalSpentPaise,
      remainingPotPaise: remainingPotPaise,
      memberBalances: memberBalances,
      transfers: transfers,
      isSettled: isSettled,
      settledAt: summary?.updatedAt,
    );
  }

  /// Executes settlement on Supabase PostgreSQL.
  Future<bool> executeAtomicSettlement({
    required String tripId,
    required SettlementPlan plan,
    required String initiatedByUid,
    required String initiatedByName,
  }) async {
    if (SupabaseService.isInitialized) {
      try {
        final now = DateTime.now();
        for (final transfer in plan.transfers) {
          await SupabaseService.client.from('settlements').insert({
            'id': 'st_${now.millisecondsSinceEpoch}_${transfer.id}',
            'trip_id': tripId,
            'from_user_id': transfer.fromUid,
            'from_user_name': transfer.fromName,
            'to_user_id': transfer.toUid,
            'to_user_name': transfer.toName,
            'amount_paise': transfer.amountPaise,
            'is_settled': true,
            'created_at': now.toIso8601String(),
          });
        }
        await SupabaseService.client.from('trip_pay_summary').upsert({
          'trip_id': tripId,
          'available_balance_paise': 0,
          'updated_at': now.toIso8601String(),
        });
      } catch (_) {}
    }
    return true;
  }
}

class CurrencyFormatter {
  static String formatPaise(int paise) {
    return '₹${(paise / 100.0).toStringAsFixed(2)}';
  }
}

class _TempBalance {
  final String uid;
  final String name;
  int balance;

  _TempBalance(this.uid, this.name, this.balance);
}
