import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/trip_pay/presentation/add_contribution_screen.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

void main() {
  testWidgets('AddContributionScreen allows erasing suggested amount and entering 500', (
    WidgetTester tester,
  ) async {
    final testTrip = TripModel(
      id: 'trip_100',
      ownerId: 'user_1',
      name: 'Goa Weekend',
      startingPlace: 'Bengaluru',
      destination: 'Goa',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 5),
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
      inviteCode: 'GOA100',
      memberCount: 1,
      budget: 2000,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeTripProvider.overrideWith((ref) => testTrip),
        ],
        child: const MaterialApp(
          home: AddContributionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Initial suggested amount should be 2000
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    final textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.controller?.text, '2000');

    // 2. Erase the text field to empty
    await tester.enterText(textFieldFinder, '');
    await tester.pumpAndSettle();

    // 3. Crucial check: Controller must remain empty and NOT get overridden by build loop
    final clearedField = tester.widget<TextField>(textFieldFinder);
    expect(clearedField.controller?.text, '');
    expect(find.text('Enter Contribution Amount'), findsOneWidget);

    // 4. Enter 500 into the cleared field
    await tester.enterText(textFieldFinder, '500');
    await tester.pumpAndSettle();

    // 5. Verify the amount is now 500
    final updatedField = tester.widget<TextField>(textFieldFinder);
    expect(updatedField.controller?.text, '500');

    // 6. Verify total payment calculation: ₹500 + 1% (₹5) = ₹505
    expect(find.text('₹500'), findsWidgets);
    expect(find.text('₹5'), findsOneWidget);
    expect(find.text('₹505'), findsWidgets);

    // 7. Verify the clear icon button clears the field in one tap
    final clearButton = find.byTooltip('Clear amount');
    expect(clearButton, findsOneWidget);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    final afterClearField = tester.widget<TextField>(textFieldFinder);
    expect(afterClearField.controller?.text, '');

    // 8. Verify tapping the ₹500 chip populates 500
    final chip500 = find.widgetWithText(ActionChip, '₹500');
    expect(chip500, findsOneWidget);
    await tester.tap(chip500);
    await tester.pumpAndSettle();

    final afterChipField = tester.widget<TextField>(textFieldFinder);
    expect(afterChipField.controller?.text, '500');
    expect(find.text('₹505'), findsWidgets);
  });
}
