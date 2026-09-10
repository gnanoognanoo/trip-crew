import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/app/app.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/expenses/models/expense_model.dart';
import 'package:tripcrew/features/expenses/utils/settlement_calculator.dart';

void main() {
  group('TripCrew Comprehensive Automated Tests', () {
    testWidgets(
      'App renders Home Dashboard with greeting, active trip, and hub modules',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const ProviderScope(child: TripCrewApp()));
        await tester.pumpAndSettle();

        // Check Home dashboard greeting and active trip
        expect(find.text('Good morning,'), findsOneWidget);
        expect(find.text('Goa Trip'), findsOneWidget);
        expect(find.text('Itinerary'), findsOneWidget);
        expect(find.text('Expenses'), findsOneWidget);
        expect(find.text('Map'), findsOneWidget);
        expect(find.text('Packing'), findsOneWidget);
        expect(find.text('Memories'), findsOneWidget);
        expect(find.text('Crew'), findsOneWidget);

        // Check 5-tab NavigationBar destinations
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Trips'), findsOneWidget);
        expect(find.text('Wallet'), findsOneWidget);
        expect(find.text('Explore'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
      },
    );

    testWidgets(
      'Navigation bar switches across Trips, Wallet, Explore, and Profile',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const ProviderScope(child: TripCrewApp()));
        await tester.pumpAndSettle();

        // 1. Navigate to Trips
        await tester.tap(find.text('Trips'));
        await tester.pumpAndSettle();
        expect(find.text('Create Trip'), findsOneWidget);
        expect(find.text('Join Trip'), findsOneWidget);

        // 2. Navigate to Wallet
        await tester.tap(find.text('Wallet'));
        await tester.pumpAndSettle();
        expect(find.text('Total Balance'), findsOneWidget);
        expect(find.text('Send'), findsOneWidget);
        expect(find.text('Request'), findsOneWidget);

        // 3. Navigate to Explore
        await tester.tap(find.text('Explore'));
        await tester.pumpAndSettle();
        expect(find.text('Explore Nearby'), findsOneWidget);

        // 4. Navigate to Profile
        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();
        expect(find.text('Collect moments, not things. ✨'), findsOneWidget);
        expect(find.text('My Trips'), findsOneWidget);
        expect(find.text('My Wallet'), findsOneWidget);
        expect(find.text('Logout'), findsOneWidget);
      },
    );

    test('Currency and decimal-safe paise conversions', () {
      expect(CurrencyFormatter.toSmallestUnit(1200.50), equals(120050));
      expect(CurrencyFormatter.fromSmallestUnit(120050), equals(1200.50));
      expect(CurrencyFormatter.format(18450), contains('18,450'));
    });

    test('Settlement calculator minimizes peer-to-peer transactions', () {
      final expenses = [
        ExpenseModel(
          id: 'e1',
          description: 'Goa Villa',
          amountPaise: 120000, // ₹1,200
          category: 'Stay',
          paidByUid: 'user_a',
          paidByName: 'Kowshik',
          participantUids: ['user_a', 'user_b', 'user_c', 'user_d'],
          createdBy: 'user_a',
          createdAt: DateTime.now(),
        ),
      ];

      final memberNames = {
        'user_a': 'Kowshik',
        'user_b': 'Arun',
        'user_c': 'Rahul',
        'user_d': 'Praveen',
      };

      final settlements = SettlementCalculator.calculateSettlements(
        expenses: expenses,
        memberNames: memberNames,
      );

      // ₹1200 split equally 4 ways = ₹300 per member.
      // Kowshik is owed ₹900; Arun, Rahul, Praveen each owe ₹300.
      expect(settlements.length, equals(3));
      for (final s in settlements) {
        expect(s.toName, equals('Kowshik'));
        expect(s.amountPaise, equals(30000)); // ₹300
      }
    });
  });
}
