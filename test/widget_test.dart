import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tripcrew/app/app.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/cloudinary_service.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/features/auth/models/user_profile.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/expenses/models/expense_model.dart';
import 'package:tripcrew/features/expenses/utils/settlement_calculator.dart';
import 'package:tripcrew/features/memories/models/memory_model.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) _handler;
  MockHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

class FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return AuthState(
      isLoading: false,
      user: UserProfile(
        uid: 'test_uid_1',
        name: 'Alex Rivera',
        email: 'alex@tripcrew.app',
        tripCount: 3,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }
}

class FakeTripsNotifier extends TripsNotifier {
  @override
  TripsState build() {
    final now = DateTime.now();
    final testTrip = TripModel(
      id: 'test_trip_1',
      ownerId: 'test_uid_1',
      name: 'Mountain Expedition',
      startingPlace: 'Base Camp',
      destination: 'Summit Ridge',
      startDate: now.add(const Duration(days: 2)),
      endDate: now.add(const Duration(days: 5)),
      tripType: 'Trek',
      budget: 12000,
      currency: 'INR (₹)',
      inviteCode: 'TRIP-MNT01',
      status: 'active',
      memberCount: 4,
      totalSpendingPaise: 480000,
      createdAt: now,
      updatedAt: now,
    );
    return TripsState(
      isLoading: false,
      trips: [testTrip],
      activeTripId: testTrip.id,
    );
  }
}

void main() {
  group('TripCrew Comprehensive Automated Tests', () {
    testWidgets('Unauthenticated user lands on Welcome screen', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: TripCrewApp()));
      await tester.pumpAndSettle();

      expect(find.text('TripCrew'), findsOneWidget);
      expect(find.text('Travel Better Together'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets(
      'Authenticated user renders Home Dashboard with greeting, active trip, and hub modules',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(FakeAuthNotifier.new),
              tripsProvider.overrideWith(FakeTripsNotifier.new),
            ],
            child: const TripCrewApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Check Home dashboard greeting and active trip
        expect(find.text('Good morning,'), findsOneWidget);
        expect(find.text('Alex Rivera'), findsOneWidget);
        expect(find.text('Mountain Expedition'), findsOneWidget);
        expect(find.text('Itinerary'), findsOneWidget);
        expect(find.text('Expenses'), findsOneWidget);
        expect(find.text('Live Crew'), findsOneWidget);
        expect(find.text('Packing'), findsOneWidget);
        expect(find.text('Memories'), findsOneWidget);
        expect(find.text('Crew'), findsOneWidget);

        // Check 4-tab NavigationBar destinations (Wallet removed from global nav)
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Trips'), findsOneWidget);
        expect(find.text('Explore'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('Wallet'), findsNothing);

        // Check TripCrew Pay quick action on Home
        expect(find.text('TripCrew Pay'), findsOneWidget);
        expect(find.text('Open Trip Pot'), findsOneWidget);
      },
    );

    testWidgets('Navigation bar switches across Trips, Explore, and Profile', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(FakeAuthNotifier.new),
            tripsProvider.overrideWith(FakeTripsNotifier.new),
          ],
          child: const TripCrewApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Navigate to Trips
      await tester.tap(find.text('Trips'));
      await tester.pumpAndSettle();
      expect(find.text('Create Trip'), findsOneWidget);
      expect(find.text('Join Trip'), findsOneWidget);

      // 2. Navigate to Explore
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      expect(find.text('Explore Nearby'), findsOneWidget);

      // 3. Navigate to Profile
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Alex Rivera'), findsOneWidget);
      expect(find.text('My Trips'), findsOneWidget);
      expect(find.text('My Trip Payments'), findsOneWidget);
      expect(find.text('My Wallet'), findsNothing);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('TripCrew Pay opens from Home Quick Action and Trip Workspace', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(FakeAuthNotifier.new),
            tripsProvider.overrideWith(FakeTripsNotifier.new),
          ],
          child: const TripCrewApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Home Quick Action opens TripCrew Pay
      expect(find.text('Open Trip Pot'), findsOneWidget);
      await tester.tap(find.text('Open Trip Pot'));
      await tester.pumpAndSettle();

      // Dismiss first-time explanation if displayed
      if (find.text('Continue').evaluate().isNotEmpty) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }

      expect(find.text('SHARED TRIP POT'), findsOneWidget);
      expect(find.text('Add Your Share'), findsOneWidget);
      expect(find.text('Pay from Trip Pot'), findsOneWidget);
      expect(find.text('Transaction History'), findsOneWidget);

      // Pop back to Home
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // 2. Open Workspace via Active Trip Card and verify Trip Workspace modules
      await tester.tap(find.text('Open Hub'));
      await tester.pumpAndSettle();

      expect(find.text('Trip Workspace Modules'), findsOneWidget);
      expect(find.text('Smart Itinerary'), findsOneWidget);
      expect(find.text('Crew & Members'), findsOneWidget);
      expect(find.text('TripCrew Pay'), findsOneWidget);
      expect(find.text('Shared Expenses & Settlements'), findsOneWidget);
      expect(find.text('Packing Checklist'), findsOneWidget);
      expect(find.text('Live Crew Location'), findsOneWidget);
      expect(find.text('Trip Pulse'), findsOneWidget);
      expect(find.text('Shared Memories Gallery'), findsOneWidget);
      expect(find.text('Map — Coming Soon'), findsOneWidget);

      // 3. Open TripCrew Pay from Workspace
      await tester.tap(find.text('TripCrew Pay'));
      await tester.pumpAndSettle();
      expect(find.text('SHARED TRIP POT'), findsOneWidget);
    });

    test('Currency and decimal-safe paise conversions', () {
      expect(CurrencyFormatter.toSmallestUnit(1200.50), equals(120050));
      expect(CurrencyFormatter.fromSmallestUnit(120050), equals(1200.50));
      expect(CurrencyFormatter.format(18450), contains('18,450'));
    });

    test('Settlement calculator minimizes peer-to-peer transactions', () {
      final expenses = [
        ExpenseModel(
          id: 'e1',
          description: 'Mountain Lodge',
          amountPaise: 120000, // ₹1,200
          category: 'Stay',
          paidByUid: 'user_a',
          paidByName: 'Alex',
          participantUids: ['user_a', 'user_b', 'user_c', 'user_d'],
          createdBy: 'user_a',
          createdAt: DateTime.now(),
        ),
      ];

      final memberNames = {
        'user_a': 'Alex',
        'user_b': 'Taylor',
        'user_c': 'Jordan',
        'user_d': 'Sam',
      };

      final settlements = SettlementCalculator.calculateSettlements(
        expenses: expenses,
        memberNames: memberNames,
      );

      // ₹1200 split equally 4 ways = ₹300 per member.
      // Alex is owed ₹900; Taylor, Jordan, Sam each owe ₹300.
      expect(settlements.length, equals(3));
      for (final s in settlements) {
        expect(s.toName, equals('Alex'));
        expect(s.amountPaise, equals(30000)); // ₹300
      }
    });

    test('MemoryModel preserves Cloudinary metadata fields correctly', () {
      final now = DateTime.now();
      final memory = MemoryModel(
        id: 'mem_123',
        tripId: 'trip_abc',
        uploaderId: 'user_xyz',
        photographerName: 'Alex Rivera',
        imageUrl:
            'https://res.cloudinary.com/tripcrew/image/upload/v1234/test.jpg',
        publicId: 'tripcrew/memories/trip_abc/test',
        dayIndex: 2,
        caption: 'Sunset at Summit',
        createdAt: now,
        capturedAt: now,
      );

      final map = memory.toMap();
      expect(map['tripId'], equals('trip_abc'));
      expect(map['uploaderId'], equals('user_xyz'));
      expect(
        map['imageUrl'],
        equals(
          'https://res.cloudinary.com/tripcrew/image/upload/v1234/test.jpg',
        ),
      );
      expect(map['publicId'], equals('tripcrew/memories/trip_abc/test'));
      expect(map['dayIndex'], equals(2));
      expect(map['caption'], equals('Sunset at Summit'));

      // Test deserialization
      final restored = MemoryModel.fromMap(map, 'mem_123');
      expect(restored.imageUrl, equals(memory.imageUrl));
      expect(restored.publicId, equals(memory.publicId));
      expect(restored.dayIndex, equals(2));
      expect(restored.dayNumber, equals(2));
      expect(restored.mediaUrl, equals(memory.imageUrl));
      expect(restored.uploaderId, equals('user_xyz'));
    });

    test('CloudinaryUploadResult parses JSON correctly', () {
      final json = {
        'secure_url': 'https://res.cloudinary.com/demo/image/upload/sample.jpg',
        'public_id': 'sample_id',
        'format': 'jpg',
        'bytes': 1048576,
        'width': 1920,
        'height': 1080,
        'created_at': '2026-09-10T12:00:00Z',
      };

      final result = CloudinaryUploadResult.fromJson(json);
      expect(
        result.secureUrl,
        equals('https://res.cloudinary.com/demo/image/upload/sample.jpg'),
      );
      expect(result.publicId, equals('sample_id'));
      expect(result.format, equals('jpg'));
      expect(result.bytes, equals(1048576));
      expect(result.width, equals(1920));
      expect(result.height, equals(1080));
    });

    test('CloudinaryUploadResult enforces HTTPS when HTTP is returned', () {
      final json = {
        'secure_url': 'http://res.cloudinary.com/demo/image/upload/sample.jpg',
        'public_id': 'sample_insecure_id',
      };
      final result = CloudinaryUploadResult.fromJson(json);
      expect(result.secureUrl, startsWith('https://'));
    });

    test(
      'MemoryModel supports Firestore serverTimestamp and Timestamp parsing',
      () {
        final memory = MemoryModel(
          id: 'mem_test',
          tripId: 'trip_1',
          uploaderId: 'user_1',
          imageUrl: 'https://res.cloudinary.com/test.jpg',
          createdAt: DateTime(2026, 9, 10),
        );

        final firestoreMap = memory.toFirestoreMap(useServerTimestamp: true);
        expect(firestoreMap['createdAt'], isA<FieldValue>());

        // Test parsing with Firestore Timestamp
        final snapshotMap = {
          'tripId': 'trip_1',
          'uploaderId': 'user_1',
          'imageUrl': 'https://res.cloudinary.com/test.jpg',
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 10, 15, 30)),
          'dayIndex': 3,
        };
        final parsed = MemoryModel.fromMap(snapshotMap, 'mem_test');
        expect(parsed.createdAt.year, equals(2026));
        expect(parsed.dayIndex, equals(3));
        expect(parsed.dayNumber, equals(3));
      },
    );

    test(
      'CloudinaryService validates file extensions and rejects invalid formats',
      () {
        // Valid formats
        expect(
          () => CloudinaryService.validateFile(
            filename: 'photo.jpg',
            byteLength: 1024,
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          returnsNormally,
        );
        expect(
          () => CloudinaryService.validateFile(
            filename: 'IMAGE.PNG',
            byteLength: 1024,
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          returnsNormally,
        );
        expect(
          () => CloudinaryService.validateFile(
            filename: 'picture.webp',
            byteLength: 1024,
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          returnsNormally,
        );

        // Invalid formats
        expect(
          () => CloudinaryService.validateFile(
            filename: 'document.pdf',
            byteLength: 1024,
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          throwsA(isA<CloudinaryValidationException>()),
        );
        expect(
          () => CloudinaryService.validateFile(
            filename: 'animation.gif',
            byteLength: 1024,
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          throwsA(isA<CloudinaryValidationException>()),
        );
        expect(
          () => CloudinaryService.validateFile(
            filename: 'script.exe',
            byteLength: 1024,
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          throwsA(isA<CloudinaryValidationException>()),
        );
        expect(
          () => CloudinaryService.validateFile(
            filename: 'no_extension',
            byteLength: 1024,
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          throwsA(isA<CloudinaryValidationException>()),
        );
      },
    );

    test(
      'CloudinaryService validates size limits for avatars and trip memories',
      () {
        // Avatar size limit (5MB)
        expect(
          () => CloudinaryService.validateFile(
            filename: 'avatar.jpg',
            byteLength: 4 * 1024 * 1024, // 4MB
            maxSizeBytes: CloudinaryService.maxAvatarSizeBytes,
          ),
          returnsNormally,
        );
        expect(
          () => CloudinaryService.validateFile(
            filename: 'avatar.jpg',
            byteLength: 6 * 1024 * 1024, // 6MB
            maxSizeBytes: CloudinaryService.maxAvatarSizeBytes,
          ),
          throwsA(isA<CloudinaryValidationException>()),
        );

        // Memory size limit (10MB)
        expect(
          () => CloudinaryService.validateFile(
            filename: 'memory.jpg',
            byteLength: 9 * 1024 * 1024, // 9MB
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          returnsNormally,
        );
        expect(
          () => CloudinaryService.validateFile(
            filename: 'huge_memory.jpg',
            byteLength: 11 * 1024 * 1024, // 11MB
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          throwsA(isA<CloudinaryValidationException>()),
        );

        // Zero-byte file
        expect(
          () => CloudinaryService.validateFile(
            filename: 'empty.png',
            byteLength: 0,
            maxSizeBytes: CloudinaryService.maxMemorySizeBytes,
          ),
          throwsA(isA<CloudinaryValidationException>()),
        );
      },
    );

    test(
      'Trip membership and avatar authorization guard rejects empty UIDs',
      () async {
        expect(
          () => CloudinaryService.verifyAvatarAuthorization(''),
          throwsA(isA<CloudinaryAuthException>()),
        );
        expect(
          () async => CloudinaryService.verifyTripMemberAuthorization(
            tripId: 'trip_1',
            uid: '',
          ),
          throwsA(isA<CloudinaryAuthException>()),
        );
      },
    );

    test(
      'CloudinaryService handles mock failed HTTP uploads gracefully',
      () async {
        final mockClient = MockHttpClient((request) async {
          return http.Response('{"error":{"message":"Invalid preset"}}', 400);
        });

        expect(
          () => CloudinaryService.uploadAvatar(
            bytes: Uint8List.fromList([1, 2, 3]),
            filename: 'avatar.png',
            uid: 'user_test_1',
            client: mockClient,
          ),
          throwsA(isA<CloudinaryUploadException>()),
        );
      },
    );

    test(
      'CloudinaryService deleteAsset throws UnsupportedError to protect API secret',
      () {
        expect(
          () => CloudinaryService.deleteAsset('sample_public_id'),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    testWidgets(
      'AppErrorState renders title, message, and responds to retry button',
      (WidgetTester tester) async {
        bool retried = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppErrorState(
                title: 'Connection Lost',
                message: 'Check your internet connection and try again.',
                onRetry: () => retried = true,
              ),
            ),
          ),
        );

        expect(find.text('Connection Lost'), findsOneWidget);
        expect(
          find.text('Check your internet connection and try again.'),
          findsOneWidget,
        );
        expect(find.text('Try Again'), findsOneWidget);

        await tester.tap(find.text('Try Again'));
        expect(retried, isTrue);
      },
    );

    test('Media cleanup queue payload adheres to required schema', () {
      final now = DateTime.now();
      final cleanupPayload = {
        'publicId': 'tripcrew/memories/trip_1/user_1/m_123',
        'tripId': 'trip_1',
        'requestedBy': 'user_1',
        'createdAt': now.toIso8601String(),
        'status': 'pending',
        'imageUrl':
            'https://res.cloudinary.com/tripcrew/image/upload/v1/m_123.jpg',
      };

      expect(cleanupPayload['publicId'], isNotEmpty);
      expect(cleanupPayload['tripId'], equals('trip_1'));
      expect(cleanupPayload['requestedBy'], equals('user_1'));
      expect(cleanupPayload['status'], equals('pending'));
      expect(cleanupPayload['imageUrl'], startsWith('https://'));
    });

    test('AnalyticsService logs required events without throwing', () async {
      await expectLater(AnalyticsService.logSignUp(), completes);
      await expectLater(AnalyticsService.logLogin(), completes);
      await expectLater(
        AnalyticsService.logTripCreated('trip_1', 'Road Trip'),
        completes,
      );
      await expectLater(AnalyticsService.logTripJoined('trip_1'), completes);
      await expectLater(AnalyticsService.logInviteShared('trip_1'), completes);
      await expectLater(
        AnalyticsService.logExpenseAdded(
          'trip_1',
          category: 'Food',
          paymentSource: 'manual',
        ),
        completes,
      );
      await expectLater(
        AnalyticsService.logChecklistItemCompleted('trip_1'),
        completes,
      );
      await expectLater(
        AnalyticsService.logItineraryItemAdded('trip_1'),
        completes,
      );
      await expectLater(
        AnalyticsService.logMemoryUploaded('trip_1'),
        completes,
      );
      await expectLater(
        AnalyticsService.logPulseSent('trip_1', 'Coffee'),
        completes,
      );
      await expectLater(AnalyticsService.logRecapViewed('trip_1'), completes);
    });
  });
}
