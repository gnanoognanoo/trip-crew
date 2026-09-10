import 'package:tripcrew/features/expenses/models/expense_model.dart';

class SettlementTransaction {
  final String fromUid;
  final String fromName;
  final String toUid;
  final String toName;
  final int amountPaise;

  const SettlementTransaction({
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.toName,
    required this.amountPaise,
  });

  double get amountRupees => amountPaise / 100.0;
}

/// Computes minimal settlement transactions across group members
/// to resolve debts with the fewest possible transactions.
class SettlementCalculator {
  SettlementCalculator._();

  static List<SettlementTransaction> calculateSettlements({
    required List<ExpenseModel> expenses,
    required Map<String, String> memberNames,
  }) {
    // Map of uid -> net balance in paise (+ means owed money, - means owes money)
    final Map<String, int> netBalances = {};

    for (final memberId in memberNames.keys) {
      netBalances[memberId] = 0;
    }

    for (final expense in expenses) {
      final participants = expense.participantUids.isNotEmpty
          ? expense.participantUids
          : memberNames.keys.toList();

      if (participants.isEmpty) continue;

      final share = (expense.amountPaise / participants.length).round();

      // Payer gets credited
      netBalances[expense.paidByUid] =
          (netBalances[expense.paidByUid] ?? 0) + expense.amountPaise;

      // Each participant owes their share
      for (final pUid in participants) {
        netBalances[pUid] = (netBalances[pUid] ?? 0) - share;
      }
    }

    final List<MapEntry<String, int>> creditors = [];
    final List<MapEntry<String, int>> debtors = [];

    for (final entry in netBalances.entries) {
      if (entry.value > 100) {
        // More than 1 rupee
        creditors.add(entry);
      } else if (entry.value < -100) {
        debtors.add(MapEntry(entry.key, -entry.value));
      }
    }

    // Sort descending
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final List<SettlementTransaction> transactions = [];
    int cIdx = 0;
    int dIdx = 0;

    while (cIdx < creditors.length && dIdx < debtors.length) {
      final creditor = creditors[cIdx];
      final debtor = debtors[dIdx];

      final settleAmount = creditor.value < debtor.value
          ? creditor.value
          : debtor.value;

      if (settleAmount > 0) {
        transactions.add(
          SettlementTransaction(
            fromUid: debtor.key,
            fromName: memberNames[debtor.key] ?? 'Member',
            toUid: creditor.key,
            toName: memberNames[creditor.key] ?? 'Member',
            amountPaise: settleAmount,
          ),
        );
      }

      final cRem = creditor.value - settleAmount;
      final dRem = debtor.value - settleAmount;

      if (cRem == 0) {
        cIdx++;
      } else {
        creditors[cIdx] = MapEntry(creditor.key, cRem);
      }

      if (dRem == 0) {
        dIdx++;
      } else {
        debtors[dIdx] = MapEntry(debtor.key, dRem);
      }
    }

    return transactions;
  }
}
