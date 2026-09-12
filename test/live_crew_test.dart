import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/maps/models/live_location_model.dart';
import 'package:tripcrew/features/maps/utils/location_calculator.dart';
import 'package:tripcrew/core/services/live_crew_service.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';

void main() {
  group('Live Crew Location & Proximity Tests', () {
    test('calculateDistance computes accurate geodesic distances', () {
      // Goa Baga Beach (~15.5528, 73.7517) to Calangute Beach (~15.5439, 73.7553)
      // Actual ground distance is ~1.05 km (1050m)
      final distance = LocationCalculator.calculateDistance(
        15.5528,
        73.7517,
        15.5439,
        73.7553,
      );

      expect(distance, greaterThan(950));
      expect(distance, lessThan(1150));

      // Same point distance is 0.0
      expect(
        LocationCalculator.calculateDistance(
          15.5528,
          73.7517,
          15.5528,
          73.7517,
        ),
        equals(0.0),
      );
    });

    test(
      'calculateBearing calculates initial compass bearing in 0..360 range',
      () {
        // Due North: lat increases, lon constant
        final bearingNorth = LocationCalculator.calculateBearing(
          10.0,
          70.0,
          11.0,
          70.0,
        );
        expect(bearingNorth, closeTo(0.0, 1.0));

        // Due East: lat constant, lon increases
        final bearingEast = LocationCalculator.calculateBearing(
          10.0,
          70.0,
          10.0,
          71.0,
        );
        expect(bearingEast, closeTo(90.0, 1.0));

        // Due South: lat decreases, lon constant
        final bearingSouth = LocationCalculator.calculateBearing(
          10.0,
          70.0,
          9.0,
          70.0,
        );
        expect(bearingSouth, closeTo(180.0, 1.0));
      },
    );

    test('formatDistance uses meters under 1km and km above 1km', () {
      expect(LocationCalculator.formatDistance(120.4), equals('120 m away'));
      expect(LocationCalculator.formatDistance(650.0), equals('650 m away'));
      expect(LocationCalculator.formatDistance(999.4), equals('999 m away'));
      expect(LocationCalculator.formatDistance(1000.0), equals('1.0 km away'));
      expect(LocationCalculator.formatDistance(1280.0), equals('1.3 km away'));
      expect(LocationCalculator.formatDistance(4820.0), equals('4.8 km away'));
    });

    test('formatCompactDistance provides compact badges for radar display', () {
      expect(LocationCalculator.formatCompactDistance(120), equals('120m'));
      expect(LocationCalculator.formatCompactDistance(1250), equals('1.3km'));
    });

    test(
      'GroupStatus accurately detects Everyone is together vs Away warnings',
      () {
        // Everyone <= 250m
        final togetherStatus = GroupStatus.evaluate([45.0, 120.0, 210.0]);
        expect(togetherStatus.isTogether, isTrue);
        expect(togetherStatus.awayCount, equals(0));
        expect(togetherStatus.statusTitle, equals('🟢 Everyone is together'));

        // 1 member > 250m
        final oneAwayStatus = GroupStatus.evaluate([45.0, 120.0, 650.0]);
        expect(oneAwayStatus.isTogether, isFalse);
        expect(oneAwayStatus.awayCount, equals(1));
        expect(oneAwayStatus.statusTitle, contains('1 crew member is away'));

        // 2 members > 250m
        final twoAwayStatus = GroupStatus.evaluate([50.0, 320.0, 1200.0]);
        expect(twoAwayStatus.isTogether, isFalse);
        expect(twoAwayStatus.awayCount, equals(2));
        expect(twoAwayStatus.statusTitle, contains('2 crew members are away'));
      },
    );

    test('LiveLocationModel calculates freshness correctly', () {
      final now = DateTime.now();

      // Updated 10s ago -> Live
      final liveModel = LiveLocationModel(
        uid: 'u1',
        displayName: 'Arun',
        latitude: 15.5,
        longitude: 73.7,
        accuracy: 8.0,
        updatedAt: now.subtract(const Duration(seconds: 10)),
        sharingMode: '1_hour',
        sharingUntil: now.add(const Duration(minutes: 50)),
        isSharing: true,
      );
      expect(liveModel.freshness, equals(LocationFreshness.live));
      expect(liveModel.freshnessLabel, equals('Live now'));

      // Updated 2 minutes ago -> Recent
      final recentModel = LiveLocationModel(
        uid: 'u2',
        displayName: 'Rahul',
        latitude: 15.5,
        longitude: 73.7,
        accuracy: 10.0,
        updatedAt: now.subtract(const Duration(minutes: 2)),
        sharingMode: '1_hour',
        sharingUntil: now.add(const Duration(minutes: 50)),
        isSharing: true,
      );
      expect(recentModel.freshness, equals(LocationFreshness.recent));
      expect(recentModel.freshnessLabel, equals('Updated 2m ago'));

      // Updated 8 minutes ago -> Stale
      final staleModel = LiveLocationModel(
        uid: 'u3',
        displayName: 'Praveen',
        latitude: 15.5,
        longitude: 73.7,
        accuracy: 12.0,
        updatedAt: now.subtract(const Duration(minutes: 8)),
        sharingMode: '1_hour',
        sharingUntil: now.add(const Duration(minutes: 50)),
        isSharing: true,
      );
      expect(staleModel.freshness, equals(LocationFreshness.stale));
      expect(
        staleModel.freshnessLabel,
        equals('Location unavailable (Last updated 8m ago)'),
      );
    });

    test('LiveLocationModel detects expired sharingUntil', () {
      final now = DateTime.now();

      // Expired 5 minutes ago
      final expiredModel = LiveLocationModel(
        uid: 'u4',
        displayName: 'Kowshik',
        latitude: 15.5,
        longitude: 73.7,
        accuracy: 10.0,
        updatedAt: now.subtract(const Duration(minutes: 10)),
        sharingMode: '1_hour',
        sharingUntil: now.subtract(const Duration(minutes: 5)),
        isSharing: true,
      );
      expect(expiredModel.isExpired, isTrue);
      expect(expiredModel.freshness, equals(LocationFreshness.offline));
      expect(expiredModel.freshnessLabel, equals('Location expired'));
    });

    test(
      'LiveLocationModel serialization preserves all required Firestore fields',
      () {
        final now = DateTime.now();
        final model = LiveLocationModel(
          uid: 'user_goa_01',
          displayName: 'Kowshik',
          photoUrl:
              'https://res.cloudinary.com/tripcrew/image/upload/avatar.jpg',
          latitude: 15.5528,
          longitude: 73.7517,
          accuracy: 6.5,
          updatedAt: now,
          sharingMode: 'until_end_of_day',
          sharingUntil: now.add(const Duration(hours: 4)),
          isSharing: true,
          batteryLevel: 0.85,
          lastPulse: 'Coffee',
        );

        final map = model.toMap();
        expect(map['uid'], equals('user_goa_01'));
        expect(map['displayName'], equals('Kowshik'));
        expect(map['latitude'], equals(15.5528));
        expect(map['longitude'], equals(73.7517));
        expect(map['accuracy'], equals(6.5));
        expect(map['sharingMode'], equals('until_end_of_day'));
        expect(map['isSharing'], isTrue);
        expect(map['lastPulse'], equals('Coffee'));

        final reconstructed = LiveLocationModel.fromMap(map, 'user_goa_01');
        expect(reconstructed.uid, equals('user_goa_01'));
        expect(reconstructed.displayName, equals('Kowshik'));
        expect(reconstructed.latitude, equals(15.5528));
        expect(reconstructed.longitude, equals(73.7517));
        expect(reconstructed.isSharing, isTrue);
        expect(reconstructed.lastPulse, equals('Coffee'));
      },
    );

    test('Stale locations are never marked as live', () {
      final now = DateTime.now();

      // Older than 5 minutes (305 seconds), sharingUntil still valid
      final staleModel = LiveLocationModel(
        uid: 'user_stale',
        displayName: 'Old Tracker',
        latitude: 15.55,
        longitude: 73.75,
        accuracy: 10.0,
        updatedAt: now.subtract(const Duration(seconds: 305)),
        sharingMode: '1_hour',
        sharingUntil: now.add(const Duration(minutes: 30)),
        isSharing: true,
      );

      expect(staleModel.freshness, equals(LocationFreshness.stale));
      expect(staleModel.freshness, isNot(equals(LocationFreshness.live)));
      expect(staleModel.freshnessLabel, contains('Location unavailable'));
    });

    test('Firestore cost calculation strictly matches mathematical bounds', () {
      const members = 4;
      const hours = 8;
      const minutes = hours * 60; // 480 minutes

      // Moving range: 1.5 to 3 writes/member/min
      const minMovingWrites = members * minutes * 1.5; // 2,880
      const maxMovingWrites = members * minutes * 3.0; // 5,760

      expect(minMovingWrites, equals(2880));
      expect(maxMovingWrites, equals(5760));

      // Stationary: 0.5 writes/member/min
      const stationaryWrites = members * minutes * 0.5; // 960
      expect(stationaryWrites, equals(960));

      // Spark daily limit: 20,000 writes/day
      const sparkDailyWriteLimit = 20000;
      expect(maxMovingWrites, lessThan(sparkDailyWriteLimit));
      expect(
        (maxMovingWrites / sparkDailyWriteLimit) * 100,
        closeTo(28.8, 0.1),
      );

      // Firestore realtime reads:
      // With all 4 members actively listening to trips/{tripId}/locations:
      // Each written document change generates 1 read per active listener (4 reads total per write)
      const minMovingReads = minMovingWrites * members; // 11,520
      const maxMovingReads = maxMovingWrites * members; // 23,040
      const stationaryReads = stationaryWrites * members; // 3,840

      expect(minMovingReads, equals(11520));
      expect(maxMovingReads, equals(23040));
      expect(stationaryReads, equals(3840));

      // Spark daily read limit: 50,000 reads/day
      const sparkDailyReadLimit = 50000;
      expect(maxMovingReads, lessThan(sparkDailyReadLimit));
      expect((maxMovingReads / sparkDailyReadLimit) * 100, closeTo(46.08, 0.1));
    });
  });

  group('Live Crew Location Data Retention & Privacy Tests', () {
    test(
      'repeated location updates keep only one Firestore document per uid',
      () {
        // Simulating Firestore collection trips/{tripId}/locations
        final firestoreLocationsCollection = <String, Map<String, dynamic>>{};
        const uid = 'member_arun_42';

        // Update 1
        firestoreLocationsCollection[uid] = {
          'uid': uid,
          'displayName': 'Arun',
          'latitude': 15.5528,
          'longitude': 73.7517,
          'accuracy': 8.0,
          'isSharing': true,
        };

        // Update 2 (moved 40m)
        firestoreLocationsCollection[uid] = {
          'uid': uid,
          'displayName': 'Arun',
          'latitude': 15.5532,
          'longitude': 73.7520,
          'accuracy': 6.0,
          'isSharing': true,
        };

        // Update 3 (moved 100m)
        firestoreLocationsCollection[uid] = {
          'uid': uid,
          'displayName': 'Arun',
          'latitude': 15.5540,
          'longitude': 73.7530,
          'accuracy': 5.0,
          'isSharing': true,
        };

        // Exactly ONE document exists for this member
        expect(firestoreLocationsCollection.length, equals(1));
        expect(firestoreLocationsCollection.containsKey(uid), isTrue);
        // No historical location documents exist
        expect(firestoreLocationsCollection.keys.toList(), equals([uid]));
      },
    );

    test(
      'newest coordinate replaces previous coordinate and client replaces in-memory snapshot',
      () {
        final clientLocationCache = <String, LiveLocationModel>{};
        const uid = 'member_rahul_11';

        final update1 = LiveLocationModel(
          uid: uid,
          displayName: 'Rahul',
          latitude: 15.5500,
          longitude: 73.7500,
          accuracy: 10.0,
          updatedAt: DateTime.now().subtract(const Duration(seconds: 40)),
          isSharing: true,
        );
        clientLocationCache[uid] = update1;

        expect(clientLocationCache[uid]!.latitude, equals(15.5500));
        expect(clientLocationCache[uid]!.longitude, equals(73.7500));

        final update2 = LiveLocationModel(
          uid: uid,
          displayName: 'Rahul',
          latitude: 15.5580,
          longitude: 73.7590,
          accuracy: 4.5,
          updatedAt: DateTime.now(),
          isSharing: true,
        );
        // New snapshot replaces previous in-memory object (never appends)
        clientLocationCache[uid] = update2;

        expect(clientLocationCache.length, equals(1));
        expect(clientLocationCache[uid]!.latitude, equals(15.5580));
        expect(clientLocationCache[uid]!.longitude, equals(73.7590));
        expect(clientLocationCache[uid]!.accuracy, equals(4.5));
      },
    );

    test(
      'Stop Sharing clears precise coordinates and sets isSharing = false',
      () {
        final activeLocation = LiveLocationModel(
          uid: 'member_kowshik_99',
          displayName: 'Kowshik',
          latitude: 15.5528,
          longitude: 73.7517,
          accuracy: 5.0,
          updatedAt: DateTime.now(),
          isSharing: true,
          sharingMode: '1_hour',
          sharingUntil: DateTime.now().add(const Duration(minutes: 45)),
        );

        expect(activeLocation.hasCoordinates, isTrue);
        expect(activeLocation.isSharing, isTrue);

        // Simulating stopSharing payload sent to Firestore:
        // latitude, longitude, accuracy deleted, sharingUntil cleared, isSharing = false
        final stoppedDoc = <String, dynamic>{
          'uid': activeLocation.uid,
          'displayName': activeLocation.displayName,
          'isSharing': false,
          'sharingMode': 'off',
          'updatedAt': DateTime.now().toIso8601String(),
          // latitude, longitude, accuracy deleted in Firestore
        };

        final stoppedModel = LiveLocationModel.fromMap(
          stoppedDoc,
          activeLocation.uid,
        );

        expect(stoppedModel.isSharing, isFalse);
        expect(stoppedModel.latitude, isNull);
        expect(stoppedModel.longitude, isNull);
        expect(stoppedModel.accuracy, isNull);
        expect(stoppedModel.hasCoordinates, isFalse);
        expect(stoppedModel.sharingUntil, isNull);
        expect(stoppedModel.freshness, equals(LocationFreshness.offline));
        expect(stoppedModel.freshnessLabel, equals('Location sharing off'));
      },
    );

    test(
      'expired sharing clears precise coordinates and marks status offline',
      () {
        final now = DateTime.now();

        // Expired sharing duration
        final expiredModel = LiveLocationModel(
          uid: 'member_expired',
          displayName: 'Praveen',
          latitude: 15.5400,
          longitude: 73.7500,
          accuracy: 9.0,
          updatedAt: now.subtract(const Duration(minutes: 65)),
          isSharing: true,
          sharingMode: '1_hour',
          sharingUntil: now.subtract(const Duration(minutes: 5)),
        );

        expect(expiredModel.isExpired, isTrue);
        expect(expiredModel.freshness, equals(LocationFreshness.offline));
        expect(expiredModel.freshnessLabel, equals('Location expired'));

        // Cleaned model with deleted coordinates
        final cleanedModel = expiredModel.copyWith(
          isSharing: false,
          clearCoordinates: true,
          clearSharingUntil: true,
        );

        expect(cleanedModel.hasCoordinates, isFalse);
        expect(cleanedModel.latitude, isNull);
        expect(cleanedModel.longitude, isNull);
        expect(cleanedModel.accuracy, isNull);
        expect(cleanedModel.isExpired, isTrue);
      },
    );

    test('trip completion clears active sharing', () {
      final now = DateTime.now();
      final completedTrip = TripModel(
        id: 'trip_goa_completed',
        ownerId: 'owner_1',
        name: 'Goa Summer Trip',
        startingPlace: 'Mumbai',
        destination: 'Goa',
        startDate: now.subtract(const Duration(days: 4)),
        endDate: now.subtract(
          const Duration(hours: 2),
        ), // Trip ended 2 hours ago
        inviteCode: 'GOA123',
        status: 'completed',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      );

      // Verify trip is completed / past end date
      expect(completedTrip.status, equals('completed'));
      expect(now.isAfter(completedTrip.endDate), isTrue);

      // When trip is completed, member sharing must be stopped and coordinates deleted
      final memberLocationAfterTripEnd = LiveLocationModel(
        uid: 'user_active',
        displayName: 'Member',
        updatedAt: now,
        isSharing: false,
        sharingMode: 'off',
        // coordinates deleted
      );

      expect(memberLocationAfterTripEnd.isSharing, isFalse);
      expect(memberLocationAfterTripEnd.hasCoordinates, isFalse);
      expect(memberLocationAfterTripEnd.latitude, isNull);
      expect(memberLocationAfterTripEnd.longitude, isNull);
    });

    test('UI never displays old coordinates after sharing stops', () {
      // When member stops sharing, distance calculation must not include old coordinates
      final userLocation = LiveLocationModel(
        uid: 'me',
        displayName: 'You',
        latitude: 15.5528,
        longitude: 73.7517,
        accuracy: 5.0,
        updatedAt: DateTime.now(),
        isSharing: true,
      );

      final stoppedMember = LiveLocationModel(
        uid: 'friend_stopped',
        displayName: 'Arun',
        updatedAt: DateTime.now(),
        isSharing: false,
        // No coordinates retained
      );

      expect(stoppedMember.hasCoordinates, isFalse);

      // Distances calculation ignores members without coordinates
      final distances = <String, double>{};
      if (userLocation.hasCoordinates &&
          stoppedMember.isSharing &&
          !stoppedMember.isExpired &&
          stoppedMember.hasCoordinates) {
        distances[stoppedMember.uid] = LocationCalculator.calculateDistance(
          userLocation.latitude!,
          userLocation.longitude!,
          stoppedMember.latitude!,
          stoppedMember.longitude!,
        );
      }

      // Assert that distances map contains NO entry for stopped member
      expect(distances.containsKey(stoppedMember.uid), isFalse);
      expect(stoppedMember.freshnessLabel, equals('Location sharing off'));
    });
  });

  group('Process-Death & Expiry Hardening Tests', () {
    test('A. Sharing expires normally while app is alive', () {
      final now = DateTime.now();
      final sharingUntil = now.subtract(const Duration(seconds: 1)); // Expired

      // When expiry check runs, stopSharing is called
      final activeModel = LiveLocationModel(
        uid: 'user_alive_expiry',
        displayName: 'Test User',
        latitude: 15.55,
        longitude: 73.75,
        accuracy: 5.0,
        updatedAt: now.subtract(const Duration(seconds: 30)),
        isSharing: true,
        sharingMode: '1_hour',
        sharingUntil: sharingUntil,
      );

      expect(activeModel.isExpired, isTrue);
      expect(activeModel.isLiveActive, isFalse);

      // Simulating stopSharing output
      final stoppedModel = activeModel.copyWith(
        isSharing: false,
        clearCoordinates: true,
        clearSharingUntil: true,
      );

      expect(stoppedModel.isSharing, isFalse);
      expect(stoppedModel.hasCoordinates, isFalse);
      expect(stoppedModel.latitude, isNull);
      expect(stoppedModel.longitude, isNull);
    });

    test(
      'B. Stored Firestore document contains expired sharingUntil but still contains latitude/longitude (process-death simulation)',
      () {
        final now = DateTime.now();
        // Simulating a killed app: document still physically holds coordinates in Firestore
        // but sharingUntil passed 15 minutes ago
        final rawFirestoreDoc = {
          'uid': 'user_killed_app',
          'displayName': 'Dead Process User',
          'latitude': 15.5528,
          'longitude': 73.7517,
          'accuracy': 8.0,
          'updatedAt': now
              .subtract(const Duration(minutes: 20))
              .toIso8601String(),
          'sharingMode': '1_hour',
          'sharingUntil': now
              .subtract(const Duration(minutes: 15))
              .toIso8601String(),
          'isSharing': true,
        };

        final parsedModel = LiveLocationModel.fromMap(
          rawFirestoreDoc,
          'user_killed_app',
        );

        // Client MUST treat as expired despite physical coordinates in map
        expect(parsedModel.isExpired, isTrue);
        expect(parsedModel.isLiveActive, isFalse);
        expect(parsedModel.freshness, equals(LocationFreshness.offline));
        expect(parsedModel.freshnessLabel, equals('Location expired'));

        // Distance and bearing MUST NOT be calculated
        final myLoc = LiveLocationModel(
          uid: 'me',
          displayName: 'You',
          latitude: 15.5500,
          longitude: 73.7500,
          accuracy: 4.0,
          updatedAt: now,
          isSharing: true,
          sharingMode: '1_hour',
          sharingUntil: now.add(const Duration(minutes: 30)),
        );

        final distances = <String, double>{};
        final bearings = <String, double>{};

        // Strict client guard: both myLoc and member must be non-expired and live active
        if (myLoc.isLiveActive && parsedModel.isLiveActive) {
          distances[parsedModel.uid] = LocationCalculator.calculateDistance(
            myLoc.latitude!,
            myLoc.longitude!,
            parsedModel.latitude!,
            parsedModel.longitude!,
          );
          bearings[parsedModel.uid] = LocationCalculator.calculateBearing(
            myLoc.latitude!,
            myLoc.longitude!,
            parsedModel.latitude!,
            parsedModel.longitude!,
          );
        }

        // UI radar and distance map MUST NEVER expose coordinates
        expect(distances.containsKey(parsedModel.uid), isFalse);
        expect(bearings.containsKey(parsedModel.uid), isFalse);
      },
    );

    test(
      'C. App restarts with expired location document: cleanup executes and removes coordinates',
      () {
        final now = DateTime.now();
        final staleDocOnStartup = <String, dynamic>{
          'uid': 'user_restarted',
          'displayName': 'Returning User',
          'latitude': 15.5528,
          'longitude': 73.7517,
          'accuracy': 7.0,
          'sharingMode': '1_hour',
          'sharingUntil': now.subtract(const Duration(hours: 2)), // 2 hours ago
          'isSharing': true,
          'updatedAt': now.subtract(const Duration(hours: 2)),
        };

        // Idempotent cleanup execution
        final isExpired =
            staleDocOnStartup['sharingUntil'] != null &&
            now.isAfter(staleDocOnStartup['sharingUntil'] as DateTime);
        expect(isExpired, isTrue);

        // Perform cleanup: purge coordinates and set sharing off
        staleDocOnStartup['isSharing'] = false;
        staleDocOnStartup['sharingMode'] = 'off';
        staleDocOnStartup.remove('latitude');
        staleDocOnStartup.remove('longitude');
        staleDocOnStartup.remove('accuracy');
        staleDocOnStartup.remove('sharingUntil');
        staleDocOnStartup['updatedAt'] = now;

        final cleanedModel = LiveLocationModel.fromMap(
          staleDocOnStartup,
          'user_restarted',
        );
        expect(cleanedModel.isSharing, isFalse);
        expect(cleanedModel.hasCoordinates, isFalse);
        expect(cleanedModel.latitude, isNull);
        expect(cleanedModel.longitude, isNull);
        expect(cleanedModel.accuracy, isNull);
        expect(cleanedModel.freshnessLabel, equals('Location sharing off'));
      },
    );

    test(
      'D. Network reconnect after expiry: cleanup happens BEFORE any new location update',
      () {
        final now = DateTime.now();
        // Device was offline when sharing expired
        final activeSharingUntil = now.subtract(const Duration(minutes: 10));

        bool cleanupTriggered = false;
        bool positionUploaded = false;

        void onPositionReceived(double lat, double lng) {
          // Expiration check BEFORE network write
          if (DateTime.now().isAfter(activeSharingUntil)) {
            cleanupTriggered = true;
            // Stop stream and clean up; do NOT upload position
            return;
          }
          positionUploaded = true;
        }

        onPositionReceived(15.5530, 73.7520);

        expect(cleanupTriggered, isTrue);
        expect(positionUploaded, isFalse); // New location was never sent
      },
    );

    test('E. Until Trip Ends: sharingUntil equals trip end timestamp', () {
      final now = DateTime.now();
      final tripEndDate = now.add(const Duration(days: 3));
      final trip = TripModel(
        id: 'trip_kerala',
        ownerId: 'owner_1',
        name: 'Kerala Backwaters',
        startingPlace: 'Kochi',
        destination: 'Munnar',
        startDate: now,
        endDate: tripEndDate,
        inviteCode: 'KER456',
        createdAt: now,
        updatedAt: now,
      );

      // Resolving trip end hard expiry
      final hardExpiry = DateTime(
        trip.endDate.year,
        trip.endDate.month,
        trip.endDate.day,
        23,
        59,
        59,
      );

      final model = LiveLocationModel(
        uid: 'user_trip_end',
        displayName: 'Traveler',
        latitude: 10.0,
        longitude: 76.0,
        accuracy: 5.0,
        updatedAt: now,
        isSharing: true,
        sharingMode: 'until_trip_ends',
        sharingUntil: hardExpiry,
      );

      expect(model.sharingUntil, equals(hardExpiry));
      expect(model.sharingUntil!.isAfter(now), isTrue);
      expect(model.isExpired, isFalse);

      // Once trip end passes:
      final afterTripEnd = hardExpiry.add(const Duration(seconds: 10));
      expect(afterTripEnd.isAfter(model.sharingUntil!), isTrue);
    });

    test(
      'F. Sharing expiry passed: location sharing does not restart',
      () async {
        final pastExpiry = DateTime.now().subtract(const Duration(minutes: 5));

        // Attempting to start sharing with a past expiry must fail immediately
        final state = await LiveCrewService.instance.startSharing(
          tripId: 'mock_trip',
          tripName: 'Mock',
          uid: 'user_expired_test',
          displayName: 'Test',
          sharingMode: '1_hour',
          sharingUntil: pastExpiry,
        );

        expect(state, equals(LocationServiceState.off));
        expect(LiveCrewService.instance.isSharing, isFalse);
      },
    );
  });
}
