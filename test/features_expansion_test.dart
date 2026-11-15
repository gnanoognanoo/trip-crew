import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/expenses/models/expense_model.dart';
import 'package:tripcrew/features/expenses/utils/settlement_calculator.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/checklist/models/checklist_item.dart';

void main() {
  group('Trip Features Expansion Unit Tests', () {
    final now = DateTime.now();

    test('TripModel copyWith preserves and updates lifecycle fields', () {
      final trip = TripModel(
        id: 'trip_100',
        ownerId: 'user_1',
        name: 'Goa Holiday',
        startingPlace: 'Mumbai',
        destination: 'Goa',
        startDate: now,
        endDate: now.add(const Duration(days: 4)),
        tripType: 'Vacation',
        budget: 25000,
        currency: 'INR (₹)',
        inviteCode: 'TRIP-GOA01',
        status: 'active',
        memberCount: 3,
        totalSpendingPaise: 500000,
        createdAt: now,
        updatedAt: now,
      );

      final updated = trip.copyWith(
        name: 'Goa Sun & Sand',
        budget: 35000,
        status: 'archived',
      );

      expect(updated.name, 'Goa Sun & Sand');
      expect(updated.budget, 35000);
      expect(updated.status, 'archived');
      expect(updated.destination, 'Goa');
      expect(updated.id, 'trip_100');
    });

    test('ExpenseModel copyWith and fromMap support both camelCase and snake_case', () {
      final mapFromSupabase = {
        'id': 'exp_1',
        'title': 'Dinner at Beach Shack',
        'amount_paise': 240000,
        'category': 'Food',
        'paid_by_user_id': 'user_a',
        'paid_by_name': 'Alice',
        'participantUids': ['user_a', 'user_b'],
        'split_type': 'equal',
        'created_by': 'user_a',
        'created_at': '2026-10-17T12:00:00Z',
      };

      final expense = ExpenseModel.fromMap(mapFromSupabase, 'exp_1');
      expect(expense.id, 'exp_1');
      expect(expense.description, 'Dinner at Beach Shack');
      expect(expense.amountPaise, 240000);
      expect(expense.paidByUid, 'user_a');
      expect(expense.paidByName, 'Alice');
      expect(expense.participantUids, ['user_a', 'user_b']);
      expect(expense.createdAt.year, 2026);

      final modified = expense.copyWith(
        amountPaise: 300000,
        description: 'Updated Dinner',
      );
      expect(modified.amountPaise, 300000);
      expect(modified.description, 'Updated Dinner');
      expect(modified.category, 'Food');
    });

    test('ItineraryItem fromMap handles native columns and JSON notes fallback', () {
      // Scenario A: Native columns exist
      final nativeMap = {
        'title': 'Scuba Diving',
        'location': 'Grand Island',
        'day_number': 3,
        'time': '09:00 AM',
        'is_visited': false,
        'order': 1,
      };
      final itemA = ItineraryItem.fromMap(nativeMap, 'itin_1');
      expect(itemA.dayNumber, 3);
      expect(itemA.time, '09:00 AM');
      expect(itemA.title, 'Scuba Diving');

      // Scenario B: Native columns absent, metadata encoded in notes JSON
      final notesFallbackMap = {
        'title': 'Sunset Cruise',
        'location': 'Mandovi River',
        'notes': jsonEncode({
          'dayNumber': 2,
          'time': '05:30 PM',
          'notes': 'Booked on lower deck',
        }),
        'is_visited': true,
        'order': 2,
      };
      final itemB = ItineraryItem.fromMap(notesFallbackMap, 'itin_2');
      expect(itemB.dayNumber, 2);
      expect(itemB.time, '05:30 PM');
      expect(itemB.notes, 'Booked on lower deck');
      expect(itemB.isVisited, true);

      // Scenario C: copyWith updates item cleanly
      final itemC = itemB.copyWith(
        title: 'Sunset Cruise VIP',
        dayNumber: 4,
      );
      expect(itemC.title, 'Sunset Cruise VIP');
      expect(itemC.dayNumber, 4);
      expect(itemC.time, '05:30 PM');
    });

    test('ChecklistItem fromMap and copyWith preserve category and assignment', () {
      final checklistMap = {
        'title': 'Sunscreen SPF 50',
        'category': 'Toiletries',
        'is_checked': false,
        'is_shared': true,
        'assigned_to_user_id': 'user_b',
        'assigned_to_name': 'Bob',
      };
      final item = ChecklistItem.fromMap(checklistMap, 'chk_1');
      expect(item.title, 'Sunscreen SPF 50');
      expect(item.category, 'Toiletries');
      expect(item.isShared, true);
      expect(item.assignedToMemberName, 'Bob');

      final updatedItem = item.copyWith(
        isCompleted: true,
        category: 'Essentials',
      );
      expect(updatedItem.isCompleted, true);
      expect(updatedItem.category, 'Essentials');
      expect(updatedItem.assignedToUid, 'user_b');
    });

    test('SettlementCalculator resolves debts when an offsetting settlement expense is recorded', () {
      // Alice paid ₹2000 for Alice and Bob (equal split: ₹1000 each)
      final initialExpense = ExpenseModel(
        id: 'exp_1',
        description: 'Hotel stay',
        amountPaise: 200000,
        category: 'Stay',
        paidByUid: 'alice',
        paidByName: 'Alice',
        participantUids: ['alice', 'bob'],
        splitType: 'equal',
        createdBy: 'alice',
        createdAt: now,
      );

      final members = {
        'alice': 'Alice',
        'bob': 'Bob',
      };

      // Before settlement: Bob owes Alice ₹1000
      final initialSettlements = SettlementCalculator.calculateSettlements(
        expenses: [initialExpense],
        memberNames: members,
      );

      expect(initialSettlements.length, 1);
      expect(initialSettlements.first.fromUid, 'bob');
      expect(initialSettlements.first.toUid, 'alice');
      expect(initialSettlements.first.amountPaise, 100000);

      // Bob settles up: Bob pays Alice ₹1000 directly
      final settlementExpense = ExpenseModel(
        id: 'settle_1',
        description: 'Direct Settlement: Bob -> Alice',
        amountPaise: 100000,
        category: 'Settlement',
        paidByUid: 'bob',
        paidByName: 'Bob',
        participantUids: ['alice'],
        splitType: 'equal',
        createdBy: 'bob',
        createdAt: now.add(const Duration(hours: 1)),
      );

      // After settlement: all debts are balanced (0 settlements needed)
      final postSettlements = SettlementCalculator.calculateSettlements(
        expenses: [initialExpense, settlementExpense],
        memberNames: members,
      );

      expect(postSettlements.isEmpty, true);
    });
  });
}
