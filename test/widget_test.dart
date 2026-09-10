import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/app/app.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/core/widgets/app_loading_indicator.dart';

void main() {
  group('Phase 0 - TripCrew App Shell & Navigation Tests', () {
    testWidgets('App renders Home screen with branding and navigation bar',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: TripCrewApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify branding text
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text(AppConstants.appTagline), findsOneWidget);

      // Verify Home content sections
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Create Trip'), findsOneWidget);
      expect(find.text('Join Trip'), findsOneWidget);
      expect(find.text('Active Trip'), findsOneWidget);
      expect(find.text('Upcoming Trips'), findsOneWidget);

      // Verify bottom navigation bar destinations
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('Navigation bar switches between Home, Trips, and Profile tabs',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: TripCrewApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Trips tab
      await tester.tap(find.text('Trips'));
      await tester.pumpAndSettle();

      // Verify Trips screen content
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // Navigate to Profile tab
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      // Verify Profile screen content
      expect(find.text('User'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Memories'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);

      // Navigate back to Home tab
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.text(AppConstants.appName), findsOneWidget);
    });
  });

  group('Phase 0 - Core Reusable Widgets Tests', () {
    testWidgets('AppLoadingIndicator renders with custom message',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppLoadingIndicator(message: 'Loading crew trips...'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading crew trips...'), findsOneWidget);
    });

    testWidgets('AppEmptyState renders title, message, and invokes action',
        (WidgetTester tester) async {
      var actionTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              icon: Icons.luggage_outlined,
              title: 'No Trips Found',
              message: 'Get started by creating a new trip.',
              actionLabel: 'Create Now',
              onActionPressed: () {
                actionTriggered = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('No Trips Found'), findsOneWidget);
      expect(find.text('Get started by creating a new trip.'), findsOneWidget);
      expect(find.text('Create Now'), findsOneWidget);

      await tester.tap(find.text('Create Now'));
      await tester.pump();

      expect(actionTriggered, isTrue);
    });

    testWidgets('AppErrorState renders message and triggers retry callback',
        (WidgetTester tester) async {
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorState(
              title: 'Connection Error',
              message: 'Please check your internet connection.',
              onRetry: () {
                retried = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Connection Error'), findsOneWidget);
      expect(find.text('Please check your internet connection.'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pump();

      expect(retried, isTrue);
    });
  });
}
