import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/trip_pay/models/settlement_model.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_summary.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/services/trip_settlement_service.dart';

void main() {
  group('TripSettlementService', () {
    late TripSettlementService service;

    setUp(() {
      service = TripSettlementService();
    });

    test('calculateMemberBalances calculates fair shares and net positions', () {
      final memberNames = {
        'user_1': 'Alice',
        'user_2': 'Bob',
        'user_3': 'Charlie',
      };

      final transactions = [
        // Alice contributed 3000 rupees (300000 paise)
        TripPayTransaction(
          id: 'tx1',
          tripId: 'trip_1',
          type: TripPayTransactionType.contribution,
          amountPaise: 300000,
          initiatedByUid: 'user_1',
          initiatedByName: 'Alice',
          createdAt: DateTime.now(),
          clientRequestId: 'req1',
        ),
        // Bob contributed 1500 rupees (150000 paise)
        TripPayTransaction(
          id: 'tx2',
          tripId: 'trip_1',
          type: TripPayTransactionType.contribution,
          amountPaise: 150000,
          initiatedByUid: 'user_2',
          initiatedByName: 'Bob',
          createdAt: DateTime.now(),
          clientRequestId: 'req2',
        ),
        // Charlie contributed 0 rupees
        // Total spent: 3000 rupees (300000 paise)
        TripPayTransaction(
          id: 'tx3',
          tripId: 'trip_1',
          type: TripPayTransactionType.expense,
          amountPaise: 300000,
          initiatedByUid: 'user_1',
          initiatedByName: 'Alice',
          createdAt: DateTime.now(),
          clientRequestId: 'req3',
        ),
      ];

      // Total spent = 300000 paise. 3 members -> Fair share = 100000 paise each (1000 rupees).
      final balances = service.calculateMemberBalances(
        memberNames: memberNames,
        transactions: transactions,
        totalSpentPaise: 300000,
      );

      expect(balances.length, equals(3));

      final alice = balances.firstWhere((b) => b.uid == 'user_1');
      final bob = balances.firstWhere((b) => b.uid == 'user_2');
      final charlie = balances.firstWhere((b) => b.uid == 'user_3');

      expect(alice.totalContributedPaise, equals(300000));
      expect(alice.fairSharePaise, equals(100000));
      expect(alice.netBalancePaise, equals(200000)); // +2000 rupees (gets refund/paid)

      expect(bob.totalContributedPaise, equals(150000));
      expect(bob.fairSharePaise, equals(100000));
      expect(bob.netBalancePaise, equals(50000)); // +500 rupees (gets refund/paid)

      expect(charlie.totalContributedPaise, equals(0));
      expect(charlie.fairSharePaise, equals(100000));
      expect(charlie.netBalancePaise, equals(-100000)); // -1000 rupees (owes payment)
    });

    test('calculateTransfers simplifies debt cleanly ("Who Pays Whom")', () {
      final memberBalances = [
        const MemberBalance(
          uid: 'user_1',
          displayName: 'Alice',
          totalContributedPaise: 300000,
          fairSharePaise: 100000,
        ), // net +200000
        const MemberBalance(
          uid: 'user_2',
          displayName: 'Bob',
          totalContributedPaise: 150000,
          fairSharePaise: 100000,
        ), // net +50000
        const MemberBalance(
          uid: 'user_3',
          displayName: 'Charlie',
          totalContributedPaise: 0,
          fairSharePaise: 250000,
        ), // net -250000
      ];

      final transfers = service.calculateTransfers(
        memberBalances: memberBalances,
        remainingPotPaise: 0,
      );

      // Charlie owes 250000: pays 200000 to Alice, and 50000 to Bob
      expect(transfers.length, equals(2));

      final charlieToAlice = transfers.firstWhere(
        (t) => t.fromUid == 'user_3' && t.toUid == 'user_1',
      );
      expect(charlieToAlice.amountPaise, equals(200000));
      expect(charlieToAlice.type, equals('peer_to_peer'));

      final charlieToBob = transfers.firstWhere(
        (t) => t.fromUid == 'user_3' && t.toUid == 'user_2',
      );
      expect(charlieToBob.amountPaise, equals(50000));
      expect(charlieToBob.type, equals('peer_to_peer'));
    });

    test('calculateTransfers handles pot refund for remaining balance', () {
      final memberBalances = [
        const MemberBalance(
          uid: 'user_1',
          displayName: 'Alice',
          totalContributedPaise: 200000,
          fairSharePaise: 100000,
        ),
        const MemberBalance(
          uid: 'user_2',
          displayName: 'Bob',
          totalContributedPaise: 200000,
          fairSharePaise: 100000,
        ),
      ];

      // Remaining pot = 200000 paise (2000 rupees)
      final transfers = service.calculateTransfers(
        memberBalances: memberBalances,
        remainingPotPaise: 200000,
      );

      // Both contributed equally -> pot refund 100000 each
      final potRefunds = transfers.where((t) => t.type == 'pot_refund').toList();
      expect(potRefunds.length, equals(2));
      expect(potRefunds[0].amountPaise, equals(100000));
      expect(potRefunds[1].amountPaise, equals(100000));
    });

    test('buildSettlementPlan creates complete plan object', () {
      final summary = TripPaySummary(
        tripId: 'trip_100',
        totalContributedPaise: 450000,
        totalSpentPaise: 300000,
        availableBalancePaise: 150000,
        updatedAt: DateTime.now(),
      );

      final plan = service.buildSettlementPlan(
        tripId: 'trip_100',
        memberNames: {'user_1': 'Alice', 'user_2': 'Bob'},
        transactions: [],
        summary: summary,
      );

      expect(plan.tripId, equals('trip_100'));
      expect(plan.totalContributedPaise, equals(450000));
      expect(plan.totalSpentPaise, equals(300000));
      expect(plan.remainingPotPaise, equals(150000));
      expect(plan.isSettled, isFalse);
    });
  });
}
