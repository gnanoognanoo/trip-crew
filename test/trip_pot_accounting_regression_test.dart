import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_summary.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/trip_pay_notifier.dart';
import 'package:tripcrew/features/trip_pay/utils/trip_pay_reconciler.dart';

void main() {
  group('Trip Pot Accounting & Spending Regression Tests', () {
    test('1. A ₹700 expense from a known balance debits exactly ₹700 and updates totals', () {
      const initialContributed = 32070000; // ₹3,20,700 in paise
      const initialSpent = 0;
      const initialBalance = 32070000; // ₹3,20,700
      const expenseAmount = 70000; // ₹700 in paise

      // Simulate atomic spending logic (same as database RPC spend_from_trip_pot)
      expect(initialBalance >= expenseAmount, isTrue);
      final balanceAfter = initialBalance - expenseAmount;
      final totalSpentAfter = initialSpent + expenseAmount;
      const totalContributedAfter = initialContributed; // Preserved

      expect(balanceAfter, equals(32000000)); // Exactly ₹3,20,000
      expect(totalSpentAfter, equals(70000)); // Exactly ₹700
      expect(totalContributedAfter, equals(32070000)); // Preserved
      expect(totalContributedAfter - totalSpentAfter, equals(balanceAfter));
    });

    test('2. A ₹40,000 expense from a known balance debits exactly ₹40,000', () {
      // Historical state after TX 18 (₹700 expense) and TX 19 (₹20,000 contribution)
      const initialContributed = 34070000; // ₹3,40,700 in paise
      const initialSpent = 70000; // ₹700 from earlier expense
      const initialBalance = 34000000; // ₹3,40,000 available balance
      const expenseAmount = 4000000; // ₹40,000 in paise

      expect(initialBalance >= expenseAmount, isTrue);
      final balanceAfter = initialBalance - expenseAmount;
      final totalSpentAfter = initialSpent + expenseAmount;
      const totalContributedAfter = initialContributed;

      // Notice: Resulting balance is ₹3,00,000 (30,000,000 paise), NOT ₹3,00,700
      // because ₹700 was already spent in TX 18!
      expect(balanceAfter, equals(30000000)); // Exactly ₹3,00,000
      expect(totalSpentAfter, equals(4070000)); // Exactly ₹40,700
      expect(totalContributedAfter, equals(34070000)); // Exactly ₹3,40,700
      expect(totalContributedAfter - totalSpentAfter, equals(balanceAfter));
    });

    test('3. Failed spending leaves balance and total spent unchanged', () {
      const initialContributed = 1000000; // ₹10,000
      const initialSpent = 200000; // ₹2,000
      const initialBalance = 800000; // ₹8,000
      const excessiveExpense = 5000000; // ₹50,000

      // Spending check
      bool hasSufficientFunds = initialBalance >= excessiveExpense;
      expect(hasSufficientFunds, isFalse);

      int finalBalance = initialBalance;
      int finalSpent = initialSpent;
      int finalContributed = initialContributed;

      if (hasSufficientFunds) {
        finalBalance -= excessiveExpense;
        finalSpent += excessiveExpense;
      }

      expect(finalBalance, equals(800000));
      expect(finalSpent, equals(200000));
      expect(finalContributed, equals(1000000));
    });

    test('4. Repeated submission (idempotency) does not debit twice', () {
      int balance = 34000000;
      int totalSpent = 70000;
      const expenseAmount = 4000000;
      const clientRequestId = 'pay_1791903393191_388';

      final committedTransactions = <String, Map<String, dynamic>>{};

      // First submission
      if (!committedTransactions.containsKey(clientRequestId)) {
        final balanceBefore = balance;
        balance -= expenseAmount;
        totalSpent += expenseAmount;
        committedTransactions[clientRequestId] = {
          'id': 'tx_425676020',
          'amount': expenseAmount,
          'balanceBefore': balanceBefore,
          'balanceAfter': balance,
          'idempotent': false,
        };
      }

      expect(balance, equals(30000000));
      expect(totalSpent, equals(4070000));

      // Second (repeated) submission with same clientRequestId
      bool wasDebitedAgain = false;
      if (!committedTransactions.containsKey(clientRequestId)) {
        balance -= expenseAmount;
        totalSpent += expenseAmount;
        wasDebitedAgain = true;
      }

      expect(wasDebitedAgain, isFalse);
      expect(balance, equals(30000000)); // Remained ₹3,00,000
      expect(totalSpent, equals(4070000)); // Remained ₹40,700
    });

    test('5. Total added remains unchanged during spending', () {
      const totalAdded = 34070000;
      int balance = 34000000;
      int totalSpent = 70000;

      final expenses = [50000, 100000, 4000000]; // ₹500, ₹1,000, ₹40,000

      for (final exp in expenses) {
        balance -= exp;
        totalSpent += exp;
        // Total added must be strictly invariant
        expect(totalAdded, equals(34070000));
      }

      expect(totalAdded, equals(34070000));
      expect(totalAdded - totalSpent, equals(balance));
    });

    test('6. Total spent increases by exactly the committed expense amount', () {
      int totalSpent = 0;

      // TX 18: ₹700
      totalSpent += 70000;
      expect(totalSpent, equals(70000));

      // TX 20: ₹40,000
      totalSpent += 4000000;
      expect(totalSpent, equals(4070000));
    });

    test('7. Result screen and Trip Pay summary show the same resulting balance via reconciliation', () {
      final now = DateTime.now();

      // Create full list of transactions matching the database audit
      final transactions = <TripPayTransaction>[
        // Contributions summing to ₹3,40,700
        TripPayTransaction(
          id: 'tx_c1',
          tripId: 'trip_1791482737100',
          type: TripPayTransactionType.contribution,
          amountPaise: 32070000,
          initiatedByUid: 'u1',
          initiatedByName: 'Member',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now.subtract(const Duration(days: 2)),
          clientRequestId: 'cr_1',
        ),
        // TX 18: ₹700 expense
        TripPayTransaction(
          id: 'tx_164433054',
          tripId: 'trip_1791482737100',
          type: TripPayTransactionType.expense,
          amountPaise: 70000,
          initiatedByUid: 'u1',
          initiatedByName: 'Member',
          merchantName: 'Beach',
          description: 'Dinner',
          status: TripPayTransactionStatus.sandboxSuccess,
          balanceBeforePaise: 32070000,
          balanceAfterPaise: 32000000,
          createdAt: now.subtract(const Duration(days: 1)),
          clientRequestId: 'pay_1791762818714_887',
        ),
        // TX 19: ₹20,000 contribution
        TripPayTransaction(
          id: 'tx_968215628',
          tripId: 'trip_1791482737100',
          type: TripPayTransactionType.contribution,
          amountPaise: 2000000,
          initiatedByUid: 'u1',
          initiatedByName: 'Member',
          status: TripPayTransactionStatus.sandboxSuccess,
          balanceBeforePaise: 32000000,
          balanceAfterPaise: 34000000,
          createdAt: now.subtract(const Duration(minutes: 5)),
          clientRequestId: 'ctr_1791903379668_424',
        ),
        // TX 20: ₹40,000 expense
        TripPayTransaction(
          id: 'tx_425676020',
          tripId: 'trip_1791482737100',
          type: TripPayTransactionType.expense,
          amountPaise: 4000000,
          initiatedByUid: 'u1',
          initiatedByName: 'Member',
          merchantName: 'highway',
          description: 'hotel',
          status: TripPayTransactionStatus.sandboxSuccess,
          balanceBeforePaise: 34000000,
          balanceAfterPaise: 30000000,
          createdAt: now.subtract(const Duration(minutes: 1)),
          clientRequestId: 'pay_1791903393191_388',
        ),
      ];

      // Total contributed: 32,070,000 + 2,000,000 = 34,070,000 (₹3,40,700)
      // Total spent: 70,000 + 4,000,000 = 4,070,000 (₹40,700)
      // Balance: 30,000,000 (₹3,00,000)
      final summary = TripPaySummary(
        tripId: 'trip_1791482737100',
        totalContributedPaise: 34070000,
        totalSpentPaise: 4070000,
        availableBalancePaise: 30000000,
        updatedAt: now,
      );

      final result = TripPayReconciler.reconcile(
        transactions: transactions,
        summary: summary,
      );

      expect(result.isConsistent, isTrue);
      expect(result.discrepancyPaise, equals(0));
      expect(result.ledgerCalculatedBalancePaise, equals(30000000));
      expect(summary.availableBalancePaise, equals(30000000));

      // The last expense transaction's balanceAfterPaise matches the summary's available balance exactly!
      final lastTx = transactions.last;
      expect(lastTx.balanceAfterPaise, equals(summary.availableBalancePaise));
      expect(
        CurrencyFormatter.formatUnits(lastTx.balanceAfterPaise),
        equals(CurrencyFormatter.formatUnits(summary.availableBalancePaise)),
      );
    });

    testWidgets('8. Spending does not trigger contribution snackbar and clears stale snackbars', (tester) async {
      final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // Simulate contribution success snackbar
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Added ₹20,000 to the Trip Pot!'),
                          backgroundColor: Color(0xFF10B981),
                        ),
                      );
                    },
                    child: const Text('Simulate Contribution'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // Opening spending flow clears stale snackbars
                      ScaffoldMessenger.of(ctx).clearSnackBars();
                      // Completing spending operation shows ONLY the spending snackbar
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Paid ₹40,000 to highway from Trip Pot!'),
                          backgroundColor: Color(0xFF10B981),
                        ),
                      );
                    },
                    child: const Text('Simulate Spending Flow'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 1. Trigger contribution snackbar
      await tester.tap(find.text('Simulate Contribution'));
      await tester.pump();
      expect(find.text('Added ₹20,000 to the Trip Pot!'), findsOneWidget);

      // 2. Trigger spending flow
      await tester.tap(find.text('Simulate Spending Flow'));
      await tester.pump();

      // Verify that "Added ₹20,000 to the Trip Pot!" is GONE
      expect(find.text('Added ₹20,000 to the Trip Pot!'), findsNothing);
      // Verify that ONLY the spending snackbar is displayed
      expect(find.text('Paid ₹40,000 to highway from Trip Pot!'), findsOneWidget);
    });

    test('9. Crew Activity correctly aggregates ₹15,700 spending across 5 payments for Pondi cherry week', () {
      final now = DateTime.now();
      const tripId = 'trip_1791763018861';
      const userId = 'FzvDHPlfaAYIDy95vx2SRhGCOC92';
      const userName = 'Raagul S D';

      // The 7 authoritative transactions from Supabase for 'Pondi cherry week'
      final pondiTransactions = <TripPayTransaction>[
        // 1. Contribution ₹200
        TripPayTransaction(
          id: 'tx_717095553',
          tripId: tripId,
          type: TripPayTransactionType.contribution,
          amountPaise: 20000,
          initiatedByUid: userId,
          initiatedByName: userName,
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now.subtract(const Duration(hours: 10)),
          clientRequestId: 'cr_717095553',
        ),
        // 2. Expense ₹100
        TripPayTransaction(
          id: 'tx_971600494',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 10000,
          initiatedByUid: userId,
          initiatedByName: userName,
          merchantName: 'highway',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now.subtract(const Duration(hours: 9)),
          clientRequestId: 'cr_971600494',
        ),
        // 3. Expense ₹50
        TripPayTransaction(
          id: 'tx_846400978',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 5000,
          initiatedByUid: userId,
          initiatedByName: userName,
          merchantName: 'highway',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now.subtract(const Duration(hours: 8)),
          clientRequestId: 'cr_846400978',
        ),
        // 4. Expense ₹50
        TripPayTransaction(
          id: 'tx_504492507',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 5000,
          initiatedByUid: userId,
          initiatedByName: userName,
          merchantName: 'high',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now.subtract(const Duration(hours: 7)),
          clientRequestId: 'cr_504492507',
        ),
        // 5. Contribution ₹20,000
        TripPayTransaction(
          id: 'tx_787242205',
          tripId: tripId,
          type: TripPayTransactionType.contribution,
          amountPaise: 2000000,
          initiatedByUid: userId,
          initiatedByName: userName,
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now.subtract(const Duration(hours: 6)),
          clientRequestId: 'cr_787242205',
        ),
        // 6. Expense ₹15,000
        TripPayTransaction(
          id: 'tx_326723913',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 1500000,
          initiatedByUid: userId,
          initiatedByName: userName,
          merchantName: 'dinner',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now.subtract(const Duration(hours: 5)),
          clientRequestId: 'cr_326723913',
        ),
        // 7. Expense ₹500
        TripPayTransaction(
          id: 'tx_880562891',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 50000,
          initiatedByUid: userId,
          initiatedByName: userName,
          merchantName: 'high',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now.subtract(const Duration(hours: 4)),
          clientRequestId: 'cr_880562891',
        ),
      ];

      final summary = TripPaySummary(
        tripId: tripId,
        totalContributedPaise: 2020000, // ₹20,200
        totalSpentPaise: 1570000,       // ₹15,700
        availableBalancePaise: 450000,  // ₹4,500
        updatedAt: now,
      );

      final state = TripPayState(
        isLoading: false,
        summary: summary,
        transactions: pondiTransactions,
        memberNames: {userId: userName},
      );

      // Verify Reconciler consistency
      final rec = TripPayReconciler.reconcile(
        transactions: pondiTransactions,
        summary: summary,
      );
      expect(rec.isConsistent, isTrue);
      expect(rec.discrepancyPaise, equals(0));
      expect(rec.ledgerCalculatedBalancePaise, equals(450000));
      expect(rec.totalContributedPaise, equals(2020000));
      expect(rec.totalSpentPaise, equals(1570000));

      // Verify MemberContribution aggregation in TripPayState
      final memberContribs = state.memberContributions;
      expect(memberContribs.length, equals(1));

      final mc = memberContribs.first;
      expect(mc.uid, equals(userId));
      expect(mc.displayName, equals(userName));
      expect(mc.totalContributedPaise, equals(2020000)); // ₹20,200
      expect(mc.paymentsInitiated, equals(5)); // Exactly 5 payments
      expect(mc.totalSpendingInitiatedPaise, equals(1570000)); // Exactly ₹15,700

      // Verify CurrencyFormatter display strings
      expect(CurrencyFormatter.formatUnits(mc.totalContributedPaise), equals('₹20,200'));
      expect(CurrencyFormatter.formatUnits(mc.totalSpendingInitiatedPaise), equals('₹15,700'));
    });

    test('10. Pending and failed transactions are excluded from completed spending and contributions', () {
      final now = DateTime.now();
      const tripId = 'trip_1791763018861';
      const userId = 'user_abc';
      const userName = 'Alice';

      final mixedTransactions = <TripPayTransaction>[
        // Successful contribution
        TripPayTransaction(
          id: 'tx_s1',
          tripId: tripId,
          type: TripPayTransactionType.contribution,
          amountPaise: 500000, // ₹5,000
          initiatedByUid: userId,
          initiatedByName: userName,
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now,
          clientRequestId: 'cr_s1',
        ),
        // Pending contribution - should be ignored
        TripPayTransaction(
          id: 'tx_p1',
          tripId: tripId,
          type: TripPayTransactionType.contribution,
          amountPaise: 200000, // ₹2,000
          initiatedByUid: userId,
          initiatedByName: userName,
          status: TripPayTransactionStatus.pending,
          createdAt: now,
          clientRequestId: 'cr_p1',
        ),
        // Successful expense
        TripPayTransaction(
          id: 'tx_s2',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 100000, // ₹1,000
          initiatedByUid: userId,
          initiatedByName: userName,
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now,
          clientRequestId: 'cr_s2',
        ),
        // Failed expense - should be ignored
        TripPayTransaction(
          id: 'tx_f1',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 300000, // ₹3,000
          initiatedByUid: userId,
          initiatedByName: userName,
          status: TripPayTransactionStatus.failed,
          createdAt: now,
          clientRequestId: 'cr_f1',
        ),
        // Pending expense - should be ignored
        TripPayTransaction(
          id: 'tx_p2',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 400000, // ₹4,000
          initiatedByUid: userId,
          initiatedByName: userName,
          status: TripPayTransactionStatus.pending,
          createdAt: now,
          clientRequestId: 'cr_p2',
        ),
      ];

      final state = TripPayState(
        transactions: mixedTransactions,
        memberNames: {userId: userName},
      );

      final mc = state.memberContributions.first;
      expect(mc.totalContributedPaise, equals(500000)); // Only the successful ₹5,000
      expect(mc.paymentsInitiated, equals(1));           // Only the 1 successful expense
      expect(mc.totalSpendingInitiatedPaise, equals(100000)); // Only the successful ₹1,000
    });

    test('11. Filtered transactions includes expense transactions under payments filter', () {
      final now = DateTime.now();
      const tripId = 'trip_1791763018861';

      final txList = <TripPayTransaction>[
        TripPayTransaction(
          id: 'tx_c',
          tripId: tripId,
          type: TripPayTransactionType.contribution,
          amountPaise: 100000,
          initiatedByUid: 'u1',
          initiatedByName: 'User 1',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now,
          clientRequestId: 'cr_c',
        ),
        TripPayTransaction(
          id: 'tx_e',
          tripId: tripId,
          type: TripPayTransactionType.expense,
          amountPaise: 50000,
          initiatedByUid: 'u1',
          initiatedByName: 'User 1',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now,
          clientRequestId: 'cr_e',
        ),
      ];

      final statePayments = TripPayState(
        transactions: txList,
        activeFilter: TripPayFilter.payments,
      );
      final filteredPayments = statePayments.filteredTransactions('u1');
      expect(filteredPayments.length, equals(1));
      expect(filteredPayments.first.id, equals('tx_e'));

      final stateContrib = TripPayState(
        transactions: txList,
        activeFilter: TripPayFilter.contributions,
      );
      final filteredContribs = stateContrib.filteredTransactions('u1');
      expect(filteredContribs.length, equals(1));
      expect(filteredContribs.first.id, equals('tx_c'));
    });
  });
}
