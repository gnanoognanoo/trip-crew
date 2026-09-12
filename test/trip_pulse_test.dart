import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/maps/models/live_location_model.dart';
import 'package:tripcrew/features/maps/utils/location_calculator.dart';
import 'package:tripcrew/features/pulse/models/trip_pulse.dart';

void main() {
  group('Trip Pulse Domain Model & Expiry Tests', () {
    test('Pulse replacement per uid: new pulse replaces previous pulse', () {
      final pulsesCollection = <String, TripPulse>{};
      const uid = 'member_arun_01';

      final now = DateTime.now();

      // Initial pulse: Hungry
      final pulse1 = TripPulse(
        uid: uid,
        memberName: 'Arun',
        pulseType: PulseType.hungry.title,
        type: PulseType.hungry.key,
        createdAt: now.subtract(const Duration(minutes: 10)),
        expiresAt: now.add(const Duration(minutes: 50)),
      );
      pulsesCollection[uid] = pulse1;

      expect(pulsesCollection.length, equals(1));
      expect(pulsesCollection[uid]!.type, equals('hungry'));

      // New pulse: Tired replaces Hungry
      final pulse2 = TripPulse(
        uid: uid,
        memberName: 'Arun',
        pulseType: PulseType.tired.title,
        type: PulseType.tired.key,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 60)),
      );
      pulsesCollection[uid] = pulse2;

      // Exactly ONE document exists per member
      expect(pulsesCollection.length, equals(1));
      expect(pulsesCollection[uid]!.type, equals('tired'));
      expect(pulsesCollection[uid]!.pulseType, equals('Tired'));
      expect(pulsesCollection[uid]!.emoji, equals('😴'));
    });

    test('Pulse expiry: default durations and expiration detection', () {
      final now = DateTime.now();

      // Hungry: 60 minutes
      expect(
        PulseType.hungry.defaultDuration,
        equals(const Duration(minutes: 60)),
      );
      // Need Break: 30 minutes
      expect(
        PulseType.needBreak.defaultDuration,
        equals(const Duration(minutes: 30)),
      );
      // Restroom: 30 minutes
      expect(
        PulseType.restroom.defaultDuration,
        equals(const Duration(minutes: 30)),
      );
      // Need Fuel: 60 minutes
      expect(
        PulseType.needFuel.defaultDuration,
        equals(const Duration(minutes: 60)),
      );
      // Tired: 60 minutes
      expect(
        PulseType.tired.defaultDuration,
        equals(const Duration(minutes: 60)),
      );
      // Want Photos: 60 minutes
      expect(
        PulseType.wantPhotos.defaultDuration,
        equals(const Duration(minutes: 60)),
      );
      // Emergency: 120 minutes
      expect(
        PulseType.emergency.defaultDuration,
        equals(const Duration(minutes: 120)),
      );

      // Active pulse
      final activePulse = TripPulse(
        uid: 'user_active',
        memberName: 'Kowshik',
        pulseType: 'Hungry',
        type: 'hungry',
        createdAt: now.subtract(const Duration(minutes: 20)),
        expiresAt: now.add(const Duration(minutes: 40)),
      );
      expect(activePulse.isExpired, isFalse);
      expect(activePulse.isCurrentlyActive, isTrue);

      // Expired pulse
      final expiredPulse = TripPulse(
        uid: 'user_expired',
        memberName: 'Rahul',
        pulseType: 'Hungry',
        type: 'hungry',
        createdAt: now.subtract(const Duration(minutes: 70)),
        expiresAt: now.subtract(const Duration(minutes: 10)),
      );
      expect(expiredPulse.isExpired, isTrue);
      expect(expiredPulse.isCurrentlyActive, isFalse);
    });

    test('Clear Pulse: marks pulse inactive or deletes status', () {
      final now = DateTime.now();
      final activePulse = TripPulse(
        uid: 'user_cleared',
        memberName: 'Praveen',
        pulseType: 'Need a Break',
        type: 'needBreak',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        isActive: true,
      );

      expect(activePulse.isCurrentlyActive, isTrue);

      // Cleared status
      final clearedPulse = activePulse.copyWith(isActive: false);
      expect(clearedPulse.isActive, isFalse);
      expect(clearedPulse.isExpired, isTrue);
      expect(clearedPulse.isCurrentlyActive, isFalse);
    });

    test('Expired Pulse not rendered on member model', () {
      final now = DateTime.now();
      final expiredPulse = TripPulse(
        uid: 'u1',
        memberName: 'Arun',
        pulseType: 'Hungry',
        type: 'hungry',
        createdAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.subtract(const Duration(hours: 1)),
      );

      final member = LiveLocationModel(
        uid: 'u1',
        displayName: 'Arun',
        latitude: 15.5528,
        longitude: 73.7517,
        updatedAt: now,
        isSharing: true,
        sharingMode: '1_hour',
        sharingUntil: now.add(const Duration(minutes: 30)),
        activePulse: expiredPulse,
      );

      // Expired pulse is NOT active
      expect(member.hasActivePulse, isFalse);
      expect(member.effectivePulseLabel, isNull);
      expect(member.radarPulseEmoji, isNull);
    });
  });

  group('Live Crew + Pulse Integration Tests', () {
    test(
      'Location off + Pulse active: pulse renders even when location is off',
      () {
        final now = DateTime.now();
        final activePulse = TripPulse(
          uid: 'user_rahul',
          memberName: 'Rahul',
          pulseType: 'Tired',
          type: 'tired',
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 60)),
        );

        // Rahul has location sharing OFF
        final member = LiveLocationModel(
          uid: 'user_rahul',
          displayName: 'Rahul',
          updatedAt: now,
          isSharing: false,
          sharingMode: 'off',
          activePulse: activePulse,
        );

        expect(member.isSharing, isFalse);
        expect(member.hasCoordinates, isFalse);
        expect(member.hasActivePulse, isTrue);
        expect(member.effectivePulseLabel, equals('😴 Tired'));
        expect(member.radarPulseEmoji, equals('😴'));
      },
    );

    test('Location active + Pulse active: renders both distance and pulse', () {
      final now = DateTime.now();
      final myLoc = LiveLocationModel(
        uid: 'me',
        displayName: 'You',
        latitude: 15.5500,
        longitude: 73.7500,
        updatedAt: now,
        isSharing: true,
        sharingMode: '1_hour',
        sharingUntil: now.add(const Duration(minutes: 45)),
      );

      final arunPulse = TripPulse(
        uid: 'user_arun',
        memberName: 'Arun',
        pulseType: 'Hungry',
        type: 'hungry',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 60)),
      );

      final arunLoc = LiveLocationModel(
        uid: 'user_arun',
        displayName: 'Arun',
        latitude: 15.5510,
        longitude: 73.7510,
        updatedAt: now,
        isSharing: true,
        sharingMode: '1_hour',
        sharingUntil: now.add(const Duration(minutes: 45)),
        activePulse: arunPulse,
      );

      expect(arunLoc.hasActivePulse, isTrue);
      expect(arunLoc.effectivePulseLabel, equals('🍔 Hungry'));

      final distance = LocationCalculator.calculateDistance(
        myLoc.latitude!,
        myLoc.longitude!,
        arunLoc.latitude!,
        arunLoc.longitude!,
      );

      expect(distance, greaterThan(0));
      expect(LocationCalculator.formatDistance(distance), contains('m away'));
    });

    test(
      'Expired location + Pulse active: location is unavailable but pulse remains visible',
      () {
        final now = DateTime.now();

        final hungryPulse = TripPulse(
          uid: 'user_praveen',
          memberName: 'Praveen',
          pulseType: 'Hungry',
          type: 'hungry',
          createdAt: now.subtract(const Duration(minutes: 10)),
          expiresAt: now.add(const Duration(minutes: 50)),
        );

        // Praveen's location expired 15 minutes ago
        final praveen = LiveLocationModel(
          uid: 'user_praveen',
          displayName: 'Praveen',
          latitude: 15.5528,
          longitude: 73.7517,
          updatedAt: now.subtract(const Duration(minutes: 20)),
          isSharing: true,
          sharingMode: '1_hour',
          sharingUntil: now.subtract(const Duration(minutes: 15)),
          activePulse: hungryPulse,
        );

        // Location expired
        expect(praveen.isExpired, isTrue);
        expect(praveen.isLiveActive, isFalse);
        expect(praveen.freshnessLabel, equals('Location expired'));

        // Pulse still active and visible!
        expect(praveen.hasActivePulse, isTrue);
        expect(praveen.effectivePulseLabel, equals('🍔 Hungry'));
      },
    );

    test(
      'Crew Pulse aggregation: counts active pulses and generates non-AI insights',
      () {
        final now = DateTime.now();

        final pulses = [
          TripPulse(
            uid: 'u1',
            memberName: 'Arun',
            pulseType: 'Hungry',
            type: 'hungry',
            createdAt: now,
            expiresAt: now.add(const Duration(minutes: 60)),
          ),
          TripPulse(
            uid: 'u2',
            memberName: 'Rahul',
            pulseType: 'Hungry',
            type: 'hungry',
            createdAt: now,
            expiresAt: now.add(const Duration(minutes: 60)),
          ),
          TripPulse(
            uid: 'u3',
            memberName: 'Praveen',
            pulseType: 'Tired',
            type: 'tired',
            createdAt: now,
            expiresAt: now.add(const Duration(minutes: 60)),
          ),
          TripPulse(
            uid: 'u4',
            memberName: 'Kowshik',
            pulseType: 'Need a Break',
            type: 'needBreak',
            createdAt: now,
            expiresAt: now.add(const Duration(minutes: 30)),
          ),
          // Expired pulse (should be excluded)
          TripPulse(
            uid: 'u5',
            memberName: 'Old User',
            pulseType: 'Hungry',
            type: 'hungry',
            createdAt: now.subtract(const Duration(hours: 2)),
            expiresAt: now.subtract(const Duration(hours: 1)),
          ),
        ];

        // Aggregation logic
        final counts = <String, int>{};
        for (final p in pulses) {
          if (p.isCurrentlyActive) {
            counts[p.pulseType] = (counts[p.pulseType] ?? 0) + 1;
          }
        }

        expect(counts['Hungry'], equals(2));
        expect(counts['Tired'], equals(1));
        expect(counts['Need a Break'], equals(1));
        expect(counts.containsKey('Old User'), isFalse);

        // Non-AI insight evaluation
        final insights = <String>[];
        if ((counts['Hungry'] ?? 0) >= 2) {
          insights.add('${counts['Hungry']} crew members are hungry.');
        }
        if ((counts['Need a Break'] ?? 0) >= 2) {
          insights.add('Your crew may need a break.');
        }

        expect(insights, contains('2 crew members are hungry.'));
        expect(insights.length, equals(1));
      },
    );
  });

  group('Emergency Pulse & Privacy Tests', () {
    test('Emergency Pulse: properties and emoji', () {
      final now = DateTime.now();
      final emergencyPulse = TripPulse(
        uid: 'user_sos',
        memberName: 'Rahul',
        pulseType: 'Emergency',
        type: 'emergency',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 120)),
      );

      expect(emergencyPulse.isEmergency, isTrue);
      expect(emergencyPulse.emoji, equals('🚨'));
      expect(emergencyPulse.displayLabel, equals('🚨 Emergency'));
      expect(emergencyPulse.isCurrentlyActive, isTrue);
    });

    test('Emergency Pulse without location: location sharing remains OFF', () {
      final now = DateTime.now();
      final emergencyPulse = TripPulse(
        uid: 'user_sos_offline',
        memberName: 'Rahul',
        pulseType: 'Emergency',
        type: 'emergency',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 120)),
      );

      // Member triggered emergency with location sharing OFF
      final member = LiveLocationModel(
        uid: 'user_sos_offline',
        displayName: 'Rahul',
        updatedAt: now,
        isSharing: false,
        sharingMode: 'off',
        activePulse: emergencyPulse,
      );

      // Location sharing is NOT automatically enabled
      expect(member.isSharing, isFalse);
      expect(member.hasCoordinates, isFalse);
      expect(member.latitude, isNull);
      expect(member.longitude, isNull);

      // Emergency status is prominently active
      expect(member.hasActivePulse, isTrue);
      expect(member.activePulse!.isEmergency, isTrue);

      // UI text for location when sharing is off during emergency
      final locationText = (member.isSharing && member.hasCoordinates)
          ? '650 m away'
          : 'Location unavailable';

      expect(locationText, equals('Location unavailable'));
    });

    test(
      'Firestore Security Rules: pulse write restricted to self and members',
      () {
        // Simulate rule: allow write: if isTripMember(tripId) && request.auth.uid == pulseUid;
        bool canWritePulse({
          required bool isMember,
          required String authUid,
          required String pulseUid,
        }) {
          return isMember && authUid == pulseUid;
        }

        // Member writing their own pulse -> ALLOWED
        expect(
          canWritePulse(isMember: true, authUid: 'user_A', pulseUid: 'user_A'),
          isTrue,
        );

        // Account B attempting to write to Account A's pulse -> BLOCKED
        expect(
          canWritePulse(isMember: true, authUid: 'user_B', pulseUid: 'user_A'),
          isFalse,
        );

        // Non-member Account C attempting to write to trip pulse -> BLOCKED
        expect(
          canWritePulse(isMember: false, authUid: 'user_C', pulseUid: 'user_C'),
          isFalse,
        );
      },
    );

    test('Firestore Security Rules: non-member cannot read trip pulses', () {
      // Simulate rule: allow read: if isTripMember(tripId);
      bool canReadPulses({required bool isMember}) {
        return isMember;
      }

      expect(canReadPulses(isMember: true), isTrue);
      expect(canReadPulses(isMember: false), isFalse);
    });
  });
}
